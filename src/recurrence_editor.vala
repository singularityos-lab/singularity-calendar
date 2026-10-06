using Gtk;
using GLib;
using Singularity.Calendar;
using Singularity.Widgets;

namespace Singularity.Apps.Calendar {

    public class RecurrenceEditor : Box {
        private DropDown frequency_drop;
        private SpinButton interval_spin;
        private Label interval_unit;
        private Box interval_box;
        private Box weekdays_box;
        private ToggleButton[] weekday_toggles = {};
        private DropDown monthly_drop;
        private DropDown end_drop;
        private SpinButton count_spin;
        private DateButton until_button;
        private Box end_box;
        private Label summary;
        private DateTime start;
        private bool updating = false;

        public signal void changed ();

        private const RecurrenceFrequency[] FREQUENCIES = {
            RecurrenceFrequency.NONE, RecurrenceFrequency.DAILY, RecurrenceFrequency.WEEKLY,
            RecurrenceFrequency.MONTHLY, RecurrenceFrequency.YEARLY
        };

        public RecurrenceEditor (DateTime start, string? rrule) {
            Object (orientation: Orientation.VERTICAL, spacing: 10);
            this.start = start;

            var freq_row = new Box (Orientation.HORIZONTAL, 8);
            var freq_label = new Label (_("Repeat"));
            freq_label.hexpand = true;
            freq_label.xalign = 0;
            frequency_drop = new DropDown.from_strings ({ _("Never"), _("Daily"), _("Weekly"), _("Monthly"), _("Yearly") });
            freq_row.append (freq_label);
            freq_row.append (frequency_drop);
            append (freq_row);

            interval_box = new Box (Orientation.HORIZONTAL, 8);
            var every = new Label (_("Every"));
            every.hexpand = true;
            every.xalign = 0;
            interval_spin = new SpinButton.with_range (1, 99, 1);
            interval_unit = new Label ("");
            interval_unit.width_chars = 7;
            interval_unit.xalign = 0;
            interval_box.append (every);
            interval_box.append (interval_spin);
            interval_box.append (interval_unit);
            append (interval_box);

            weekdays_box = new Box (Orientation.HORIZONTAL, 4);
            weekdays_box.halign = Align.CENTER;
            for (int i = 0; i < 7; i++) {
                int weekday = (CalendarLayout.first_weekday () - 1 + i) % 7 + 1;
                string name = RecurrenceRule.weekday_name (weekday, true);
                var toggle = new ToggleButton.with_label (name.substring (0, name.index_of_nth_char (2)));
                toggle.add_css_class ("cal-weekday-toggle");
                toggle.tooltip_text = RecurrenceRule.weekday_name (weekday);
                toggle.set_data<int> ("weekday", weekday);
                toggle.toggled.connect (on_changed);
                weekday_toggles += toggle;
                weekdays_box.append (toggle);
            }
            append (weekdays_box);

            monthly_drop = new DropDown.from_strings ({ "", "", "" });
            monthly_drop.hexpand = true;
            append (monthly_drop);

            end_box = new Box (Orientation.HORIZONTAL, 8);
            var ends = new Label (_("Ends"));
            ends.hexpand = true;
            ends.xalign = 0;
            end_drop = new DropDown.from_strings ({ _("Never"), _("On Date"), _("After") });
            count_spin = new SpinButton.with_range (1, 999, 1);
            count_spin.value = 10;
            until_button = new DateButton (start.add_months (3));
            end_box.append (ends);
            end_box.append (end_drop);
            end_box.append (count_spin);
            end_box.append (until_button);
            append (end_box);

            summary = new Label ("");
            summary.add_css_class ("dim-label");
            summary.wrap = true;
            summary.xalign = 0;
            append (summary);

            load (rrule);
            frequency_drop.notify["selected"].connect (on_changed);
            interval_spin.value_changed.connect (on_changed);
            monthly_drop.notify["selected"].connect (on_changed);
            end_drop.notify["selected"].connect (on_changed);
            count_spin.value_changed.connect (on_changed);
            until_button.changed.connect (on_changed);
            refresh_visibility ();
        }

