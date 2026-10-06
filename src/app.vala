using Gtk;
using GLib;
using Gee;
using Singularity;
using Singularity.Calendar;
using Singularity.Widgets;

namespace Singularity.Apps.Calendar {

    public class CalendarApp : Singularity.Application {
        private CalendarWindow win;
        public GLib.Settings settings { get; private set; }
        private CalendarSearch search_provider;
        private bool pending_new_event = false;

        public CalendarApp () {
            Object (application_id: "dev.sinty.calendar", flags: ApplicationFlags.HANDLES_OPEN);
            add_main_option ("new-event", 0, OptionFlags.NONE, OptionArg.NONE, _("Start a new event today"), null);
            search_provider = new CalendarSearch (this);
            search_provider.export (this);
        }

        public static void register_calendars (CalendarManager mgr) {
            LocalProvider.register_all (mgr);
            WebCalendarProvider.register_all (mgr);
            AccountCalendars.register_all (mgr);
        }

        protected override int handle_local_options (VariantDict options) {
            if (!options.contains ("new-event")) return -1;
            try {
                register (null);
            } catch (Error e) {
                warning ("calendar: %s", e.message);
                return 1;
            }
            if (get_is_remote ()) {
                activate_action ("new-event", null);
                return 0;
            }
            pending_new_event = true;
            return -1;
        }

        protected override void startup () {
            base.startup ();
            settings = new GLib.Settings ("dev.sinty.calendar");

            var menu = new GLib.Menu ();
            var file_menu = new GLib.Menu ();
            var file_new = new GLib.Menu ();
            file_new.append (_("New Event"), "app.new-event");
            file_new.append (_("New Calendar…"), "app.new-calendar");
            file_new.append (_("Subscribe to Calendar…"), "app.subscribe");
            file_menu.append_section (null, file_new);
            var file_import = new GLib.Menu ();
            file_import.append (_("Import…"), "app.import");
            file_import.append (_("Sync Now"), "app.sync");
            file_menu.append_section (null, file_import);
            var file_close = new GLib.Menu ();
            file_close.append (_("Close Window"), "win.close");
            file_close.append (_("Quit"), "app.quit");
            file_menu.append_section (null, file_close);
            menu.append_submenu (_("File"), file_menu);
            var edit_menu = new GLib.Menu ();
            var edit_clip = new GLib.Menu ();
            edit_clip.append (_("Copy Event"), "win.copy-event");
            edit_clip.append (_("Paste Event"), "win.paste-event");
            edit_menu.append_section (null, edit_clip);
            var edit_find = new GLib.Menu ();
            edit_find.append (_("Find"), "app.search");
            edit_menu.append_section (null, edit_find);
            var edit_settings = new GLib.Menu ();
            edit_settings.append (_("Settings"), "app.settings");
            edit_menu.append_section (null, edit_settings);
            menu.append_submenu (_("Edit"), edit_menu);
            var view_menu = new GLib.Menu ();
            var view_modes = new GLib.Menu ();
            view_modes.append (_("Month"), "app.view::month");
            view_modes.append (_("Week"), "app.view::week");
            view_modes.append (_("Day"), "app.view::day");
            view_modes.append (_("List"), "app.view::list");
            view_menu.append_section (null, view_modes);
            var view_options = new GLib.Menu ();
            view_options.append (_("Show Weekends"), "app.show-weekends");
            view_options.append (_("Toggle Sidebar"), "win.toggle-sidebar");
            view_menu.append_section (null, view_options);
            menu.append_submenu (_("View"), view_menu);
            var go_menu = new GLib.Menu ();
            go_menu.append (_("Today"), "app.today");
            go_menu.append (_("Previous"), "app.previous");
            go_menu.append (_("Next"), "app.next");
            menu.append_submenu (_("Go"), go_menu);
            set_menubar (menu);

            add_simple ("new-event", () => when_shown ((w) => w.new_event ()));
            add_simple ("new-calendar", () => ensure_window ().new_calendar ());
            add_simple ("subscribe", () => ensure_window ().subscribe_dialog ());
            add_simple ("import", () => ensure_window ().choose_import ());
            add_simple ("sync", () => ensure_window ().sync_now ());
            add_simple ("today", () => ensure_window ().go_today ());
            add_simple ("search", () => ensure_window ().start_search ());
            add_simple ("previous", () => ensure_window ().go_previous ());
            add_simple ("next", () => ensure_window ().go_next ());

            var open_event = new SimpleAction ("open-event", VariantType.STRING);
            open_event.activate.connect ((param) => {
                string[] parts = param.get_string ().split ("\t");
                if (parts.length != 3) return;
                string calendar_id = parts[0];
                string event_id = parts[1];
                int64 start = int64.parse (parts[2]);
                when_shown ((w) => w.reveal_event (calendar_id, event_id, start));
            });
            add_action (open_event);

            var show_day = new SimpleAction ("show-day", VariantType.INT64);
            show_day.activate.connect ((param) => {
                var day = new DateTime.from_unix_local (param.get_int64 ());
                when_shown ((w) => w.show_day (day));
            });
            add_action (show_day);

            var find_action = new SimpleAction ("find", VariantType.STRING);
            find_action.activate.connect ((param) => {
                string text = param.get_string ();
                when_shown ((w) => w.search_for (text));
            });
            add_action (find_action);

            var view_action = new SimpleAction ("view", VariantType.STRING);
            view_action.activate.connect ((param) => ensure_window ().show_view (param.get_string ()));
            add_action (view_action);

            add_simple ("settings", () => {
                try {
                    Singularity.Shell.ShellService shell = Bus.get_proxy_sync (
                        BusType.SESSION, "dev.sinty.desktop", "/dev/sinty/Shell");
                    shell.open_app_settings ("dev.sinty.calendar");
                } catch (Error e) {
                    warning ("Failed to open settings: %s", e.message);
                }
            });
            add_simple ("quit", () => quit ());
            add_action (settings.create_action ("show-weekends"));

            set_accels_for_action ("app.new-event", { "<Control>n" });
            set_accels_for_action ("app.search", { "<Control>f" });
            set_accels_for_action ("app.today", { "<Control>t" });
            set_accels_for_action ("app.previous", { "<Alt>Left", "Page_Up" });
            set_accels_for_action ("app.next", { "<Alt>Right", "Page_Down" });
            set_accels_for_action ("app.view::month", { "<Control>1" });
            set_accels_for_action ("app.view::week", { "<Control>2" });
            set_accels_for_action ("app.view::day", { "<Control>3" });
            set_accels_for_action ("app.view::list", { "<Control>4" });
            set_accels_for_action ("app.quit", { "<Control>q" });
            set_accels_for_action ("app.settings", { "<Control>comma" });
            set_accels_for_action ("win.close", { "<Control>w" });
            set_accels_for_action ("win.toggle-sidebar", { "F9" });
        }

