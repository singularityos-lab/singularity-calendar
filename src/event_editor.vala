using Gtk;
using GLib;
using Gee;
using Singularity.Calendar;
using Singularity.Widgets;

namespace Singularity.Apps.Calendar {

    public class EventEditor : AppDialog {
        private const int[] REMINDERS = { -1, 0, 5, 10, 15, 30, 60, 120, 1440, 2880, 10080 };

        private CalendarApp app;
        private CalendarEvent? original;
        private CalendarEvent draft;
        private Gee.List<WritableCalendarProvider> calendars;

        private Entry title_entry;
        private Entry location_entry;
        private DropDown calendar_drop;
        private Switch all_day_switch;
        private DateButton start_date;
        private DateButton end_date;
        private TimeDrop start_time;
        private TimeDrop end_time;
        private RecurrenceEditor recurrence;
        private DropDown reminder_drop;
        private TextView notes;
        private PreferencesGroup people_group;
        private Entry people_entry;
        private Gee.ArrayList<CalendarAttendee> attendees;
        private Label error_label;
        private int64 duration;

        public signal void saved (CalendarEvent? original, CalendarEvent edited);
        public signal void delete_requested (CalendarEvent evt);

        public EventEditor (CalendarApp app, CalendarEvent? original, CalendarEvent draft) {
            base (app, true);
            this.app = app;
            this.original = original;
            this.draft = draft;
            attendees = EventStore.copy_attendees (draft.attendees);
            duration = draft.end_time.difference (draft.start_time);
            set_title (original == null ? _("New Event") : _("Edit Event"));
            set_default_size (460, 720);

            var scroll = new ScrolledWindow ();
            scroll.hscrollbar_policy = PolicyType.NEVER;
            scroll.vexpand = true;
            scroll.propagate_natural_height = true;
            scroll.max_content_height = 620;

            var body = new Box (Orientation.VERTICAL, 14);
            body.margin_top = 8;
            body.margin_bottom = 12;
            body.margin_start = 18;
            body.margin_end = 18;

            title_entry = new Entry ();
            title_entry.placeholder_text = _("Event Name");
            title_entry.text = draft.title ?? "";
            title_entry.add_css_class ("title-3");
            title_entry.activate.connect (on_save);
            body.append (title_entry);

            location_entry = new Entry ();
            location_entry.placeholder_text = _("Location or Video Call Link");
            location_entry.text = draft.location ?? "";
            location_entry.primary_icon_name = "mark-location-symbolic";
            body.append (location_entry);

            calendars = EventStore.editable_providers (CalendarManager.get_default ());
            string[] names = {};
            uint selected = 0;
            for (int i = 0; i < calendars.size; i++) {
                names += EventStore.label_for (calendars[i]);
                if (calendars[i].id == draft.calendar_id) selected = i;
            }
            calendar_drop = new DropDown.from_strings (names);
            calendar_drop.selected = selected;
            body.append (labeled (_("Calendar"), calendar_drop));

            all_day_switch = new Switch ();
            all_day_switch.active = draft.all_day;
            all_day_switch.valign = Align.CENTER;
            body.append (labeled (_("All Day"), all_day_switch));

            start_date = new DateButton (draft.start_time);
            start_time = new TimeDrop (draft.start_time.format ("%H:%M"));
            var end_display = draft.all_day ? draft.end_time.add_days (-1) : draft.end_time;
            if (end_display.compare (draft.start_time) < 0) end_display = draft.start_time;
            end_date = new DateButton (end_display);
            end_time = new TimeDrop (draft.end_time.format ("%H:%M"));
            var start_box = new Box (Orientation.HORIZONTAL, 6);
            start_box.append (start_date);
            start_box.append (start_time);
            var end_box = new Box (Orientation.HORIZONTAL, 6);
            end_box.append (end_date);
            end_box.append (end_time);
            body.append (labeled (_("Starts"), start_box));
            body.append (labeled (_("Ends"), end_box));

            recurrence = new RecurrenceEditor (draft.start_time, draft.recurrence);
            body.append (recurrence);

            string[] reminder_names = {};
            uint reminder_index = 0;
            int current = draft.alarms != null && draft.alarms.length > 0 ? draft.alarms[0] : -1;
            for (int i = 0; i < REMINDERS.length; i++) {
                reminder_names += reminder_label (REMINDERS[i]);
                if (REMINDERS[i] == current) reminder_index = i;
            }
            reminder_drop = new DropDown.from_strings (reminder_names);
            reminder_drop.selected = reminder_index;
            body.append (labeled (_("Reminder"), reminder_drop));

            people_group = new PreferencesGroup (_("People"));
            body.append (people_group);
            var add_box = new Box (Orientation.HORIZONTAL, 6);
            people_entry = new Entry ();
            people_entry.hexpand = true;
            people_entry.placeholder_text = _("Add people by email");
            people_entry.input_purpose = InputPurpose.EMAIL;
            people_entry.activate.connect (add_people);
            var add_btn = new Button.from_icon_name ("list-add-symbolic");
            add_btn.tooltip_text = _("Invite");
            add_btn.clicked.connect (add_people);
            add_box.append (people_entry);
            add_box.append (add_btn);
            body.append (add_box);
            rebuild_people ();

            var notes_label = new Label (_("Notes"));
            notes_label.xalign = 0;
            notes_label.add_css_class ("heading");
            body.append (notes_label);
            notes = new TextView ();
            notes.wrap_mode = WrapMode.WORD_CHAR;
            notes.buffer.text = draft.description ?? "";
            notes.top_margin = 6;
            notes.bottom_margin = 6;
            notes.left_margin = 8;
            notes.right_margin = 8;
            var notes_frame = new Frame (null);
            notes_frame.child = notes;
            notes_frame.set_size_request (-1, 90);
            body.append (notes_frame);

            error_label = new Label ("");
            error_label.add_css_class ("error");
            error_label.visible = false;
            error_label.wrap = true;
            body.append (error_label);

            scroll.child = body;
            content_box.append (scroll);

            var actions = new Box (Orientation.HORIZONTAL, 8);
            actions.margin_top = 8;
            actions.margin_bottom = 14;
            actions.margin_start = 18;
            actions.margin_end = 18;
            if (original != null) {
                var delete_btn = new Button.with_label (_("Delete"));
                delete_btn.add_css_class ("destructive-action");
                delete_btn.clicked.connect (() => {
                    close_dialog ();
                    delete_requested (original);
                });
                actions.append (delete_btn);
            }
            var spacer = new Box (Orientation.HORIZONTAL, 0);
            spacer.hexpand = true;
            actions.append (spacer);
            var cancel = new Button.with_label (_("Cancel"));
            cancel.clicked.connect (() => close_dialog ());
            set_cancel_button (cancel);
            var save = new Button.with_label (_("Save"));
            save.add_css_class ("suggested-action");
            save.clicked.connect (on_save);
            actions.append (cancel);
            actions.append (save);
            content_box.append (actions);

            all_day_switch.notify["active"].connect (() => sync_all_day ());
            start_date.changed.connect (on_start_changed);
            start_time.changed.connect (on_start_changed);
            end_date.changed.connect (remember_duration);
            end_time.changed.connect (remember_duration);
            sync_all_day ();
            title_entry.grab_focus ();
        }

