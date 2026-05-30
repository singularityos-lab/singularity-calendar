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

        private CalendarManager   mgr;

        // Views
        private CalendarMonthView month_view;
        private CalendarWeekView  week_view;
        private CalendarDayView   day_view;

        // Navigation state
        private DateTime          current_date;
        private CalendarNavPicker nav_picker;

        // Toolbar widgets
        private Label             period_lbl;
        private SegmentedControl  _view_switcher;

        public CalendarWindow (Gtk.Application app) {
            Object (application: app);

            set_default_size (1100, 720);

            current_date = new DateTime.now_local ();
            _update_window_title ();

            // ── Manager ──────────────────────────────────────────────────────
            mgr = CalendarManager.get_default ();
            _load_calendars ();

            // ── Views ────────────────────────────────────────────────────────
            month_view = new CalendarMonthView (mgr);
            week_view  = new CalendarWeekView  (mgr);
            day_view   = new CalendarDayView   (mgr);

            month_view.day_selected.connect    ((d) => { _switch_to_day (d); });
            month_view.event_activated.connect ((e) => { _show_event_popup (e); });
            week_view.event_activated.connect  ((e) => { _show_event_popup (e); });
            day_view.event_activated.connect   ((e) => { _show_event_popup (e); });

            view_stack.transition_type = StackTransitionType.SLIDE_LEFT_RIGHT;
            view_stack.add_titled (month_view, "month", "Month");
            view_stack.add_titled (week_view,  "week",  "Week");
            view_stack.add_titled (day_view,   "day",   "Day");
            view_stack.visible_child_name = "month";
            set_content (view_stack);

            // ── Toolbar ──────────────────────────────────────────────────────
            period_lbl = new Label ("");
            period_lbl.add_css_class ("title");

            _view_switcher = new SegmentedControl (view_stack);
            _view_switcher.hexpand = false;

            toolbar.pack_start (_view_switcher);
            toolbar.set_title_widget (period_lbl);
            toolbar.is_static = false;

            // ── Sidebar ──────────────────────────────────────────────────────
            nav_picker = new CalendarNavPicker ();
            nav_picker.margin_top    = 8;
            nav_picker.margin_bottom = 4;
            nav_picker.set_date (current_date);
            nav_picker.date_selected.connect ((d) => {
                current_date = d;
                _refresh_all_views ();
                _update_period_label ();
                _update_window_title ();
            });
            nav_picker.today_clicked.connect (_go_today);
            nav_host.append (nav_picker);

            var cal_group = new PreferencesGroup ("Calendars", null);
            _populate_calendar_list (cal_group);
            scroll_sidebar.set_child (cal_group);
            scroll_sidebar.vexpand = true;
            scroll_sidebar.margin_top = 4;
            scroll_sidebar.hscrollbar_policy = PolicyType.NEVER;

            set_sidebar (sidebar_box);
            set_sidebar_visible (true);
            set_sidebar_width (220);

            // ── Wire signals ─────────────────────────────────────────────────
            mgr.events_changed.connect (() => {
                Idle.add (() => { _refresh_current_view (); return false; });
            });

            view_stack.notify["visible-child"].connect (() => {
                _update_period_label ();
                _refresh_current_view ();
            });

            // ── Initial load ─────────────────────────────────────────────────
            _update_period_label ();
            _refresh_all_views ();
        }

        // ── Navigation helpers ────────────────────────────────────────────────

        private void _go_prev () {
            switch (view_stack.visible_child_name) {
                case "month": current_date = current_date.add_months (-1); break;
                case "week":  current_date = current_date.add_weeks  (-1); break;
                case "day":   current_date = current_date.add_days   (-1); break;
            }
            nav_picker.set_date (current_date);
            _update_period_label ();
            _update_window_title ();
            _refresh_current_view ();
        }

        private void _go_next () {
            switch (view_stack.visible_child_name) {
                case "month": current_date = current_date.add_months (1); break;
                case "week":  current_date = current_date.add_weeks  (1); break;
                case "day":   current_date = current_date.add_days   (1); break;
            }
            nav_picker.set_date (current_date);
            _update_period_label ();
            _update_window_title ();
            _refresh_current_view ();
        }

        private void _go_today () {
            current_date = new DateTime.now_local ();
            nav_picker.set_date (current_date);
            _update_period_label ();
            _update_window_title ();
            _refresh_current_view ();
        }

        private void _update_window_title () {
            set_title (current_date.format ("%a, %b %e %Y"));
        }

        private void _switch_to_day (DateTime d) {
            current_date = d;
            nav_picker.set_date (d);
            view_stack.visible_child_name = "day";
        }

        // ── Refresh helpers ───────────────────────────────────────────────────

        private void _refresh_all_views () {
            month_view.set_date (current_date);
            week_view.set_date  (current_date);
            day_view.set_date   (current_date);
        }

        private void _refresh_current_view () {
            switch (view_stack.visible_child_name) {
                case "month": month_view.set_date (current_date); break;
                case "week":  week_view.set_date  (current_date); break;
                case "day":   day_view.set_date   (current_date); break;
            }
        }

        private void _update_period_label () {
            switch (view_stack.visible_child_name) {
                case "month":
                    period_lbl.label = current_date.format ("%B %Y");
                    break;
                case "week": {
                    int dow = current_date.get_day_of_week () % 7;
                    var ws  = current_date.add_days (-dow);
                    var we  = ws.add_days (6);
                    if (ws.get_month () == we.get_month ())
                        period_lbl.label = "%s %d–%d, %d".printf (
                            ws.format ("%B"), ws.get_day_of_month (), we.get_day_of_month (), ws.get_year ());
                    else
                        period_lbl.label = "%s %d – %s %d".printf (
                            ws.format ("%b"), ws.get_day_of_month (), we.format ("%b"), we.get_day_of_month ());
                    break;
                }
                case "day":
                    period_lbl.label = current_date.format ("%A, %B %e %Y");
                    break;
                default:
                    period_lbl.label = current_date.format ("%B %Y");
                    break;
            }
        }

        // ── Calendar list ─────────────────────────────────────────────────────

        private void _populate_calendar_list (PreferencesGroup group) {
            foreach (var p in mgr.get_providers ()) {
                var row = new SwitchRow (p.name, null, p.is_visible);
                var dot = new Box (Orientation.HORIZONTAL, 0);
                try {
                    var css = new CssProvider ();
                    css.load_from_string (
                        ".cal-provider-dot { background-color: %s; border-radius: 4px; min-width: 10px; min-height: 10px; margin-right: 4px; }".printf (p.color));
                    dot.add_css_class ("cal-provider-dot");
                    dot.get_style_context ().add_provider (css, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);
                } catch {}
                dot.valign = Align.CENTER;
                row.add_prefix (dot);

                var cap = p;
                row.switch_btn.notify["active"].connect (() => {
                    cap.is_visible = row.switch_btn.active;
                });
                group.add_row (row);
            }
        }

        // ── Event popup ───────────────────────────────────────────────────────

        private void _show_event_popup (CalendarEvent evt) {
            var dlg = new AppDialog (this.application);
            dlg.set_title (evt.title);
            dlg.set_default_size (320, -1);

            var vbox = new Box (Orientation.VERTICAL, 8);
            vbox.margin_top    = 12;
            vbox.margin_bottom = 12;
            vbox.margin_start  = 16;
            vbox.margin_end    = 16;

            if (!evt.all_day) {
                var time_lbl = new Label (evt.start_time.format ("%H:%M") + " – " + evt.end_time.format ("%H:%M"));
                time_lbl.halign = Align.START;
                time_lbl.add_css_class ("dim-label");
                vbox.append (time_lbl);
            }

            if (evt.description != null && evt.description.length > 0) {
                var desc = new Label (evt.description);
                desc.halign = Align.START;
                desc.wrap   = true;
                desc.set_max_width_chars (40);
                vbox.append (desc);
            }

            var close = new Button.with_label ("Close");
            close.add_css_class ("suggested-action");
            close.halign = Align.END;
            close.clicked.connect (() => dlg.close ());
            vbox.append (close);

            dlg.content_box.append (vbox);
            dlg.present ();
        }

        private void _load_calendars () {
            string data_dir = Environment.get_user_data_dir ();
            string calendar_dir = GLib.Path.build_filename (data_dir, "singularity", "calendar");
            try {
                var dir = GLib.File.new_for_path (calendar_dir);
                if (!dir.query_exists ())
                    DirUtils.create_with_parents (calendar_dir, 0755);

                if (mgr.get_provider ("local-provider") == null)
                    mgr.register_provider (new Singularity.Calendar.LocalProvider ());

                var enumerator = dir.enumerate_children (GLib.FileAttribute.STANDARD_NAME, 0);
                GLib.FileInfo info;
                while ((info = enumerator.next_file ()) != null) {
                    string filename = info.get_name ();
                    if (filename.has_suffix (".json") && filename != "local.json") {
                        string name  = filename.replace (".json", "");
                        string id    = "local-" + name;
                        if (mgr.get_provider (id) != null) continue;
                        string color = Singularity.Calendar.CalendarManager.generate_color (name);
                        mgr.register_provider (new Singularity.Calendar.LocalProvider (name, id, filename, color));
                    }
                }
            } catch (Error e) {
                warning ("CalendarApp: failed to load calendars: %s", e.message);
            }
        }
    }
}