        private void add_simple (string name, owned ActionCallback callback) {
            var action = new SimpleAction (name, null);
            action.activate.connect (() => callback ());
            add_action (action);
        }

        public delegate void ActionCallback ();

        private CalendarWindow ensure_window () {
            if (win == null) {
                setup_styles ();
                win = new CalendarWindow (this);
            }
            return win;
        }

        public override void activate () {
            if (pending_new_event) {
                pending_new_event = false;
                when_shown ((w) => w.new_event ());
                return;
            }
            ensure_window ().present ();
        }

        public delegate void WindowCallback (CalendarWindow window);

        private void when_shown (owned WindowCallback callback) {
            var window = ensure_window ();
            if (window.get_mapped ()) {
                window.present ();
                callback (window);
                return;
            }
            ulong handler = 0;
            handler = window.map.connect (() => {
                window.disconnect (handler);
                Timeout.add (250, () => {
                    callback (window);
                    return Source.REMOVE;
                });
            });
            window.present ();
        }

        public override void open (File[] files, string hint) {
            var window = ensure_window ();
            File[] pending = files;
            if (window.get_mapped ()) {
                window.present ();
                foreach (var file in pending) window.open_ics (file);
                return;
            }
            ulong handler = 0;
            handler = window.map.connect (() => {
                window.disconnect (handler);
                Timeout.add (250, () => {
                    foreach (var file in pending) window.open_ics (file);
                    return Source.REMOVE;
                });
            });
            window.present ();
        }

        private void setup_styles () {
            var provider = new Gtk.CssProvider ();
            provider.load_from_string (CAL_CSS);
            Gtk.StyleContext.add_provider_for_display (
                Gdk.Display.get_default (), provider,
                Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);
        }

