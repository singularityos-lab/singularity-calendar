using Gtk;
using Singularity.Calendar;

namespace Singularity.Apps.Calendar {

    public class AgentCard : Object {
        private static bool styled = false;

        private static string text (Json.Object o, string key) {
            return o.has_member (key) && o.get_member (key).get_value_type () == typeof (string) ? o.get_string_member (key) : "";
        }

        private static string color_of (string calendar) {
            foreach (var p in CalendarManager.get_default ().get_providers ()) {
                if (p.id == calendar) return p.color;
            }
            return "";
        }

        private static CalendarEvent? parse (Json.Node node) {
            if (node.get_node_type () != Json.NodeType.OBJECT) return null;
            var o = node.get_object ();
            var zone = new TimeZone.local ();
            var start = new DateTime.from_iso8601 (text (o, "start"), zone);
            var end = new DateTime.from_iso8601 (text (o, "end"), zone);
            if (start == null || end == null) return null;
            CalendarEvent e = CalendarEvent ();
            e.id = text (o, "id");
            e.calendar_id = text (o, "calendar");
            e.title = text (o, "title");
            e.location = text (o, "location");
            e.description = text (o, "description");
            e.start_time = start.to_local ();
            e.end_time = end.to_local ();
            e.all_day = o.has_member ("all_day") && o.get_boolean_member ("all_day");
            e.color = color_of (e.calendar_id);
            return e;
        }

        private static void show_day (DateTime day) {
            Bus.get.begin (BusType.SESSION, null, (obj, res) => {
                try {
                    var bus = Bus.get.end (res);
                    var args = new VariantBuilder (new VariantType ("av"));
                    args.add ("v", new Variant.int64 (day.to_unix ()));
                    bus.call.begin ("dev.sinty.calendar", "/dev/sinty/calendar", "org.gtk.Actions", "Activate",
                        new Variant ("(sava{sv})", "show-day", args, new VariantBuilder (new VariantType ("a{sv}"))),
                        null, DBusCallFlags.NONE, 10000, null);
                } catch (Error e) {
                    warning ("Calendar card: %s", e.message);
                }
            });
        }

        public static Widget? build (string intent, string args, string result) {
            Json.Node root;
            try {
                root = Json.from_string (result);
            } catch (Error e) {
                return null;
            }
            if (root == null) return null;
            var events = new Gee.ArrayList<CalendarEvent?> ();
            if (root.get_node_type () == Json.NodeType.ARRAY) {
                foreach (var n in root.get_array ().get_elements ()) {
                    var e = parse (n);
                    if (e != null) events.add (e);
                }
            } else {
                var e = parse (root);
                if (e != null) events.add (e);
            }
            events.sort ((a, b) => a.start_time.compare (b.start_time));
            if (!styled) {
                var css = new CssProvider ();
                css.load_from_string (AgendaRows.STYLE);
                StyleContext.add_provider_for_display (Gdk.Display.get_default (), css, STYLE_PROVIDER_PRIORITY_USER + 1);
                styled = true;
            }
            var box = new Box (Orientation.VERTICAL, 2);
            if (events.size == 0) {
                var none = new Label (_("Nothing planned"));
                none.add_css_class ("dim-label");
                none.xalign = 0;
                box.append (none);
                return box;
            }
            string last_day = "";
            foreach (var evt in events) {
                string key = evt.start_time.format ("%Y-%m-%d");
                if (key != last_day) {
                    last_day = key;
                    var header = AgendaRows.day_header (evt.start_time);
                    if (box.get_first_child () == null) header.margin_top = 0;
                    box.append (header);
                }
                var row = AgendaRows.event_row (evt);
                var day = evt.start_time;
                row.clicked.connect (() => show_day (day));
                box.append (row);
            }
            return box;
        }
    }

    [CCode (cname = "singularity_calendar_card_new")]
    public Widget? agent_card_new (string intent, string args, string result) {
        LocalProvider.register_all (CalendarManager.get_default ());
        WebCalendarProvider.register_all (CalendarManager.get_default ());
        AccountCalendars.register_all (CalendarManager.get_default ());
        return AgentCard.build (intent, args, result);
    }
}