        public void set_start (DateTime value) {
            start = value;
            update_monthly_labels ();
            refresh_visibility ();
        }

        private void on_changed () {
            if (updating) return;
            refresh_visibility ();
            changed ();
        }

        private int week_of_month (DateTime date) {
            return (date.get_day_of_month () - 1) / 7 + 1;
        }

        private void update_monthly_labels () {
            string weekday = RecurrenceRule.weekday_name (start.get_day_of_week ());
            var model = new StringList ({
                _("On day %d").printf (start.get_day_of_month ()),
                _("On the %s %s").printf (RecurrenceRule.ordinal (week_of_month (start)), weekday),
                _("On the last %s").printf (weekday)
            });
            uint selected = monthly_drop.selected;
            updating = true;
            monthly_drop.model = model;
            monthly_drop.selected = selected;
            updating = false;
        }

        private void load (string? rrule) {
            updating = true;
            update_monthly_labels ();
            var rule = RecurrenceRule.parse (rrule);
            if (rule == null) {
                frequency_drop.selected = 0;
                foreach (var toggle in weekday_toggles) toggle.active = toggle.get_data<int> ("weekday") == start.get_day_of_week ();
                updating = false;
                return;
            }
            for (int i = 0; i < FREQUENCIES.length; i++) if (FREQUENCIES[i] == rule.frequency) frequency_drop.selected = i;
            interval_spin.value = rule.interval;
            foreach (var toggle in weekday_toggles) {
                bool on = false;
                foreach (var day in rule.by_weekday) if (day.weekday == toggle.get_data<int> ("weekday")) on = true;
                toggle.active = on || (rule.by_weekday.length == 0 && toggle.get_data<int> ("weekday") == start.get_day_of_week ());
            }
            if (rule.frequency == RecurrenceFrequency.MONTHLY || rule.frequency == RecurrenceFrequency.YEARLY) {
                if (rule.by_weekday.length > 0) monthly_drop.selected = rule.by_weekday[0].position < 0 ? 2 : 1;
                else monthly_drop.selected = 0;
            }
            if (rule.count > 0) {
                end_drop.selected = 2;
                count_spin.value = rule.count;
            } else if (rule.until != null) {
                end_drop.selected = 1;
                until_button.date = rule.until;
            } else {
                end_drop.selected = 0;
            }
            updating = false;
        }

        private RecurrenceFrequency frequency () {
            return FREQUENCIES[frequency_drop.selected.clamp (0, FREQUENCIES.length - 1)];
        }

        private void refresh_visibility () {
            var freq = frequency ();
            bool repeats = freq != RecurrenceFrequency.NONE;
            interval_box.visible = repeats;
            weekdays_box.visible = freq == RecurrenceFrequency.WEEKLY;
            monthly_drop.visible = freq == RecurrenceFrequency.MONTHLY || freq == RecurrenceFrequency.YEARLY;
            end_box.visible = repeats;
            count_spin.visible = end_drop.selected == 2;
            until_button.visible = end_drop.selected == 1;
            int n = (int) interval_spin.value;
            switch (freq) {
                case RecurrenceFrequency.DAILY: interval_unit.label = ngettext ("day", "days", n); break;
                case RecurrenceFrequency.WEEKLY: interval_unit.label = ngettext ("week", "weeks", n); break;
                case RecurrenceFrequency.MONTHLY: interval_unit.label = ngettext ("month", "months", n); break;
                case RecurrenceFrequency.YEARLY: interval_unit.label = ngettext ("year", "years", n); break;
                default: interval_unit.label = ""; break;
            }
            var rule = RecurrenceRule.parse (rrule ());
            summary.label = rule != null ? rule.describe (start) : "";
            summary.visible = rule != null;
        }

