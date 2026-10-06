using Gtk;
using GLib;
using Singularity;
using Singularity.Calendar;
using Singularity.Widgets;

namespace SingularityCalendarWidget {

    public class UpcomingProvider : Object, OverviewWidgetProvider {
        public string id           { get { return "calendar.upcoming"; } }
        public string provider_id  { get { return "dev.sinty.calendar"; } }
        public string display_name { get { return _("Upcoming Events"); } }
        public string icon_name    { get { return "dev.sinty.calendar"; } }
        public WidgetSize[] supported_sizes {
            get {
                if (_sizes == null) {
                    _sizes = new WidgetSize[2];
                    _sizes[0] = WidgetSize (2, 2);
                    _sizes[1] = WidgetSize (4, 2);
                }
                return _sizes;
            }
        }
        private WidgetSize[] _sizes;

        public Gtk.Widget create_instance (string instance_id, WidgetSize size, Variant? config) {
            return new UpcomingInstance (size);
        }
    }

    public class UpcomingInstance : Gtk.Box {
        private const int MAX_ROWS = 6;
        private static CssProvider? css = null;
        private CalendarManager mgr;
        private Gtk.Box list;
        private Gtk.Box? week = null;
        private uint tick_id = 0;
        private ulong changed_id = 0;
        private ulong providers_id = 0;
        private bool loading = false;
        private bool again = false;

        public UpcomingInstance (WidgetSize size) {
            Object (orientation: Orientation.HORIZONTAL, spacing: 14);
            ensure_css ();
            add_css_class ("overview-calendar");
            hexpand = true;
            vexpand = true;

            mgr = CalendarManager.get_default ();
            LocalProvider.register_all (mgr);
            WebCalendarProvider.register_all (mgr);
            AccountCalendars.register_all (mgr);

            if (size.w >= 4) {
                week = new Gtk.Box (Orientation.HORIZONTAL, 2);
                week.homogeneous = true;
                week.hexpand = true;
                week.valign = Align.FILL;
                week.add_css_class ("overview-calendar-week");
                append (week);
            }

            list = new Gtk.Box (Orientation.VERTICAL, 2);
            list.hexpand = true;
            list.vexpand = true;
            list.valign = Align.START;
            append (list);

            changed_id = mgr.events_changed.connect (() => reload ());
            providers_id = mgr.providers_changed.connect (() => reload ());
            tick_id = Timeout.add_seconds (60, () => {
                reload ();
                return Source.CONTINUE;
            });
            reload ();

            destroy.connect (() => {
                if (tick_id != 0) Source.remove (tick_id);
                tick_id = 0;
                if (changed_id != 0) mgr.disconnect (changed_id);
                if (providers_id != 0) mgr.disconnect (providers_id);
                changed_id = 0;
                providers_id = 0;
            });
        }

        private static void ensure_css () {
            if (css != null) return;
            css = new CssProvider ();
            css.load_from_string ("""
.overview-calendar {
    border-radius: 20px;
    background: alpha(@window_bg_color, 0.35);
    border: 1px solid alpha(@window_fg_color, 0.08);
    box-shadow: 0 1px 2px alpha(black, 0.18) inset, 0 1px 4px alpha(black, 0.12);
    padding: 14px 16px;
}
.overview-calendar-day {
    font-size: 12px;
    font-weight: bold;
    opacity: 0.7;
    margin-top: 4px;
}
.overview-calendar-row {
    padding: 3px 6px;
    border-radius: 8px;
    min-height: 0;
}
.overview-calendar-row:hover {
    background-color: alpha(@window_fg_color, 0.08);
}
.overview-calendar-time {
    font-size: 12px;
    font-feature-settings: "tnum";
    opacity: 0.7;
}
.overview-calendar .cal-event-dot {
    border-radius: 999px;
    min-width: 8px;
    min-height: 8px;
}
.overview-calendar-week {
    border-right: 1px solid alpha(@window_fg_color, 0.1);
    padding-right: 10px;
}
.overview-calendar-weekday {
    font-size: 11px;
    font-weight: bold;
    opacity: 0.6;
}
.overview-calendar-date {
    font-size: 15px;
    min-width: 28px;
    min-height: 28px;
    border-radius: 999px;
}
.overview-calendar-date.today {
    background-color: @accent_bg_color;
    color: @accent_fg_color;
    font-weight: bold;
}
.overview-calendar-bar {
    border-radius: 3px;
    min-height: 5px;
}
""");
            StyleContext.add_provider_for_display (Gdk.Display.get_default (), css, STYLE_PROVIDER_PRIORITY_USER + 1);
        }

