using Gtk;
using GLib;
using Gee;
using Singularity;
using Singularity.Calendar;
using Singularity.Widgets;

namespace Singularity.Apps.Calendar {

    [GtkTemplate (ui = "/dev/sinty/calendar/ui/main.ui")]
    public class CalendarWindow : Singularity.Widgets.Window {

        [GtkChild] unowned Stack          view_stack;
        [GtkChild] unowned Box            sidebar_box;
        [GtkChild] unowned Box            nav_host;
        [GtkChild] unowned ScrolledWindow scroll_sidebar;

        private const string[] PALETTE = {
            "#3584e4", "#2ec27e", "#e5a50a", "#e66100", "#c01c28", "#9141ac", "#986a44", "#1c71d8", "#26a269", "#63452c"
        };

        private CalendarApp       app;
        private CalendarManager   mgr;
        private EventStore        store;
        private CalendarMonthView month_view;
        private CalendarWeekView  week_view;
        private CalendarDayView   day_view;
        private AgendaView        agenda_view;
        private DateTime          current_date;
        private CalendarNavPicker nav_picker;
        private Label             period_lbl;
        private PreferencesGroup  cal_group;
        private Box               accounts_box;
        private HashSet<Object>   watched = new HashSet<Object> ();
        private uint              list_source = 0;
        private SearchBubble      search;
        private string            view_before_search = "month";
        private uint              refresh_source = 0;

        public CalendarWindow (CalendarApp app) {
            Object (application: app);
            this.app = app;
            set_default_size (1180, 760);

            current_date = new DateTime.now_local ();
            mgr = CalendarManager.get_default ();
            store = new EventStore (mgr);
            CalendarApp.register_calendars (mgr);
            mgr.providers_changed.connect (() => {
                if (cal_group != null) populate_calendar_list ();
            });

            month_view  = new CalendarMonthView (mgr);
            week_view   = new CalendarWeekView (mgr);
            day_view    = new CalendarDayView (mgr);
            agenda_view = new AgendaView (mgr);

            month_view.event_activated.connect (show_details);
            week_view.event_activated.connect (show_details);
            day_view.event_activated.connect (show_details);
            agenda_view.event_activated.connect (show_details);
            agenda_view.clear_search_requested.connect (() => search.text = "");
            month_view.day_selected.connect (open_day);
            week_view.day_selected.connect (open_day);
            day_view.day_selected.connect (open_day);
            month_view.create_requested.connect (create_at);
            week_view.create_requested.connect (create_at);
            day_view.create_requested.connect (create_at);
            week_view.event_moved.connect ((evt, start) => store.move (evt, start));
            day_view.event_moved.connect ((evt, start) => store.move (evt, start));
            week_view.event_copied.connect ((evt, start) => copy_event_to (evt, start));
            day_view.event_copied.connect ((evt, start) => copy_event_to (evt, start));

            view_stack.transition_type = StackTransitionType.CROSSFADE;
            view_stack.add_titled (month_view, "month", _("Month"));
            view_stack.add_titled (week_view, "week", _("Week"));
            view_stack.add_titled (day_view, "day", _("Day"));
            view_stack.add_titled (agenda_view, "list", _("List"));

            add_bubble_icon ("go-previous-symbolic", _("Previous"), () => go_previous ());
            add_bubble_icon ("x-office-calendar-symbolic", _("Today"), () => go_today ());
            add_bubble_icon ("go-next-symbolic", _("Next"), () => go_next ());
            period_lbl = add_bubble_label ("");
            add_bubble_widget (new BubbleSwitcher (view_stack));
            search = add_bubble_search (_("Search Events"), (text) => on_search (text));
            add_bubble_icon ("list-add-symbolic", _("New Event"), () => new_event ());

            set_content (view_stack);

            nav_picker = new CalendarNavPicker ();
            nav_picker.margin_bottom = 4;
            Singularity.Widgets.apply_titlebar_inset (sidebar_box);
            view_stack.add_css_class ("cal-views");
            nav_picker.set_date (current_date);
            nav_picker.date_selected.connect ((d) => {
                current_date = d;
                refresh_current ();
            });
            nav_picker.month_changed.connect (() => update_busy_days.begin ());
            nav_picker.today_clicked.connect (go_today);
            nav_host.append (nav_picker);

            var side = new Box (Orientation.VERTICAL, 8);
            cal_group = new PreferencesGroup (_("Calendars"), null);
            side.append (cal_group);
            accounts_box = new Box (Orientation.VERTICAL, 8);
            side.append (accounts_box);
            Singularity.Accounts.Manager.get_default ().account_changed.connect (() => queue_calendar_list ());
            var side_actions = new Box (Orientation.HORIZONTAL, 6);
            side_actions.homogeneous = true;
            side_actions.margin_start = 4;
            side_actions.margin_end = 4;
            var new_cal = new Button.with_label (_("New Calendar"));
            new_cal.clicked.connect (() => {
                var menu = new ContextMenu (new_cal);
                menu.add_item (_("Empty Calendar"), "list-add-symbolic", () => new_calendar ());
                menu.add_item (_("Subscribe to a Link"), "web-browser-symbolic", () => subscribe_dialog ());
                menu.closed.connect (() => Idle.add (() => { menu.unparent (); return false; }));
                menu.popup ();
            });
            var import_btn = new Button.with_label (_("Import"));
            import_btn.clicked.connect (() => choose_import ());
            side_actions.append (new_cal);
            side_actions.append (import_btn);
            side.append (side_actions);
            scroll_sidebar.set_child (side);
            scroll_sidebar.vexpand = true;
            scroll_sidebar.margin_top = 4;
            scroll_sidebar.hscrollbar_policy = PolicyType.NEVER;
            populate_calendar_list ();

            set_sidebar (sidebar_box);
            set_sidebar_visible (true);
            set_sidebar_width (240);

            mgr.events_changed.connect (queue_refresh);

            app.settings.bind ("show-weekends", month_view, "show-weekends", SettingsBindFlags.GET);
            app.settings.bind ("show-weekends", week_view, "show-weekends", SettingsBindFlags.GET);

            view_stack.notify["visible-child-name"].connect (() => {
                refresh_current ();
            });

            var keys = new EventControllerKey ();
            keys.key_pressed.connect ((keyval, code, state) => {
                if (keyval == Gdk.Key.Escape && agenda_view.searching) {
                    search.text = "";
                    return true;
                }
                bool ctrl = (state & Gdk.ModifierType.CONTROL_MASK) != 0;
                if (ctrl && (keyval == Gdk.Key.v || keyval == Gdk.Key.V) && !(get_focus () is Editable)) {
                    paste_event.begin ();
                    return true;
                }
                if (ctrl && (keyval == Gdk.Key.c || keyval == Gdk.Key.C) && focused_event != null && !(get_focus () is Editable)) {
                    copy_event (focused_event);
                    return true;
                }
                return false;
            });
            ((Widget) this).add_controller (keys);

            var window_actions = new ActionEntry[] {
                { "close", () => close () },
                { "toggle-sidebar", () => set_sidebar_visible (!get_sidebar_visible ()) },
                { "copy-event", () => { if (focused_event != null) copy_event (focused_event); } },
                { "paste-event", () => paste_event.begin () }
            };
            add_action_entries (window_actions, this);
            ((SimpleAction) lookup_action ("copy-event")).set_enabled (false);

            string view = app.settings.get_string ("default-view");
            view_stack.visible_child_name = view_stack.get_child_by_name (view) != null ? view : "month";
            refresh_current ();
        }