        private static string reminder_label (int minutes) {
            if (minutes < 0) return _("None");
            if (minutes == 0) return _("At time of event");
            if (minutes < 60) return ngettext ("%d minute before", "%d minutes before", minutes).printf (minutes);
            if (minutes < 1440) return ngettext ("%d hour before", "%d hours before", minutes / 60).printf (minutes / 60);
            if (minutes < 10080) return ngettext ("%d day before", "%d days before", minutes / 1440).printf (minutes / 1440);
            return _("1 week before");
        }

        private Box labeled (string text, Widget widget) {
            var row = new Box (Orientation.HORIZONTAL, 12);
            var label = new Label (text);
            label.xalign = 0;
            label.hexpand = true;
            label.valign = Align.CENTER;
            row.append (label);
            widget.valign = Align.CENTER;
            row.append (widget);
            return row;
        }

        private void sync_all_day () {
            bool all_day = all_day_switch.active;
            start_time.visible = !all_day;
            end_time.visible = !all_day;
        }

        private DateTime compose (DateButton date, TimeDrop time) {
            var d = date.date;
            string[] parts = time.time.split (":");
            int hour = all_day_switch.active ? 0 : int.parse (parts[0]);
            int minute = all_day_switch.active ? 0 : int.parse (parts[1]);
            return new DateTime.local (d.get_year (), d.get_month (), d.get_day_of_month (), hour, minute, 0);
        }

        private void on_start_changed () {
            var start = compose (start_date, start_time);
            var end = start.add (duration);
            end_date.date = end;
            end_time.time = end.format ("%H:%M");
            recurrence.set_start (start);
        }

        private void remember_duration () {
            var start = compose (start_date, start_time);
            var end = compose (end_date, end_time);
            if (end.compare (start) > 0) duration = end.difference (start);
        }

        private static bool valid_email (string email) {
            int at = email.index_of_char ('@');
            return at > 0 && email.last_index_of_char ('.') > at + 1 && !email.contains (" ");
        }

