namespace Singularity.Apps.Calendar {

    [DBus (name = "dev.sinty.Calendar1")]
    public class CalendarBus : Object {
        private unowned GLib.Application app;

        public CalendarBus (GLib.Application app) {
            this.app = app;
        }

        public void new_event_at (int64 when, bool timed, string title) throws Error {
            app.activate_action ("new-event-at", new Variant ("(xbs)", when, timed, title));
        }

        public void show_day (int64 day) throws Error {
            app.activate_action ("show-day", new Variant.int64 (day));
        }

        public void open_event (string calendar_id, string event_id, int64 start) throws Error {
            app.activate_action ("open-event", new Variant.string (("%s\t%s\t%" + int64.FORMAT).printf (calendar_id, event_id, start)));
        }
    }

    [DBus (name = "dev.sinty.Collab.Event1")]
    public class EventCollabBus : Object {
        private unowned GLib.Application app;

        public EventCollabBus (GLib.Application app) {
            this.app = app;
        }

        public void receive (string title, string payload, string from) throws Error {
            string dir = Path.build_filename (Environment.get_user_cache_dir (), "singularity", "calendar-received");
            DirUtils.create_with_parents (dir, 0700);
            string path = Path.build_filename (dir, "%s.ics".printf (Uuid.string_random ()));
            FileUtils.set_contents (path, payload);
            app.open ({ File.new_for_path (path) }, "");
        }

        public void join (string session, string title, string snapshot, string role, string from) throws Error {
            throw new IOError.NOT_SUPPORTED ("events are not shared in a session");
        }
    }
}