        private void queue_refresh () {
            if (refresh_source != 0) return;
            refresh_source = Idle.add (() => {
                refresh_source = 0;
                refresh_current ();
                populate_calendar_list ();
                return false;
            });
        }

        public void show_view (string name) {
            if (view_stack.get_child_by_name (name) != null) view_stack.visible_child_name = name;
        }

        public void go_previous () { step (-1); }
        public void go_next () { step (1); }

        private void step (int direction) {
            switch (view_stack.visible_child_name) {
                case "week": current_date = current_date.add_weeks (direction); break;
                case "day":  current_date = current_date.add_days (direction); break;
                case "list": current_date = current_date.add_months (direction); break;
                default:     current_date = current_date.add_months (direction); break;
            }
            refresh_current ();
        }

        public void go_today () {
            current_date = new DateTime.now_local ();
            refresh_current ();
            if (view_stack.visible_child_name == "week") week_view.scroll_to_working_hours ();
            if (view_stack.visible_child_name == "day") day_view.scroll_to_working_hours ();
        }

        public void start_search () {
            search.grab_focus_entry ();
        }

        private void on_search (string text) {
            if (text.strip () != "" && !agenda_view.searching && view_stack.visible_child_name != "list") {
                view_before_search = view_stack.visible_child_name;
            }
            agenda_view.set_query (text);
            if (text.strip () != "") {
                view_stack.visible_child_name = "list";
            } else if (view_before_search != "list") {
                view_stack.visible_child_name = view_before_search;
            }
        }

        private void open_day (DateTime date) {
            current_date = date;
            view_stack.visible_child_name = "day";
            refresh_current ();
        }

        private void refresh_current () {
            nav_picker.set_date (current_date);
            switch (view_stack.visible_child_name) {
                case "week": week_view.set_date (current_date); break;
                case "day":  day_view.set_date (current_date); break;
                case "list": if (!agenda_view.searching) agenda_view.set_date (current_date); else agenda_view.refresh.begin (); break;
                default:     month_view.set_date (current_date); break;
            }
            update_period_label ();
            set_title (current_date.format (_("%B %Y")));
            update_busy_days.begin ();
        }

        private async void update_busy_days () {
            var month = nav_picker.displayed_month;
            var events = yield mgr.get_events (month, month.add_months (1));
            var days = new Gee.HashSet<string> ();
            foreach (var evt in events) {
                var day = CalendarLayout.day_start (evt.start_time);
                var last = evt.all_day ? evt.end_time.add_days (-1) : evt.end_time.add_seconds (-1);
                for (int i = 0; i < 62 && day.compare (last) <= 0; i++) {
                    days.add (day.format ("%Y-%m-%d"));
                    day = day.add_days (1);
                }
                days.add (evt.start_time.format ("%Y-%m-%d"));
            }
            nav_picker.set_busy_days (days);
        }

        private void update_period_label () {
            switch (view_stack.visible_child_name) {
                case "week": {
                    var ws = CalendarLayout.week_start (current_date);
                    var we = ws.add_days (6);
                    if (ws.get_month () == we.get_month ())
                        period_lbl.label = "%d - %d %s".printf (ws.get_day_of_month (), we.get_day_of_month (), ws.format ("%b %Y"));
                    else
                        period_lbl.label = "%s - %s".printf (ws.format ("%-d %b").strip (), we.format ("%-d %b %Y").strip ());
                    break;
                }
                case "day":
                    period_lbl.label = current_date.format ("%a %-d %b %Y");
                    break;
                case "list":
                    period_lbl.label = agenda_view.searching ? _("Search Results") : _("From %s").printf (current_date.format ("%-d %B").strip ());
                    break;
                default:
                    period_lbl.label = current_date.format (_("%B %Y"));
                    break;
            }
        }

