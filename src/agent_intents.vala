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

        private static CalendarEvent find (Json.Object args, out WritableCalendarProvider provider) throws Error {
            string id = text (args, "id");
            if (id.contains ("@")) id = id.substring (0, id.index_of ("@"));
            foreach (var p in EventStore.editable_providers (CalendarManager.get_default ())) {
                var e = p.find_event (id);
                if (e != null) {
                    CalendarEvent found = e;
                    if (found.calendar_id == null || found.calendar_id == "") found.calendar_id = p.id;
                    provider = p;
                    if (args.has_member ("occurrence")) {
                        if (!found.is_recurring ()) throw new IOError.INVALID_ARGUMENT ("the event does not repeat, leave out occurrence");
                        var at = when (args, "occurrence");
                        int64 duration = found.end_time.difference (found.start_time);
                        found.occurrence_start = at;
                        found.start_time = at;
                        found.end_time = at.add (duration);
                    }
                    return found;
                }
            }
            throw new IOError.NOT_FOUND ("no event %s in a calendar that can be written", id);
        }

        private static async void free_slots (Json.Object args, owned Singularity.AppIntentReply reply) {
            try {
                var from = when (args, "from");
                var to = when (args, "to");
                if (to.compare (from) <= 0) throw new IOError.INVALID_ARGUMENT ("to must come after from");
                int64 minutes = args.has_member ("minutes") ? args.get_int_member ("minutes").clamp (5, 1440) : 30;
                int start_h, start_m, end_h, end_m;
                hours (args.has_member ("day_start") ? text (args, "day_start") : "09:00", out start_h, out start_m);
                hours (args.has_member ("day_end") ? text (args, "day_end") : "18:00", out end_h, out end_m);
                bool weekends = args.has_member ("weekends") && args.get_boolean_member ("weekends");
                var busy = new Gee.ArrayList<CalendarEvent?> ();
                foreach (var p in CalendarManager.get_default ().get_providers ()) {
                    foreach (var e in yield p.get_events (from, to)) {
                        if (e != null && !e.all_day) busy.add (e);
                    }
                }
                busy.sort ((a, b) => a.start_time.compare (b.start_time));
                var list = new Json.Array ();
                var day = new DateTime (from.get_timezone (), from.get_year (), from.get_month (), from.get_day_of_month (), 0, 0, 0);
                while (day.compare (to) < 0 && list.get_length () < 100) {
                    int wd = day.get_day_of_week ();
                    if (weekends || wd < 6) {
                        var open = day.add_hours (start_h).add_minutes (start_m);
                        var close = day.add_hours (end_h).add_minutes (end_m);
                        if (open.compare (from) < 0) open = from;
                        if (close.compare (to) > 0) close = to;
                        var cursor = open;
                        foreach (var e in busy) {
                            if (e.end_time.compare (cursor) <= 0 || e.start_time.compare (close) >= 0) continue;
                            if (e.start_time.difference (cursor) >= minutes * TimeSpan.MINUTE) add_slot (list, cursor, e.start_time);
                            if (e.end_time.compare (cursor) > 0) cursor = e.end_time;
                        }
                        if (close.difference (cursor) >= minutes * TimeSpan.MINUTE) add_slot (list, cursor, close);
                    }
                    day = day.add_days (1);
                }
                var o = new Json.Object ();
                o.set_int_member ("minutes", minutes);
                o.set_array_member ("slots", list);
                var node = new Json.Node (Json.NodeType.OBJECT);
                node.set_object (o);
                reply (node, null);
            } catch (Error e) {
                reply (null, e);
            }
        }

        private static void add_slot (Json.Array list, DateTime start, DateTime end) {
            var o = new Json.Object ();
            o.set_string_member ("start", start.format_iso8601 ());
            o.set_string_member ("end", end.format_iso8601 ());
            o.set_int_member ("minutes", end.difference (start) / TimeSpan.MINUTE);
            list.add_object_element (o);
        }

        private static void hours (string value, out int h, out int m) throws Error {
            var parts = value.split (":");
            if (parts.length != 2 || !int.try_parse (parts[0], out h, null, 10) || !int.try_parse (parts[1], out m, null, 10) || h < 0 || h > 24 || m < 0 || m > 59) {
                throw new IOError.INVALID_ARGUMENT ("give times as HH:MM, not %s", value);
            }
        }

        internal static void install (CalendarApp app) {
            var agent = app.agent;
            agent.add_async_intent ("calendar_list", "List the events between two ISO 8601 dates.",
                "{\"type\":\"object\",\"properties\":{\"from\":{\"type\":\"string\"},\"to\":{\"type\":\"string\"}},\"required\":[\"from\",\"to\"]}",
                Singularity.AppIntentRisk.READ, (args, reply) => {
                    list_events.begin (args, (owned) reply);
                });
            agent.add_intent ("calendar_add", "Add an event to the first calendar that can be written, or to the one named.",
                "{\"type\":\"object\",\"properties\":{\"title\":{\"type\":\"string\"},\"start\":{\"type\":\"string\"},\"end\":{\"type\":\"string\"},\"all_day\":{\"type\":\"boolean\"},\"location\":{\"type\":\"string\"},\"description\":{\"type\":\"string\"},\"calendar\":{\"type\":\"string\"}},\"required\":[\"title\",\"start\",\"end\"]}",
                Singularity.AppIntentRisk.UNDOABLE, (args) => {
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
            agent.add_intent ("calendar_update", "Change an event by id: title, start, end, all_day, location, description or calendar (moves it). Moving start alone keeps the length. For one date of a repeating event give occurrence (its start); otherwise the whole series changes.",
                "{\"type\":\"object\",\"properties\":{\"id\":{\"type\":\"string\"},\"occurrence\":{\"type\":\"string\"},\"title\":{\"type\":\"string\"},\"start\":{\"type\":\"string\"},\"end\":{\"type\":\"string\"},\"all_day\":{\"type\":\"boolean\"},\"location\":{\"type\":\"string\"},\"description\":{\"type\":\"string\"},\"calendar\":{\"type\":\"string\"}},\"required\":[\"id\"]}",
                Singularity.AppIntentRisk.UNDOABLE, (args) => {
                    WritableCalendarProvider provider;
                    var original = find (args, out provider);
                    CalendarEvent edited = original;
                    edited.attendees = EventStore.copy_attendees (original.attendees);
                    int64 duration = original.end_time.difference (original.start_time);
                    if (args.has_member ("start")) {
                        edited.start_time = when (args, "start");
                        edited.end_time = edited.start_time.add (duration);
                    }
                    if (args.has_member ("end")) edited.end_time = when (args, "end");
                    if (edited.end_time.compare (edited.start_time) < 0) throw new IOError.INVALID_ARGUMENT ("the event would end before it starts");
                    if (args.has_member ("all_day")) edited.all_day = args.get_boolean_member ("all_day");
                    if (args.has_member ("title")) edited.title = text (args, "title");
                    if (args.has_member ("location")) edited.location = text (args, "location");
                    if (args.has_member ("description")) edited.description = text (args, "description");
                    var store = new EventStore (CalendarManager.get_default ());
                    if (args.has_member ("calendar")) {
                        if (store.writable (text (args, "calendar")) == null) throw new IOError.NOT_FOUND ("no calendar %s can be written", text (args, "calendar"));
                        edited.calendar_id = text (args, "calendar");
                    }
                    store.save (original, edited, original.occurrence_start != null ? EditScope.THIS : EditScope.ALL);
                    return brief (edited);
                });
            agent.add_intent ("calendar_delete", "Delete an event by id. For one date of a repeating event give occurrence (its start); otherwise the whole series goes.",
                "{\"type\":\"object\",\"properties\":{\"id\":{\"type\":\"string\"},\"occurrence\":{\"type\":\"string\"}},\"required\":[\"id\"]}",
                Singularity.AppIntentRisk.IRREVERSIBLE, (args) => {
                    WritableCalendarProvider provider;
                    var e = find (args, out provider);
                    var node = brief (e);
                    new EventStore (CalendarManager.get_default ()).remove (e, e.occurrence_start != null ? EditScope.THIS : EditScope.ALL);
                    bool gone = e.occurrence_start != null || provider.find_event (e.id) == null;
                    node.get_object ().set_boolean_member ("verified", gone);
                    return node;
                });
            agent.add_async_intent ("calendar_free_slots", "Find free time between two ISO 8601 dates, within working hours (day_start and day_end as HH:MM, default 09:00 to 18:00, weekdays unless weekends is true), at least minutes long (default 30). All-day events do not block time.",
                "{\"type\":\"object\",\"properties\":{\"from\":{\"type\":\"string\"},\"to\":{\"type\":\"string\"},\"minutes\":{\"type\":\"integer\"},\"day_start\":{\"type\":\"string\"},\"day_end\":{\"type\":\"string\"},\"weekends\":{\"type\":\"boolean\"}},\"required\":[\"from\",\"to\"]}",
                Singularity.AppIntentRisk.READ, (args, reply) => {
                    free_slots.begin (args, (owned) reply);
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