        private void reload () {
            if (loading) {
                again = true;
                return;
            }
            loading = true;
            load.begin ((obj, res) => {
                load.end (res);
                loading = false;
                if (again) {
                    again = false;
                    reload ();
                }
            });
        }

        private async void load () {
            var now = new DateTime.now_local ();
            var today = CalendarLayout.day_start (now);
            var week_start = CalendarLayout.week_start (now);
            var range_start = week_start.compare (today) < 0 ? week_start : today;
            var range_end = week_start.add_days (7).compare (today.add_days (2)) > 0 ? week_start.add_days (7) : today.add_days (2);
            var events = yield mgr.get_events (range_start, range_end);
            events.sort ((a, b) => {
                if (a.all_day != b.all_day) return a.all_day ? -1 : 1;
                return a.start_time.compare (b.start_time);
            });
            fill_list (events, now, today);
            if (week != null) fill_week (events, now, week_start);
        }

        private void clear (Gtk.Box box) {
            Widget? child;
            while ((child = box.get_first_child ()) != null) box.remove (child);
        }

        private void fill_list (Gee.List<CalendarEvent?> events, DateTime now, DateTime today) {
            clear (list);
            int shown = 0;
            int hidden = 0;
            string[] titles = { _("Today"), _("Tomorrow") };
            for (int i = 0; i < 2; i++) {
                var day = today.add_days (i);
                var rows = new Gee.ArrayList<CalendarEvent?> ();
                foreach (var evt in events) {
                    if (!CalendarLayout.covers_day (evt, day)) continue;
                    if (i == 0 && !evt.all_day && evt.end_time.compare (now) <= 0) continue;
                    rows.add (evt);
                }
                if (rows.size == 0) continue;
                if (shown >= MAX_ROWS) {
                    hidden += rows.size;
                    continue;
                }
                var heading = new Label (titles[i]);
                heading.xalign = 0;
                heading.add_css_class ("overview-calendar-day");
                list.append (heading);
                foreach (var evt in rows) {
                    if (shown >= MAX_ROWS) {
                        hidden++;
                        continue;
                    }
                    list.append (build_row (evt));
                    shown++;
                }
            }
            if (shown == 0) {
                var empty = new Label (_("Nothing planned for today or tomorrow"));
                empty.add_css_class ("dim-label");
                empty.wrap = true;
                empty.justify = Justification.CENTER;
                empty.vexpand = true;
                empty.valign = Align.CENTER;
                list.valign = Align.FILL;
                list.append (empty);
                return;
            }
            list.valign = Align.START;
            if (hidden > 0) {
                var more = new Label (ngettext ("%d more event", "%d more events", hidden).printf (hidden));
                more.xalign = 0;
                more.add_css_class ("caption");
                more.add_css_class ("dim-label");
                more.margin_start = 6;
                list.append (more);
            }
        }

        private string event_color (CalendarEvent evt) {
            if (evt.color != null && evt.color != "") return evt.color;
            var provider = mgr.get_provider (evt.calendar_id);
            return provider != null ? provider.color : "";
        }