        private string default_calendar_id () {
            string id = app.settings.get_string ("default-calendar");
            if (store.writable (id) != null) return id;
            var list = EventStore.editable_providers (mgr);
            return list.size > 0 ? list[0].id : "local-provider";
        }

        private void apply_defaults (ref CalendarEvent evt) {
            evt.calendar_id = default_calendar_id ();
            int alarm = app.settings.get_int ("default-alarm");
            if (alarm >= 0) evt.alarms = { alarm };
        }

        public void new_event () {
            var now = new DateTime.now_local ();
            var base_day = view_stack.visible_child_name == "month" || view_stack.visible_child_name == "list" ? now : current_date;
            int hour = now.get_hour () + 1;
            var start = new DateTime.local (base_day.get_year (), base_day.get_month (), base_day.get_day_of_month (), hour.clamp (0, 23), 0, 0);
            create_at (start, start.add_minutes (app.settings.get_int ("default-duration")), false);
        }

        public void new_event_at (DateTime when, bool timed, string title) {
            show_day (when);
            DateTime start, end;
            if (timed) {
                start = when;
                end = when.add_minutes (app.settings.get_int ("default-duration"));
            } else {
                start = new DateTime.local (when.get_year (), when.get_month (), when.get_day_of_month (), 0, 0, 0);
                end = start.add_days (1);
            }
            var evt = EventStore.blank (start, end, !timed);
            evt.title = title;
            apply_defaults (ref evt);
            open_editor (null, evt);
        }

        private void create_at (DateTime start, DateTime end, bool all_day) {
            var evt = EventStore.blank (start, end, all_day);
            apply_defaults (ref evt);
            open_editor (null, evt);
        }

        private void open_editor (CalendarEvent? original, CalendarEvent draft) {
            var editor = new EventEditor (app, original, draft);
            editor.transient_for = this;
            editor.saved.connect (on_editor_saved);
            editor.delete_requested.connect (delete_event);
            editor.present ();
        }

        private void on_editor_saved (CalendarEvent? original, CalendarEvent edited) {
            if (original != null && original.occurrence_start != null && original.is_recurring ()) {
                ask_scope (_("Save Recurring Event"), _("Apply the change to this event only, or to the whole series?"), (scope) => {
                    store.save (original, edited, scope);
                    maybe_invite (original, edited);
                });
                return;
            }
            store.save (original, edited, EditScope.ALL);
            maybe_invite (original, edited);
        }

        private bool organized_by_me (CalendarEvent evt) {
            string owner = app.settings.get_string ("owner-email").down ();
            return evt.organizer == null || evt.organizer == "" || evt.organizer.down () == owner;
        }

        private void maybe_invite (CalendarEvent? original, CalendarEvent edited) {
            if (edited.attendees == null || edited.attendees.size == 0 || !organized_by_me (edited)) return;
            bool changed = original == null
                || original.start_time.compare (edited.start_time) != 0
                || original.end_time.compare (edited.end_time) != 0
                || original.title != edited.title
                || original.location != edited.location
                || original.recurrence != edited.recurrence
                || original.attendees == null || original.attendees.size != edited.attendees.size;
            if (!changed) return;
            var dlg = new ConfirmDialog (app, original == null ? _("Send Invitations?") : _("Send Updates?"), "mail-send-symbolic",
                ngettext ("Email the event to %d person so they can add it to their calendar and reply.",
                          "Email the event to %d people so they can add it to their calendar and reply.",
                          edited.attendees.size).printf (edited.attendees.size),
                _("Send"), ConfirmDialog.ActionStyle.SUGGESTED);
            dlg.transient_for = this;
            dlg.response.connect ((r) => {
                if (r == ConfirmDialog.Response.PRIMARY) Invitations.send_invites (edited);
            });
            dlg.present ();
        }

        public delegate void ScopeCallback (EditScope scope);

        private void ask_scope (string title, string text, owned ScopeCallback callback) {
            var dlg = new ConfirmDialog (app, title, "media-playlist-repeat-symbolic", text, _("All Events"), ConfirmDialog.ActionStyle.SUGGESTED);
            dlg.transient_for = this;
            dlg.set_secondary (_("This Event"));
            var following = new Button.with_label (_("This and Following Events"));
            following.add_css_class ("flat");
            following.halign = Align.CENTER;
            following.clicked.connect (() => {
                dlg.close_dialog ();
                callback (EditScope.FOLLOWING);
            });
            dlg.custom_area.append (following);
            dlg.response.connect ((r) => {
                if (r == ConfirmDialog.Response.PRIMARY) callback (EditScope.ALL);
                else if (r == ConfirmDialog.Response.SECONDARY) callback (EditScope.THIS);
            });
            dlg.present ();
        }

        private void delete_event (CalendarEvent evt) {
            if (evt.occurrence_start != null && evt.is_recurring ()) {
                ask_scope (_("Delete Recurring Event"), _("Delete only this event, or more of the series?"), (scope) => {
                    store.remove (evt, scope);
                });
                return;
            }
            var dlg = new ConfirmDialog (app, _("Delete Event?"), "user-trash-symbolic",
                _("\"%s\" will be removed from your calendar.").printf (evt.title), _("Delete"), ConfirmDialog.ActionStyle.DESTRUCTIVE);
            dlg.transient_for = this;
            bool notify_people = evt.attendees != null && evt.attendees.size > 0 && organized_by_me (evt);
            if (notify_people) dlg.set_secondary (_("Delete and Notify"), ConfirmDialog.ActionStyle.DESTRUCTIVE);
            dlg.response.connect ((r) => {
                if (r == ConfirmDialog.Response.CANCEL) return;
                if (r == ConfirmDialog.Response.SECONDARY) Invitations.send_invites (evt, true);
                store.remove (evt, EditScope.ALL);
            });
            dlg.present ();
        }