        private const string CAL_CSS = """.singularity-app:not(.ssd-mode) .cal-views > * {
    padding-top: 44px;
}


.cal-nav-picker {
    padding: 8px 6px;
}

.cal-nav-month-label {
    font-weight: bold;
    font-size: 13px;
}

.cal-nav-day-btn {
    font-size: 12px;
    min-width: 28px;
    min-height: 26px;
    padding: 0 2px;
    border-radius: 13px;
}

.cal-nav-day-btn.busy {
    font-weight: bold;
}

.cal-nav-day-btn.today {
    background-color: @accent_bg_color;
    color: @accent_fg_color;
    font-weight: bold;
}

.cal-nav-day-btn.selected:not(.today) {
    background-color: alpha(@accent_bg_color, 0.18);
}

.cal-nav-today-btn {
    font-size: 11px;
    padding: 2px 8px;
    border-radius: 10px;
    min-height: 22px;
    margin: 0 4px;
}

.cal-dow-header {
    border-bottom: 1px solid alpha(@window_fg_color, 0.08);
}

.cal-dow-label {
    font-size: 11px;
    font-weight: bold;
    opacity: 0.6;
    padding: 7px 0;
}

.cal-month-grid {
    background-color: transparent;
}

.cal-day-cell {
    border-right: 1px solid alpha(@window_fg_color, 0.07);
    border-bottom: 1px solid alpha(@window_fg_color, 0.07);
    min-height: 90px;
    min-width: 60px;
}

.cal-day-cell.out-of-month {
    opacity: 0.4;
}

.cal-day-cell.today {
    background-color: alpha(@accent_bg_color, 0.06);
}

button.cal-day-num,
button.cal-today-badge {
    font-size: 12px;
    min-height: 22px;
    min-width: 22px;
    padding: 0 5px;
    border-radius: 11px;
}

button.cal-day-num {
    opacity: 0.8;
}

.cal-today-badge {
    background-color: @accent_bg_color;
    color: @accent_fg_color;
    font-weight: bold;
    border-radius: 12px;
    min-width: 24px;
    min-height: 24px;
    padding: 0 4px;
}

button.cal-more-label {
    font-size: 11px;
    opacity: 0.7;
    min-height: 16px;
    padding: 0 6px;
}

button.cal-event-chip {
    font-size: 11px;
    border-radius: 5px;
    padding: 1px 0;
    min-height: 18px;
    background-image: none;
    box-shadow: none;
}

button.cal-event-chip.compact {
    min-height: 17px;
}

button.cal-timed-event {
    border-radius: 6px;
    padding: 2px 4px;
    font-size: 11px;
    background-image: none;
    box-shadow: none;
}

button.cal-timed-event.dragging {
    opacity: 0.75;
}

button.cal-timed-event.copying {
    opacity: 1;
    box-shadow: 0 0 0 2px @accent_bg_color;
}

.cal-event-time {
    font-size: 10px;
    opacity: 0.75;
}

.cal-week-header {
    border-bottom: 1px solid alpha(@window_fg_color, 0.07);
}

button.cal-week-day-btn {
    border-radius: 10px;
    padding: 4px 0;
}

.cal-week-day-num {
    font-size: 18px;
    font-weight: 300;
}

.cal-all-day-row {
    border-bottom: 1px solid alpha(@window_fg_color, 0.1);
    padding: 3px 0;
}

.cal-all-day-cell {
    padding: 0 2px;
}

.cal-time-label {
    font-size: 10px;
    opacity: 0.55;
    padding-right: 8px;
}

.cal-day-column {
    border-left: 1px solid alpha(@window_fg_color, 0.07);
}

.cal-hour-slot {
    border-bottom: 1px solid alpha(@window_fg_color, 0.06);
}

.cal-now-line {
    background-color: @error_color;
    min-height: 2px;
}

.cal-create-ghost {
    background-color: alpha(@accent_bg_color, 0.25);
    border: 1px dashed @accent_bg_color;
    border-radius: 6px;
}

.cal-event-dot,
.cal-color-swatch {
    border-radius: 999px;
    min-width: 10px;
    min-height: 10px;
}

.cal-color-choice {
    min-width: 22px;
    min-height: 22px;
    padding: 0;
    border-radius: 999px;
}

.cal-color-choice:checked {
    box-shadow: 0 0 0 2px @window_bg_color, 0 0 0 4px @accent_bg_color;
}

.cal-details {
    padding: 14px 16px;
}

.cal-details-title {
    font-size: 16px;
    font-weight: 700;
}

.cal-agenda-day {
    font-weight: bold;
    font-size: 13px;
    margin-top: 12px;
}

.cal-agenda-row {
    padding: 6px 10px;
    border-radius: 8px;
}

.cal-agenda-row:hover {
    background-color: alpha(@window_fg_color, 0.05);
}

.cal-attendee-status {
    font-size: 11px;
}

.cal-invite-banner {
    background-color: alpha(@accent_bg_color, 0.12);
    border-radius: 10px;
    padding: 8px 10px;
}

.cal-weekday-toggle {
    min-width: 30px;
    min-height: 30px;
    padding: 0;
    border-radius: 999px;
}
""";
    }
}