        public string rrule () {
            var freq = frequency ();
            if (freq == RecurrenceFrequency.NONE) return "";
            var rule = new RecurrenceRule (freq, (int) interval_spin.value);
            if (freq == RecurrenceFrequency.WEEKLY) {
                RecurrenceWeekday[] days = {};
                foreach (var toggle in weekday_toggles) {
                    if (toggle.active) days += RecurrenceWeekday (toggle.get_data<int> ("weekday"));
                }
                if (days.length == 0) days += RecurrenceWeekday (start.get_day_of_week ());
                rule.by_weekday = days;
            } else if (freq == RecurrenceFrequency.MONTHLY || freq == RecurrenceFrequency.YEARLY) {
                if (freq == RecurrenceFrequency.YEARLY && monthly_drop.selected != 0) rule.by_month = { start.get_month () };
                if (monthly_drop.selected == 1) {
                    rule.by_weekday = { RecurrenceWeekday (start.get_day_of_week (), week_of_month (start)) };
                } else if (monthly_drop.selected == 2) {
                    rule.by_weekday = { RecurrenceWeekday (start.get_day_of_week (), -1) };
                }
            }
            if (end_drop.selected == 2) {
                rule.count = (int) count_spin.value;
            } else if (end_drop.selected == 1) {
                var d = until_button.date;
                rule.until = new DateTime.local (d.get_year (), d.get_month (), d.get_day_of_month (), 23, 59, 59);
            }
            return rule.to_rrule ();
        }
    }

    public class DateButton : Box {
        private Gtk.Calendar calendar;
        private MenuButton button;
        private DateTime _date;

        public signal void changed ();

        public DateTime date {
            get { return _date; }
            set {
                _date = value;
                button.label = value.format ("%a %-d %b %Y");
                calendar.year = value.get_year ();
                calendar.month = value.get_month () - 1;
                calendar.day = value.get_day_of_month ();
            }
        }

        public DateButton (DateTime initial) {
            Object (orientation: Orientation.HORIZONTAL, spacing: 0);
            valign = Align.CENTER;
            calendar = new Gtk.Calendar ();
            var pop = new Popover ();
            pop.child = calendar;
            button = new MenuButton ();
            button.popover = pop;
            button.always_show_arrow = false;
            append (button);
            date = initial;
            calendar.day_selected.connect (() => {
                var picked = calendar.get_date ();
                _date = new DateTime.local (picked.get_year (), picked.get_month (), picked.get_day_of_month (),
                    _date.get_hour (), _date.get_minute (), 0);
                button.label = _date.format ("%a %-d %b %Y");
                pop.popdown ();
                changed ();
            });
        }
    }

    public class TimeDrop : Box {
        private DropDown drop;
        private string[] values = {};
        private bool updating = false;

        public signal void changed ();

        public string time {
            owned get {
                uint index = drop.selected;
                return index < values.length ? values[index] : "09:00";
            }
            set {
                updating = true;
                select (value);
                updating = false;
            }
        }

        public TimeDrop (string initial) {
            Object (orientation: Orientation.HORIZONTAL, spacing: 0);
            valign = Align.CENTER;
            drop = new DropDown.from_strings ({});
            drop.add_css_class ("cal-time-drop");
            append (drop);
            select (initial);
            drop.notify["selected"].connect (() => {
                if (!updating) changed ();
            });
        }

        private void select (string value) {
            string[] parts = value.split (":");
            int wanted = parts.length == 2 ? int.parse (parts[0]) * 60 + int.parse (parts[1]) : 540;
            string[] list = {};
            bool exact = false;
            for (int m = 0; m < 24 * 60; m += 15) {
                if (!exact && wanted < m) {
                    list += "%02d:%02d".printf (wanted / 60, wanted % 60);
                    exact = true;
                }
                if (m == wanted) exact = true;
                list += "%02d:%02d".printf (m / 60, m % 60);
            }
            if (!exact) list += "%02d:%02d".printf (wanted / 60, wanted % 60);
            values = list;
            drop.model = new StringList (list);
            string key = "%02d:%02d".printf (wanted / 60, wanted % 60);
            for (int i = 0; i < list.length; i++) {
                if (list[i] == key) drop.selected = i;
            }
        }
    }
}