        private CalendarEvent? copied_event = null;
        private CalendarEvent? focused_event = null;

        private void copy_event (CalendarEvent evt) {
            CalendarEvent copy = evt;
            copy.attendees = EventStore.copy_attendees (evt.attendees);
            copied_event = copy;
            var list = new Gee.ArrayList<CalendarEvent?> ();
            list.add (copy);
            get_clipboard ().set_text (Ics.serialize (list));
            toast (_("Event copied. Pick a day and press Ctrl+V to paste it."));
        }

        private void copy_event_to (CalendarEvent evt, DateTime start) {
            var copy = store.copy_to (evt, start);
            if (copy != null) toast (_("Copied \"%s\"").printf (copy.title));
        }

        private async void paste_event () {
            CalendarEvent? source = copied_event;
            try {
                string? text = yield get_clipboard ().read_text_async (null);
                if (text != null && text.contains ("BEGIN:VEVENT")) {
                    var doc = Ics.parse (text);
                    if (doc.events.size > 0 && (source == null || doc.events[0].id != source.id)) source = doc.events[0];
                }
            } catch (Error e) {
            }
            if (source == null) {
                toast (_("Nothing to paste. Copy an event first."));
                return;
            }
            var day = new DateTime.local (current_date.get_year (), current_date.get_month (), current_date.get_day_of_month (), 0, 0, 0);
            var local_start = source.start_time.to_local ();
            var start = source.all_day ? day : day.add_hours (local_start.get_hour ()).add_minutes (local_start.get_minute ());
            string target = store.writable (source.calendar_id) != null ? source.calendar_id : default_calendar_id ();
            var copy = store.copy_to (source, start, target);
            if (copy != null) toast (_("Pasted \"%s\" on %s").printf (copy.title, start.format ("%-d %B")));
        }

        private void toast (string text) {
            var bar = period_lbl;
            if (bar == null) return;
            if (toast_source != 0) Source.remove (toast_source);
            bar.label = text;
            toast_source = Timeout.add_seconds (3, () => {
                toast_source = 0;
                update_period_label ();
                return false;
            });
        }

        private uint toast_source = 0;

        private void show_details (CalendarEvent evt, Widget source) {
            open_details (evt, source, null);
        }

        public void show_day (DateTime date) {
            if (search.text != "") search_for ("");
            open_day (date);
        }

        public void search_for (string text) {
            search.text = text;
            on_search (text);
        }

        public void reveal_event (string calendar_id, string event_id, int64 start_unix) {
            var start = new DateTime.from_unix_local (start_unix);
            if (search.text != "") search_for ("");
            current_date = start;
            view_stack.visible_child_name = "day";
            refresh_current ();
            day_view.scroll_to_time (start);
            find_and_show.begin (calendar_id, event_id, start_unix);
        }

        private async void find_and_show (string calendar_id, string event_id, int64 start_unix) {
            var start = new DateTime.from_unix_local (start_unix);
            var day = new DateTime.local (start.get_year (), start.get_month (), start.get_day_of_month (), 0, 0, 0);
            var events = yield mgr.get_events (day.add_days (-1), day.add_days (2));
            foreach (var evt in events) {
                if (evt.id != event_id || evt.calendar_id != calendar_id || evt.start_time.to_unix () != start_unix) continue;
                Timeout.add (120, () => {
                    int w = view_stack.get_width ();
                    Gdk.Rectangle rect = { w / 2, 60, 1, 1 };
                    open_details (evt, view_stack, rect);
                    return Source.REMOVE;
                });
                return;
            }
            toast (_("This event no longer exists"));
        }

        private void open_details (CalendarEvent evt, Widget source, Gdk.Rectangle? rect) {
            string? task = null;
            if (evt.calendar_id == "local-dev.sinty.tasks" && evt.id.has_prefix ("task-") && Capabilities.available (Contracts.TASKS)) task = evt.id.substring (5);
            if (task != null) {
                var menu = new ContextMenu (source);
                if (rect != null) menu.set_pointing_to (rect);
                menu.add_item (_("Mark Done"), "object-select-symbolic", () => {
                    Capabilities.call_and_forget (Contracts.TASKS, "SetCompleted", new Variant ("(sb)", task, true));
                });
                menu.add_item (_("Open in Tasks"), "document-open-symbolic", () => {
                    Capabilities.call_and_forget (Contracts.TASKS, "ShowTask", new Variant ("(s)", task));
                });
                menu.closed.connect (() => Idle.add (() => { menu.unparent (); return false; }));
                menu.popup ();
                return;
            }
            focused_event = evt;
            ((SimpleAction) lookup_action ("copy-event")).set_enabled (true);
            var details = new EventDetails (app, evt);
            details.set_parent (source);
            details.closed.connect (() => Idle.add (() => { details.unparent (); return false; }));
            details.edit_requested.connect ((e) => edit_event (e));
            details.delete_requested.connect (delete_event);
            details.duplicate_requested.connect ((e) => {
                CalendarEvent copy = e;
                copy.id = Uuid.string_random ();
                copy.occurrence_start = null;
                copy.recurrence = "";
                copy.exdates = {};
                copy.title = _("%s (copy)").printf (e.title);
                copy.attendees = EventStore.copy_attendees (e.attendees);
                open_editor (null, copy);
            });
            details.respond_requested.connect (respond);
            details.invite_requested.connect ((e) => {
                var provider = store.writable (e.calendar_id);
                var master = provider != null ? provider.find_event (e.id) : null;
                Invitations.send_invites (master ?? e);
            });
            details.export_requested.connect (export_event);
            details.share_requested.connect ((e) => {
                details.popdown ();
                share_event (e);
            });
            details.copy_requested.connect ((e) => {
                details.popdown ();
                copy_event (e);
            });
            if (rect != null) details.pointing_to = rect;
            details.popup ();
        }

