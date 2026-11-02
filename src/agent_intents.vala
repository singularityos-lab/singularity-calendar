using GLib;
using Gee;
using Singularity.Calendar;

namespace Singularity.Apps.Calendar {

    internal class CalendarIntents : Object {
        private static string text (Json.Object args, string key) {
            return args.has_member (key) ? args.get_string_member (key) : "";
        }

        private static DateTime when (Json.Object args, string key) throws Error {
            var d = new DateTime.from_iso8601 (text (args, key), new TimeZone.local ());
            if (d == null) throw new IOError.INVALID_ARGUMENT ("%s must be an ISO 8601 date and time", key);
            return d;
        }

        private static Json.Node brief (CalendarEvent e) {
            var b = new Json.Builder ();
            b.begin_object ();
            b.set_member_name ("id").add_string_value (e.id);
            b.set_member_name ("calendar").add_string_value (e.calendar_id ?? "");
            b.set_member_name ("title").add_string_value (e.title ?? "");
            b.set_member_name ("start").add_string_value (e.start_time.format_iso8601 ());
            b.set_member_name ("end").add_string_value (e.end_time.format_iso8601 ());
            b.set_member_name ("all_day").add_boolean_value (e.all_day);
            b.set_member_name ("location").add_string_value (e.location ?? "");
            b.set_member_name ("description").add_string_value (e.description ?? "");
            b.end_object ();
            return b.get_root ();
        }

        private static async void list_events (Json.Object args, owned Singularity.AppIntentReply reply) {
            try {
                var from = when (args, "from");
                var to = when (args, "to");
                var list = new Json.Array ();
                foreach (var p in CalendarManager.get_default ().get_providers ()) {
                    foreach (var e in yield p.get_events (from, to)) {
                        if (e != null) list.add_element (brief (e));
                    }
                }
                var node = new Json.Node (Json.NodeType.ARRAY);
                node.set_array (list);
                reply (node, null);
            } catch (Error e) {
                reply (null, e);
            }
        }

        internal static void install (CalendarApp app) {
            var agent = app.agent;
            agent.add_async_intent ("calendar_list", "List the events between two ISO 8601 dates.",
                "{\"type\":\"object\",\"properties\":{\"from\":{\"type\":\"string\"},\"to\":{\"type\":\"string\"}},\"required\":[\"from\",\"to\"]}",
                Singularity.AppIntentRisk.READ, (args, reply) => {
                    app.activate ();
                    list_events.begin (args, (owned) reply);
                });
            agent.add_intent ("calendar_add", "Add an event to the first calendar that can be written, or to the one named.",
                "{\"type\":\"object\",\"properties\":{\"title\":{\"type\":\"string\"},\"start\":{\"type\":\"string\"},\"end\":{\"type\":\"string\"},\"all_day\":{\"type\":\"boolean\"},\"location\":{\"type\":\"string\"},\"description\":{\"type\":\"string\"},\"calendar\":{\"type\":\"string\"}},\"required\":[\"title\",\"start\",\"end\"]}",
                Singularity.AppIntentRisk.UNDOABLE, (args) => {
                    app.activate ();
                    var mgr = CalendarManager.get_default ();
                    var writable = EventStore.editable_providers (mgr);
                    string id = text (args, "calendar");
                    if (id == "" && writable.size > 0) id = writable[0].id;
                    var store = new EventStore (mgr);
                    if (store.writable (id) == null) throw new IOError.NOT_FOUND ("no calendar can be written");
                    bool day = args.has_member ("all_day") && args.get_boolean_member ("all_day");
                    var e = EventStore.blank (when (args, "start"), when (args, "end"), day);
                    e.calendar_id = id;
                    e.title = text (args, "title");
                    e.location = text (args, "location");
                    e.description = text (args, "description");
                    store.add (e);
                    return brief (e);
                });
            agent.add_intent ("calendar_show_day", "Show a day in the window.",
                "{\"type\":\"object\",\"properties\":{\"date\":{\"type\":\"string\"}},\"required\":[\"date\"]}",
                Singularity.AppIntentRisk.READ, (args) => {
                    app.activate_action ("show-day", new Variant.int64 (when (args, "date").to_unix ()));
                    return null;
                });
        }
    }
}
