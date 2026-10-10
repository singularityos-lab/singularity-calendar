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
}