        private void edit_event (CalendarEvent evt) {
            CalendarEvent draft = evt;
            draft.attendees = EventStore.copy_attendees (evt.attendees);
            if (evt.occurrence_start != null) {
                var provider = store.writable (evt.calendar_id);
                var master = provider != null ? provider.find_event (evt.id) : null;
                if (master != null) {
                    draft.recurrence = master.recurrence;
                    draft.exdates = master.exdates;
                }
            }
            open_editor (evt, draft);
        }

        private void respond (CalendarEvent evt, string status) {
            string email = app.settings.get_string ("owner-email");
            if (email == "" && evt.attendees != null && evt.attendees.size == 1) email = evt.attendees[0].email;
            if (email == "") return;
            store.set_my_status (evt, email, status);
            Invitations.send_reply (evt, email, status);
        }

        private void export_event (CalendarEvent evt) {
            var provider = store.writable (evt.calendar_id);
            var master = provider != null ? provider.find_event (evt.id) : null;
            CalendarEvent target = master ?? evt;
            var dialog = new FileDialog ();
            dialog.title = _("Export Event");
            dialog.initial_name = "%s.ics".printf (target.title != "" ? target.title : "event");
            dialog.save.begin (this, null, (obj, res) => {
                try {
                    var file = dialog.save.end (res);
                    var list = new Gee.ArrayList<CalendarEvent?> ();
                    target.occurrence_start = null;
                    list.add (target);
                    FileUtils.set_contents (file.get_path (), Ics.serialize (list));
                } catch (Error e) {
                }
            });
        }

        private void share_event (CalendarEvent evt) {
            var provider = store.writable (evt.calendar_id);
            var master = provider != null ? provider.find_event (evt.id) : null;
            CalendarEvent target = master ?? evt;
            target.occurrence_start = null;
            string dir = Path.build_filename (Environment.get_user_cache_dir (), "singularity", "calendar-share");
            DirUtils.create_with_parents (dir, 0700);
            string path = Path.build_filename (dir, "%s.ics".printf ((target.title != "" ? target.title : "event").replace ("/", "-")));
            var list = new Gee.ArrayList<CalendarEvent?> ();
            list.add (target);
            try {
                FileUtils.set_contents (path, Ics.serialize (list));
                Singularity.Share.files (this, { File.new_for_path (path) });
            } catch (Error e) {
                warning ("Calendar: share failed: %s", e.message);
            }
        }

        private void export_calendar (WritableCalendarProvider provider) {
            var dialog = new FileDialog ();
            dialog.title = _("Export Calendar");
            dialog.initial_name = "%s.ics".printf (provider.name);
            dialog.save.begin (this, null, (obj, res) => {
                try {
                    var file = dialog.save.end (res);
                    provider.export_file.begin (file.get_path ());
                } catch (Error e) {
                }
            });
        }

        private string? import_target = null;

        public void choose_import (string? target_id = null) {
            import_target = target_id;
            var dialog = new FileDialog ();
            dialog.title = _("Import Events");
            var filter = new FileFilter ();
            filter.name = _("Calendar Files");
            filter.add_mime_type ("text/calendar");
            filter.add_suffix ("ics");
            var filters = new GLib.ListStore (typeof (FileFilter));
            filters.append (filter);
            dialog.filters = filters;
            dialog.open.begin (this, null, (obj, res) => {
                try {
                    open_ics (dialog.open.end (res));
                } catch (Error e) {
                }
            });
        }

        public void open_ics (File file) {
            uint8[] data;
            try {
                file.load_contents (null, out data, null);
            } catch (Error e) {
                warning ("Cannot read %s: %s", file.get_uri (), e.message);
                return;
            }
            var doc = Ics.parse ((string) data);
            if (doc.events.size == 0) return;
            if (doc.method == "REPLY") {
                apply_reply (doc);
                return;
            }
            if (doc.method == "CANCEL") {
                foreach (var evt in doc.events) {
                    foreach (var provider in EventStore.editable_providers (mgr)) {
                        if (provider.find_event (evt.id) != null) provider.delete_event (evt.id);
                    }
                }
                return;
            }
            ask_import_target (file, doc);
        }

        private void apply_reply (IcsDocument doc) {
            foreach (var reply in doc.events) {
                if (reply.attendees == null) continue;
                foreach (var provider in EventStore.editable_providers (mgr)) {
                    var existing = provider.find_event (reply.id);
                    if (existing == null) continue;
                    CalendarEvent updated = existing;
                    updated.attendees = EventStore.copy_attendees (existing.attendees);
                    foreach (var answer in reply.attendees) {
                        bool found = false;
                        foreach (var a in updated.attendees) {
                            if (a.email.down () == answer.email.down ()) {
                                a.status = answer.status;
                                found = true;
                            }
                        }
                        if (!found) updated.attendees.add (answer.copy ());
                    }
                    provider.update_event (updated);
                }
            }
        }