        private void add_people () {
            string text = people_entry.text.strip ();
            if (text == "") return;
            bool bad = false;
            foreach (string part in text.replace (";", ",").split (",")) {
                string item = part.strip ();
                if (item == "") continue;
                string name = "";
                string email = item;
                int lt = item.index_of_char ('<');
                int gt = item.index_of_char ('>');
                if (lt >= 0 && gt > lt) {
                    name = item.substring (0, lt).strip ().replace ("\"", "");
                    email = item.substring (lt + 1, gt - lt - 1).strip ();
                }
                if (!valid_email (email)) {
                    bad = true;
                    continue;
                }
                bool exists = false;
                foreach (var a in attendees) if (a.email.down () == email.down ()) exists = true;
                if (!exists) attendees.add (new CalendarAttendee (email, name));
            }
            people_entry.text = bad ? text : "";
            if (bad) show_error (_("Some addresses are not valid email addresses."));
            rebuild_people ();
        }

        public static string status_label (string status) {
            switch (status) {
                case "ACCEPTED": return _("Going");
                case "DECLINED": return _("Not going");
                case "TENTATIVE": return _("Maybe");
                case "DELEGATED": return _("Delegated");
                default: return _("Awaiting reply");
            }
        }

        public static string status_icon (string status) {
            switch (status) {
                case "ACCEPTED": return "emblem-ok-symbolic";
                case "DECLINED": return "window-close-symbolic";
                case "TENTATIVE": return "dialog-question-symbolic";
                default: return "mail-unread-symbolic";
            }
        }

        private void rebuild_people () {
            people_group.clear ();
            string owner = app.settings.get_string ("owner-email");
            string organizer = draft.organizer != null && draft.organizer != "" ? draft.organizer : owner;
            string hint;
            if (attendees.size == 0) {
                hint = _("Invite people and send them the event by email.");
            } else if (organizer != "") {
                hint = _("Organized by %s").printf (organizer);
            } else {
                hint = _("Set your email in Calendar settings to organize invitations.");
            }
            people_group.description = hint;
            foreach (var attendee in attendees) {
                var row = new ActionRow (attendee.display_name (), attendee.name != "" ? attendee.email : null,
                    status_icon (attendee.status));
                row.tooltip_text = status_label (attendee.status);
                var optional = new ToggleButton.with_label (_("Optional"));
                optional.add_css_class ("flat");
                optional.active = attendee.role == "OPT-PARTICIPANT";
                optional.valign = Align.CENTER;
                var cap = attendee;
                optional.toggled.connect (() => cap.role = optional.active ? "OPT-PARTICIPANT" : "REQ-PARTICIPANT");
                row.add_suffix (optional);
                var remove = new Button.from_icon_name ("user-trash-symbolic");
                remove.add_css_class ("flat");
                remove.valign = Align.CENTER;
                remove.tooltip_text = _("Remove");
                remove.clicked.connect (() => {
                    attendees.remove (cap);
                    rebuild_people ();
                });
                row.add_suffix (remove);
                people_group.add_row (row);
            }
        }

        private void show_error (string text) {
            error_label.label = text;
            error_label.visible = true;
        }

        private void on_save () {
            var start = compose (start_date, start_time);
            var end = compose (end_date, end_time);
            if (all_day_switch.active) end = end.add_days (1);
            if (end.compare (start) <= 0) {
                show_error (_("The event must end after it starts."));
                return;
            }
            if (calendars.size == 0) {
                show_error (_("There is no calendar to save this event to."));
                return;
            }
            if (people_entry.text.strip () != "") add_people ();
            CalendarEvent edited = draft;
            edited.title = title_entry.text.strip () != "" ? title_entry.text.strip () : _("Untitled Event");
            edited.location = location_entry.text.strip ();
            edited.description = notes.buffer.text.strip ();
            edited.all_day = all_day_switch.active;
            edited.start_time = start;
            edited.end_time = end;
            edited.calendar_id = calendars[(int) calendar_drop.selected.clamp (0, calendars.size - 1)].id;
            edited.recurrence = recurrence.rrule ();
            int reminder = REMINDERS[reminder_drop.selected.clamp (0, REMINDERS.length - 1)];
            int[] alarms = {};
            if (reminder >= 0) alarms += reminder;
            if (draft.alarms != null) {
                for (int i = 1; i < draft.alarms.length; i++) alarms += draft.alarms[i];
            }
            edited.alarms = alarms;
            edited.attendees = attendees;
            if (attendees.size > 0 && (edited.organizer == null || edited.organizer == "")) {
                edited.organizer = app.settings.get_string ("owner-email");
                edited.organizer_name = app.settings.get_string ("owner-name");
            }
            if (attendees.size == 0) {
                edited.organizer = "";
                edited.organizer_name = "";
            }
            close_dialog ();
            saved (original, edited);
        }
    }
}