        private Widget build_row (CalendarEvent evt) {
            var button = new Button ();
            button.has_frame = false;
            button.add_css_class ("overview-calendar-row");
            var box = new Gtk.Box (Orientation.HORIZONTAL, 8);
            var dot = new Gtk.Box (Orientation.HORIZONTAL, 0);
            dot.add_css_class ("cal-event-dot");
            dot.valign = Align.CENTER;
            CalendarLayout.tint (dot, event_color (evt));
            box.append (dot);
            var time = new Label (evt.all_day ? _("All day") : CalendarLayout.time_label (evt.start_time.to_local ()));
            time.add_css_class ("overview-calendar-time");
            time.xalign = 0;
            time.width_chars = 6;
            box.append (time);
            var title = new Label (evt.title != "" ? evt.title : _("Untitled Event"));
            title.xalign = 0;
            title.hexpand = true;
            title.ellipsize = Pango.EllipsizeMode.END;
            box.append (title);
            button.child = box;
            button.tooltip_text = evt.location != "" ? "%s\n%s".printf (CalendarLayout.time_range (evt), evt.location) : CalendarLayout.time_range (evt);
            string target = "%s\t%s\t%lld".printf (evt.calendar_id, evt.id, evt.start_time.to_unix ());
            button.clicked.connect (() => open_event (target));
            return button;
        }

        private void fill_week (Gee.List<CalendarEvent?> events, DateTime now, DateTime week_start) {
            clear (week);
            for (int i = 0; i < 7; i++) {
                var day = week_start.add_days (i);
                var column = new Gtk.Box (Orientation.VERTICAL, 4);
                column.halign = Align.CENTER;
                var name = new Label (CalendarLayout.weekday_label (i, true));
                name.add_css_class ("overview-calendar-weekday");
                column.append (name);
                var date = new Label (day.get_day_of_month ().to_string ());
                date.add_css_class ("overview-calendar-date");
                if (CalendarLayout.same_day (day, now)) date.add_css_class ("today");
                column.append (date);
                int count = 0;
                foreach (var evt in events) {
                    if (!CalendarLayout.covers_day (evt, day)) continue;
                    if (count < 4) {
                        var bar = new Gtk.Box (Orientation.HORIZONTAL, 0);
                        bar.add_css_class ("cal-event-dot");
                        bar.add_css_class ("overview-calendar-bar");
                        bar.set_size_request (22, 5);
                        CalendarLayout.tint (bar, event_color (evt));
                        bar.tooltip_text = evt.title;
                        column.append (bar);
                    }
                    count++;
                }
                if (count > 4) {
                    var more = new Label ("+%d".printf (count - 4));
                    more.add_css_class ("caption");
                    more.add_css_class ("dim-label");
                    column.append (more);
                }
                var click = new GestureClick ();
                var captured = day;
                click.released.connect (() => open_day (captured));
                column.add_controller (click);
                week.append (column);
            }
        }

        private void open_event (string target) {
            activate_calendar ("open-event", new Variant.string (target));
        }

        private void open_day (DateTime day) {
            activate_calendar ("show-day", new Variant.int64 (day.to_unix ()));
        }

        private void activate_calendar (string action, Variant parameter) {
            var platform = new VariantBuilder (new VariantType ("a{sv}"));
            var args = new VariantBuilder (new VariantType ("av"));
            args.add ("v", parameter);
            Bus.get.begin (BusType.SESSION, null, (obj, res) => {
                try {
                    var bus = Bus.get.end (res);
                    bus.call.begin ("dev.sinty.calendar", "/dev/sinty/calendar", "org.freedesktop.Application",
                        "ActivateAction", new Variant ("(s@av@a{sv})", action, args.end (), platform.end ()),
                        null, DBusCallFlags.NONE, 10000, null, (o, r) => {
                            try {
                                bus.call.end (r);
                            } catch (Error e) {
                                warning ("calendar widget: %s", e.message);
                            }
                        });
                } catch (Error e) {
                    warning ("calendar widget: %s", e.message);
                }
            });
        }
    }

    [CCode (cname = "singularity_calendar_widget_new")]
    public static Object singularity_calendar_widget_new () {
        return new UpcomingProvider ();
    }
}