        private void ask_import_target (File file, IcsDocument doc) {
            var calendars = EventStore.editable_providers (mgr);
            string[] names = {};
            uint selected = 0;
            string def = import_target ?? default_calendar_id ();
            import_target = null;
            for (int i = 0; i < calendars.size; i++) {
                names += EventStore.label_for (calendars[i]);
                if (calendars[i].id == def) selected = i;
            }
            names += _("New Calendar from File");
            bool invite = doc.method == "REQUEST";
            string title = invite ? _("Invitation") : _("Import Events");
            string text = invite
                ? _("Add \"%s\" to your calendar to reply.").printf (doc.events[0].title)
                : ngettext ("%d event will be added.", "%d events will be added.", doc.events.size).printf (doc.events.size);
            var dlg = new ConfirmDialog (app, title, "x-office-calendar-symbolic", text, invite ? _("Add") : _("Import"), ConfirmDialog.ActionStyle.SUGGESTED);
            dlg.transient_for = this;
            var drop = new DropDown.from_strings (names);
            drop.selected = selected;
            drop.halign = Align.CENTER;
            dlg.custom_area.append (drop);
            dlg.response.connect ((r) => {
                if (r != ConfirmDialog.Response.PRIMARY) return;
                WritableCalendarProvider target;
                if (drop.selected >= calendars.size) {
                    string name = file.get_basename () ?? _("Imported");
                    if (name.has_suffix (".ics")) name = name.substring (0, name.length - 4);
                    target = LocalProvider.create (mgr, name, PALETTE[mgr.get_providers ().size % PALETTE.length]);
                } else {
                    target = calendars[(int) drop.selected];
                }
                target.import_file.begin (file.get_path (), (obj, res) => {
                    try {
                        target.import_file.end (res);
                        if (invite) {
                            current_date = doc.events[0].start_time;
                            view_stack.visible_child_name = "day";
                            refresh_current ();
                        }
                    } catch (Error e) {
                        warning ("Import failed: %s", e.message);
                    }
                });
            });
            dlg.present ();
        }

        public void new_calendar () {
            edit_calendar_dialog (null);
        }

        public void subscribe_dialog () {
            var dlg = new ConfirmDialog (app, _("Subscribe to Calendar"), null,
                _("Paste the sharing link of a calendar, such as one from Proton Calendar, Google or Outlook. It stays read-only and updates every 30 minutes."),
                _("Subscribe"), ConfirmDialog.ActionStyle.SUGGESTED);
            dlg.transient_for = this;
            var link = new Entry ();
            link.placeholder_text = "https://";
            link.input_purpose = InputPurpose.URL;
            dlg.custom_area.append (link);
            var name = new Entry ();
            name.placeholder_text = _("Calendar Name (optional)");
            dlg.custom_area.append (name);
            var error = new Label ("");
            error.add_css_class ("error");
            error.wrap = true;
            error.visible = false;
            dlg.custom_area.append (error);
            link.activate.connect (() => dlg.response (ConfirmDialog.Response.PRIMARY));
            name.activate.connect (() => dlg.response (ConfirmDialog.Response.PRIMARY));
            bool busy = false;
            dlg.response.connect ((r) => {
                if (r != ConfirmDialog.Response.PRIMARY || busy) return;
                if (link.text.strip () == "") {
                    error.label = _("Paste the calendar link first.");
                    error.visible = true;
                    return;
                }
                busy = true;
                error.label = _("Checking the link");
                error.visible = true;
                link.sensitive = false;
                name.sensitive = false;
                string color = PALETTE[mgr.get_providers ().size % PALETTE.length];
                WebCalendarProvider.subscribe.begin (mgr, name.text, link.text, color, (obj, res) => {
                    busy = false;
                    try {
                        WebCalendarProvider.subscribe.end (res);
                        populate_calendar_list ();
                        refresh_current ();
                        dlg.close_dialog ();
                    } catch (Error e) {
                        error.label = e.message;
                        link.sensitive = true;
                        name.sensitive = true;
                    }
                });
            });
            dlg.present ();
            link.grab_focus ();
        }

        private void edit_web_calendar_dialog (WebCalendarProvider existing) {
            var dlg = new ConfirmDialog (app, _("Edit Calendar"), null, existing.url, _("Save"), ConfirmDialog.ActionStyle.SUGGESTED);
            dlg.transient_for = this;
            var name = new Entry ();
            name.placeholder_text = _("Calendar Name");
            name.text = existing.name;
            dlg.custom_area.append (name);
            var colors = new Box (Orientation.HORIZONTAL, 6);
            colors.halign = Align.CENTER;
            string chosen = existing.color;
            ToggleButton? group = null;
            foreach (string color in PALETTE) {
                var btn = new ToggleButton ();
                btn.add_css_class ("cal-color-choice");
                var swatch = new Box (Orientation.HORIZONTAL, 0);
                swatch.add_css_class ("cal-color-swatch");
                swatch.set_size_request (18, 18);
                CalendarLayout.tint (swatch, color);
                btn.child = swatch;
                if (group != null) btn.group = group; else group = btn;
                btn.active = color == chosen;
                string value = color;
                btn.toggled.connect (() => { if (btn.active) chosen = value; });
                colors.append (btn);
            }
            dlg.custom_area.append (colors);
            name.activate.connect (() => dlg.response (ConfirmDialog.Response.PRIMARY));
            dlg.response.connect ((r) => {
                if (r != ConfirmDialog.Response.PRIMARY) return;
                existing.set_name (name.text);
                existing.set_color (chosen);
                populate_calendar_list ();
                dlg.close_dialog ();
            });
            dlg.present ();
            name.grab_focus ();
        }

