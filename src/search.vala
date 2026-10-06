using GLib;
using Gee;
using Singularity.Calendar;

namespace Singularity.Apps.Calendar {

    public class CalendarSearch : Singularity.SearchProviderService {
        private const int MAX_RESULTS = 20;
        private const string TASKS_CALENDAR = "local-dev.sinty.tasks";
        private CalendarApp app;
        private HashMap<string, CalendarEvent?> found = new HashMap<string, CalendarEvent?> ();

        public CalendarSearch (CalendarApp app) {
            this.app = app;
        }

        public static string event_ref (CalendarEvent evt) {
            return "%s\t%s\t%lld".printf (evt.calendar_id, evt.id, evt.start_time.to_unix ());
        }

        public override async string[] get_initial_results (string[] terms, Cancellable? cancellable) throws Error {
            string query = string.joinv (" ", terms).strip ();
            if (query.char_count () < 2) return {};
            var mgr = CalendarManager.get_default ();
            CalendarApp.register_calendars (mgr);
            var now = new DateTime.now_local ();
            var today = new DateTime.local (now.get_year (), now.get_month (), now.get_day_of_month (), 0, 0, 0);
            var matches = yield mgr.search (query, today.add_days (-90), today.add_days (366));
            var upcoming = new ArrayList<CalendarEvent?> ();
            var past = new ArrayList<CalendarEvent?> ();
            foreach (var evt in matches) {
                if (evt.calendar_id == TASKS_CALENDAR) continue;
                if (evt.end_time.compare (now) >= 0) upcoming.add (evt);
                else past.insert (0, evt);
            }
            upcoming.add_all (past);
            found.clear ();
            string[] ids = {};
            foreach (var evt in upcoming) {
                if (ids.length >= MAX_RESULTS) break;
                string id = event_ref (evt);
                if (found.has_key (id)) continue;
                found[id] = evt;
                ids += id;
            }
            return ids;
        }

        public override async Singularity.SearchResultMeta[] get_result_metas (string[] ids, Cancellable? cancellable) throws Error {
            Singularity.SearchResultMeta[] metas = {};
            var now = new DateTime.now_local ();
            var mgr = CalendarManager.get_default ();
            int rank = 0;
            foreach (string id in ids) {
                if (!found.has_key (id)) continue;
                var evt = found[id];
                var meta = new Singularity.SearchResultMeta (id, evt.title != "" ? evt.title : _("Untitled Event"));
                string when = describe_when (evt, now);
                meta.description = evt.location != "" ? "%s, %s".printf (when, evt.location) : when;
                string color = evt.color;
                if (color == "") {
                    var provider = mgr.get_provider (evt.calendar_id);
                    if (provider != null) color = provider.color;
                }
                if (color != "") meta.preview_color = color;
                meta.icon = new ThemedIcon ("dev.sinty.calendar");
                meta.score = 100 - rank;
                rank++;
                metas += meta;
            }
            return metas;
        }

        public static string describe_when (CalendarEvent evt, DateTime now) {
            var start = evt.start_time.to_local ();
            string day;
            int diff = day_number (start) - day_number (now);
            if (diff == 0) day = _("Today");
            else if (diff == 1) day = _("Tomorrow");
            else if (diff == -1) day = _("Yesterday");
            else if (start.get_year () == now.get_year ()) day = start.format (_("%a %-d %B"));
            else day = start.format (_("%a %-d %B %Y"));
            if (evt.all_day) return _("%s, all day").printf (day);
            return "%s, %s".printf (day, start.format ("%H:%M"));
        }

        private static int day_number (DateTime d) {
            var local = d.to_local ();
            var date = Date ();
            date.set_dmy ((DateDay) local.get_day_of_month (), local.get_month (), (DateYear) local.get_year ());
            return (int) date.get_julian ();
        }

        public override async Singularity.SearchActivationReply? activate_result (string id, string[] terms, uint32 timestamp) throws Error {
            app.activate_action ("open-event", new Variant.string (id));
            return null;
        }

        public override void launch_search (string[] terms, uint32 timestamp) {
            app.activate_action ("find", new Variant.string (string.joinv (" ", terms)));
        }
    }
}