        private void confirm_unsubscribe (WebCalendarProvider provider) {
            var dlg = new ConfirmDialog (app, _("Unsubscribe?"), "user-trash-symbolic",
                _("\"%s\" will be removed from this computer. The calendar itself is not changed.").printf (provider.name),
                _("Unsubscribe"), ConfirmDialog.ActionStyle.DESTRUCTIVE);
            dlg.transient_for = this;
            dlg.response.connect ((r) => {
                if (r != ConfirmDialog.Response.PRIMARY) return;
                provider.unsubscribe (mgr);
                populate_calendar_list ();
            });
            dlg.present ();
        }

        private void edit_calendar_dialog (LocalProvider? existing) {
            var dlg = new ConfirmDialog (app, existing == null ? _("New Calendar") : _("Edit Calendar"), null, null,
                existing == null ? _("Create") : _("Save"), ConfirmDialog.ActionStyle.SUGGESTED);
            dlg.transient_for = this;
            var name = new Entry ();
            name.placeholder_text = _("Calendar Name");
            name.text = existing != null ? existing.name : "";
            dlg.custom_area.append (name);
            var colors = new Box (Orientation.HORIZONTAL, 6);
            colors.halign = Align.CENTER;
            string chosen = existing != null ? existing.color : PALETTE[mgr.get_providers ().size % PALETTE.length];
            ToggleButton? group = null;
            foreach (string color in PALETTE) {
                var btn = new ToggleButton ();
                btn.add_css_class ("cal-color-choice");
                var swatch = new Box (Orientation.HORIZONTAL, 0);
                swatch.add_css_class ("cal-color-swatch");
                swatch.set_size_request (18, 18);
                CalendarLayout.tint (swatch, color);
                btn.child = swatch;
                if (group != null) btn.group = group; else group = btn;
                btn.active = color == chosen;
                string value = color;
                btn.toggled.connect (() => { if (btn.active) chosen = value; });
                colors.append (btn);
            }
            dlg.custom_area.append (colors);
            name.activate.connect (() => dlg.response (ConfirmDialog.Response.PRIMARY));
            dlg.response.connect ((r) => {
                if (r != ConfirmDialog.Response.PRIMARY) return;
                string text = name.text.strip ();
                if (text == "") text = _("Calendar");
                if (existing == null) {
                    LocalProvider.create (mgr, text, chosen);
                } else {
                    existing.set_name (text);
                    existing.set_color (chosen);
                }
                populate_calendar_list ();
                dlg.close_dialog ();
            });
            dlg.present ();
            name.grab_focus ();
        }

        public void sync_now () {
            AccountCalendars.register_all (mgr).refresh.begin ((obj, res) => {
                AccountCalendars.register_all (mgr).refresh.end (res);
                populate_calendar_list ();
            });
        }

        private void open_account_settings () {
            try {
                Singularity.Shell.ShellService shell = Bus.get_proxy_sync (
                    BusType.SESSION, "dev.sinty.desktop", "/dev/sinty/Shell");
                shell.open_settings ("accounts");
            } catch (Error e) {
                warning ("Failed to open settings: %s", e.message);
            }
        }

        private void queue_calendar_list () {
            if (list_source != 0) return;
            list_source = Timeout.add (200, () => {
                list_source = 0;
                populate_calendar_list ();
                return false;
            });
        }

        private void watch (AccountCalendarProvider p) {
            if (watched.contains (p.synced)) return;
            watched.add (p.synced);
            p.synced.notify["offline"].connect (() => queue_calendar_list ());
            p.synced.notify["last-error"].connect (() => queue_calendar_list ());
            p.synced.notify["syncing"].connect (() => queue_calendar_list ());
            var set = AccountCalendars.register_all (mgr).collections.get_set (p.account_id);
            if (set != null && !watched.contains (set)) {
                watched.add (set);
                set.notify["last-error"].connect (() => queue_calendar_list ());
            }
        }

        private string? online_status (AccountCalendarProvider p) {
            var account = Singularity.Accounts.Manager.get_default ().get_account (p.account_id);
            if (account != null && account.attention == "reauth") return _("Sign in again in Settings");
            if (p.synced.last_error != "" && !p.synced.offline) return _("Sync failed: %s").printf (p.synced.last_error);
            var set = AccountCalendars.register_all (mgr).collections.get_set (p.account_id);
            if (p.synced.offline || (set != null && set.last_error != "")) return _("Offline, changes will sync later");
            if (p.synced.syncing && p.synced.last_sync == 0) return _("Syncing…");
            if (p.read_only) return _("Read-only");
            return null;
        }

        private void add_online_row (AccountCalendarProvider p, PreferencesGroup group) {
            watch (p);
            var row = new SwitchRow (p.name, online_status (p), p.is_visible);
            var dot = new Box (Orientation.HORIZONTAL, 0);
            dot.add_css_class ("cal-color-swatch");
            dot.valign = Align.CENTER;
            dot.margin_end = 4;
            CalendarLayout.tint (dot, p.color);
            row.add_prefix (dot);
            row.switch_btn.notify["active"].connect (() => p.is_visible = row.switch_btn.active);
            var menu_btn = new Button.from_icon_name ("view-more-symbolic");
            menu_btn.add_css_class ("flat");
            menu_btn.valign = Align.CENTER;
            menu_btn.tooltip_text = _("Calendar Options");
            menu_btn.clicked.connect (() => {
                var menu = new ContextMenu (menu_btn);
                menu.add_item (_("Sync Now"), "view-refresh-symbolic", () => sync_now ());
                menu.add_item (_("Account Settings"), "emblem-system-symbolic", () => open_account_settings ());
                menu.closed.connect (() => Idle.add (() => { menu.unparent (); return false; }));
                menu.popup ();
            });
            row.add_suffix (menu_btn);
            group.add_row (row);
        }

        private void populate_calendar_list () {
            cal_group.clear ();
            for (var child = accounts_box.get_first_child (); child != null; child = accounts_box.get_first_child ()) {
                accounts_box.remove (child);
            }
            var online_list = new ArrayList<AccountCalendarProvider> ();
            foreach (var p in mgr.get_providers ()) {
                if (p is AccountCalendarProvider) online_list.add ((AccountCalendarProvider) p);
            }
            online_list.sort ((a, b) => {
                int order = a.account_name.collate (b.account_name);
                return order != 0 ? order : strcmp (a.account_id, b.account_id);
            });
            var account_groups = new HashMap<string, PreferencesGroup> ();
            foreach (var online in online_list) {
                var group = account_groups[online.account_id];
                if (group == null) {
                    group = new PreferencesGroup (online.account_name, null);
                    account_groups[online.account_id] = group;
                    accounts_box.append (group);
                }
                add_online_row (online, group);
            }
            string def = default_calendar_id ();
            foreach (var p in mgr.get_providers ()) {
                if (p is AccountCalendarProvider) continue;
                var row = new SwitchRow (p.name, p.id == def ? _("Default") : null, p.is_visible);
                var dot = new Box (Orientation.HORIZONTAL, 0);
                dot.add_css_class ("cal-color-swatch");
                dot.valign = Align.CENTER;
                dot.margin_end = 4;
                CalendarLayout.tint (dot, p.color);
                row.add_prefix (dot);
                var cap = p;
                row.switch_btn.notify["active"].connect (() => {
                    cap.is_visible = row.switch_btn.active;
                    var local = cap as LocalProvider;
                    if (local != null) local.remember_visibility ();
                    var web = cap as WebCalendarProvider;
                    if (web != null) web.remember_visibility ();
                });
                var subscribed = p as WebCalendarProvider;
                if (subscribed != null) {
                    if (subscribed.last_error != "") row.subtitle = _("Could not update");
                    var web_btn = new Button.from_icon_name ("view-more-symbolic");
                    web_btn.add_css_class ("flat");
                    web_btn.valign = Align.CENTER;
                    web_btn.tooltip_text = _("Calendar Options");
                    web_btn.clicked.connect (() => {
                        var menu = new ContextMenu (web_btn);
                        menu.add_item (_("Edit"), "document-edit-symbolic", () => edit_web_calendar_dialog (subscribed));
                        menu.add_item (_("Update Now"), "view-refresh-symbolic", () => subscribed.refresh.begin ((obj, res) => {
                            subscribed.refresh.end (res);
                            populate_calendar_list ();
                        }));
                        menu.add_item (_("Copy Link"), "edit-copy-symbolic", () => get_clipboard ().set_text (subscribed.url));
                        menu.add_item (_("Unsubscribe"), "user-trash-symbolic", () => confirm_unsubscribe (subscribed), "destructive-action");
                        menu.closed.connect (() => Idle.add (() => { menu.unparent (); return false; }));
                        menu.popup ();
                    });
                    row.add_suffix (web_btn);
                }
                var writable = p as WritableCalendarProvider;
                if (writable != null) {
                    var menu_btn = new Button.from_icon_name ("view-more-symbolic");
                    menu_btn.add_css_class ("flat");
                    menu_btn.valign = Align.CENTER;
                    menu_btn.tooltip_text = _("Calendar Options");
                    menu_btn.clicked.connect (() => {
                        var menu = new ContextMenu (menu_btn);
                        var local = cap as LocalProvider;
                        if (local != null) menu.add_item (_("Edit"), "document-edit-symbolic", () => edit_calendar_dialog (local));
                        if (cap.id != def) menu.add_item (_("Use for New Events"), "emblem-default-symbolic", () => {
                            app.settings.set_string ("default-calendar", cap.id);
                            populate_calendar_list ();
                        });
                        menu.add_item (_("Import Into"), "document-open-symbolic", () => choose_import (cap.id));
                        menu.add_item (_("Export"), "document-save-symbolic", () => export_calendar (writable));
                        if (local != null && cap.id != "local-provider") {
                            menu.add_item (_("Delete"), "user-trash-symbolic", () => confirm_delete_calendar (local), "destructive-action");
                        }
                        menu.closed.connect (() => Idle.add (() => { menu.unparent (); return false; }));
                        menu.popup ();
                    });
                    row.add_suffix (menu_btn);
                }
                cal_group.add_row (row);
            }
        }

        private void confirm_delete_calendar (LocalProvider provider) {
            var dlg = new ConfirmDialog (app, _("Delete Calendar?"), "user-trash-symbolic",
                _("\"%s\" and all of its events will be deleted.").printf (provider.name), _("Delete"), ConfirmDialog.ActionStyle.DESTRUCTIVE);
            dlg.transient_for = this;
            dlg.response.connect ((r) => {
                if (r != ConfirmDialog.Response.PRIMARY) return;
                provider.delete ();
                mgr.unregister_provider (provider.id);
                populate_calendar_list ();
            });
            dlg.present ();
        }
    }
}
