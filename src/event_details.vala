using Gtk;
using GLib;
using Gee;
using Singularity.Calendar;
using Singularity.Widgets;

namespace Singularity.Apps.Calendar {

    public class EventDetails : Popover {
        private CalendarEvent evt;
        private CalendarApp app;

        public signal void edit_requested (CalendarEvent evt);
        public signal void delete_requested (CalendarEvent evt);
        public signal void duplicate_requested (CalendarEvent evt);
        public signal void copy_requested (CalendarEvent evt);
        public signal void respond_requested (CalendarEvent evt, string status);
        public signal void invite_requested (CalendarEvent evt);
        public signal void export_requested (CalendarEvent evt);

        public EventDetails (CalendarApp app, CalendarEvent evt) {
            this.app = app;
            this.evt = evt;
            add_css_class ("cal-details-popover");
            var box = new Box (Orientation.VERTICAL, 8);
            box.add_css_class ("cal-details");
            box.set_size_request (320, -1);

            var head = new Box (Orientation.HORIZONTAL, 8);
            var swatch = new Box (Orientation.HORIZONTAL, 0);
            swatch.add_css_class ("cal-color-swatch");
            swatch.valign = Align.CENTER;
            CalendarLayout.tint (swatch, evt.color);
            head.append (swatch);
            var title = new Label (evt.title != "" ? evt.title : _("Untitled Event"));
            title.add_css_class ("cal-details-title");
            title.wrap = true;
            title.xalign = 0;
            title.hexpand = true;
            head.append (title);
            box.append (head);

            var provider = CalendarManager.get_default ().get_provider (evt.calendar_id);
            add_line (box, "x-office-calendar-symbolic", provider != null ? provider.name : "");
            string when = evt.start_time.format ("%A %-d %B %Y");
            if (!CalendarLayout.same_day (evt.start_time, evt.all_day ? evt.end_time.add_days (-1) : evt.end_time.add_seconds (-1))) {
                var last = evt.all_day ? evt.end_time.add_days (-1) : evt.end_time;
                when = "%s - %s".printf (evt.start_time.format ("%-d %b").strip (), last.format ("%-d %b %Y").strip ());
            }
            add_line (box, "alarm-symbolic", "%s\n%s".printf (when, CalendarLayout.time_range (evt)));
            if (evt.is_recurring ()) {
                var rule = RecurrenceRule.parse (evt.recurrence);
                if (rule != null) add_line (box, "media-playlist-repeat-symbolic", rule.describe (evt.start_time));
            }
            if (evt.location != null && evt.location != "") {
                string loc = evt.location;
                if (loc.has_prefix ("http://") || loc.has_prefix ("https://")) {
                    var link = new LinkButton.with_label (loc, loc);
                    link.halign = Align.START;
                    var row = new Box (Orientation.HORIZONTAL, 8);
                    var icon = new Image.from_icon_name ("camera-web-symbolic");
                    icon.add_css_class ("dim-label");
                    row.append (icon);
                    row.append (link);
                    box.append (row);
                } else {
                    add_line (box, "mark-location-symbolic", loc);
                }
            }
            if (evt.alarms != null && evt.alarms.length > 0) {
                string[] parts = {};
                foreach (int m in evt.alarms) parts += reminder_text (m);
                add_line (box, "preferences-system-notifications-symbolic", string.joinv (", ", parts));
            }

            string owner = app.settings.get_string ("owner-email").down ();
            bool organizer_is_me = evt.organizer == null || evt.organizer == "" || evt.organizer.down () == owner;
            CalendarAttendee? me = null;
            if (evt.attendees != null) {
                foreach (var a in evt.attendees) if (owner != "" && a.email.down () == owner) me = a;
            }
            if (!organizer_is_me && me == null && owner == "" && evt.attendees != null && evt.attendees.size == 1) {
                me = evt.attendees[0];
            }

            if (evt.attendees != null && evt.attendees.size > 0) {
                var people = new Label (_("People"));
                people.add_css_class ("heading");
                people.xalign = 0;
                people.margin_top = 4;
                box.append (people);
                if (evt.organizer != null && evt.organizer != "") {
                    string org = evt.organizer_name != null && evt.organizer_name != "" ? evt.organizer_name : evt.organizer;
                    add_line (box, "avatar-default-symbolic", _("%s (organizer)").printf (org));
                }
                int going = 0, declined = 0, pending = 0;
                foreach (var a in evt.attendees) {
                    if (a.status == "ACCEPTED") going++;
                    else if (a.status == "DECLINED") declined++;
                    else pending++;
                    var row = add_line (box, EventEditor.status_icon (a.status),
                        "%s · %s".printf (a.display_name (), EventEditor.status_label (a.status)));
                    row.tooltip_text = a.email + (a.role == "OPT-PARTICIPANT" ? " · " + _("Optional") : "");
                }
                var counts = new Label (_("%d going, %d not going, %d awaiting").printf (going, declined, pending));
                counts.add_css_class ("dim-label");
                counts.add_css_class ("caption");
                counts.xalign = 0;
                box.append (counts);
            }

            if (!organizer_is_me && me != null) {
                var banner = new Box (Orientation.VERTICAL, 6);
                banner.add_css_class ("cal-invite-banner");
                var q = new Label (_("Going?"));
                q.xalign = 0;
                q.add_css_class ("heading");
                banner.append (q);
                var answers = new Box (Orientation.HORIZONTAL, 6);
                answers.homogeneous = true;
                string[] statuses = { "ACCEPTED", "TENTATIVE", "DECLINED" };
                string[] labels = { _("Yes"), _("Maybe"), _("No") };
                for (int i = 0; i < 3; i++) {
                    var btn = new ToggleButton.with_label (labels[i]);
                    btn.active = me.status == statuses[i];
                    string status = statuses[i];
                    btn.clicked.connect (() => {
                        popdown ();
                        respond_requested (evt, status);
                    });
                    answers.append (btn);
                }
                banner.append (answers);
                box.append (banner);
            }

            if (evt.description != null && evt.description != "") {
                var notes = new Label (evt.description);
                notes.wrap = true;
                notes.xalign = 0;
                notes.selectable = true;
                notes.max_width_chars = 44;
                notes.margin_top = 4;
                box.append (notes);
            }

            var actions = new Box (Orientation.HORIZONTAL, 6);
            actions.margin_top = 8;
            bool writable = EventStore.is_editable (CalendarManager.get_default ().get_provider (evt.calendar_id));
            if (writable) {
                actions.append (action_button ("user-trash-symbolic", _("Delete"), () => delete_requested (evt)));
                actions.append (action_button ("edit-copy-symbolic", _("Duplicate"), () => duplicate_requested (evt)));
            }
            actions.append (action_button ("edit-paste-symbolic", _("Copy"), () => copy_requested (evt)));
            actions.append (action_button ("document-save-symbolic", _("Export"), () => export_requested (evt)));
            if (writable && organizer_is_me && evt.attendees != null && evt.attendees.size > 0) {
                actions.append (action_button ("mail-send-symbolic", _("Send Invitations"), () => invite_requested (evt)));
            }
            var spacer = new Box (Orientation.HORIZONTAL, 0);
            spacer.hexpand = true;
            actions.append (spacer);
            if (writable) {
                var edit = new Button.with_label (_("Edit"));
                edit.add_css_class ("suggested-action");
                edit.clicked.connect (() => {
                    popdown ();
                    edit_requested (evt);
                });
                actions.append (edit);
            }
            box.append (actions);
            child = box;
        }

        public delegate void Callback ();

        private Button action_button (string icon, string tooltip, owned Callback callback) {
            var btn = new Button.from_icon_name (icon);
            btn.add_css_class ("flat");
            btn.tooltip_text = tooltip;
            btn.clicked.connect (() => {
                popdown ();
                callback ();
            });
            return btn;
        }

        public static string reminder_text (int minutes) {
            if (minutes == 0) return _("At start");
            if (minutes < 60) return ngettext ("%d minute before", "%d minutes before", minutes).printf (minutes);
            if (minutes < 1440) return ngettext ("%d hour before", "%d hours before", minutes / 60).printf (minutes / 60);
            return ngettext ("%d day before", "%d days before", minutes / 1440).printf (minutes / 1440);
        }

        private Box add_line (Box parent, string icon_name, string text) {
            var row = new Box (Orientation.HORIZONTAL, 8);
            var icon = new Image.from_icon_name (icon_name);
            icon.add_css_class ("dim-label");
            icon.valign = Align.START;
            icon.margin_top = 2;
            row.append (icon);
            var label = new Label (text);
            label.wrap = true;
            label.xalign = 0;
            label.hexpand = true;
            label.selectable = false;
            row.append (label);
            parent.append (row);
            return row;
        }
    }

    public class AgendaView : Box {
        private CalendarManager mgr;
        private Box list;
        private ScrolledWindow scroll;
        private WelcomePage empty;
        private StatusPage no_match;
        private string query = "";
        private DateTime from;

        public signal void event_activated (CalendarEvent evt, Widget source);
        public signal void clear_search_requested ();

        public AgendaView (CalendarManager mgr) {
            Object (orientation: Orientation.VERTICAL, spacing: 0);
            this.mgr = mgr;
            from = CalendarLayout.day_start (new DateTime.now_local ());
            scroll = new ScrolledWindow ();
            scroll.hscrollbar_policy = PolicyType.NEVER;
            scroll.vexpand = true;
            list = new Box (Orientation.VERTICAL, 2);
            list.margin_start = 24;
            list.margin_top = 12;
            list.margin_end = 24;
            list.margin_bottom = 24;
            scroll.child = list;
            append (scroll);
            empty = new WelcomePage ();
            empty.is_section = true;
            empty.app_icon_name = "dev.sinty.calendar";
            empty.title = _("Nothing Planned");
            empty.add_action ("x-office-calendar", _("New Event"), _("Add something to your calendar"), () => activate_action ("app.new-event", null));
            empty.add_action ("document-open", _("Import"), _("Events from a calendar file"), () => activate_action ("app.import", null));
            empty.add_action ("network-workgroup", _("Subscribe to a Link"), _("Follow a calendar published online"), () => activate_action ("app.subscribe", null));
            empty.vexpand = true;
            empty.visible = false;
            append (empty);
            no_match = new StatusPage ();
            no_match.icon_name = "system-search";
            no_match.title = _("No Events Found");
            no_match.vexpand = true;
            no_match.visible = false;
            var clear = new Button.with_label (_("Clear Search"));
            clear.halign = Align.CENTER;
            clear.add_css_class ("pill");
            clear.add_css_class ("suggested-action");
            clear.clicked.connect (() => clear_search_requested ());
            no_match.child = clear;
            append (no_match);
        }

        public void set_date (DateTime date) {
            from = CalendarLayout.day_start (date);
            refresh.begin ();
        }

        public void set_query (string text) {
            query = text.strip ();
            refresh.begin ();
        }

        public bool searching { get { return query != ""; } }

        public async void refresh () {
            Gee.List<CalendarEvent?> events;
            if (query != "") {
                var now = new DateTime.now_local ();
                events = yield mgr.search (query, now.add_years (-2), now.add_years (2));
            } else {
                events = yield mgr.get_events (from, from.add_days (60));
                events.sort ((a, b) => a.start_time.compare (b.start_time));
            }
            Widget? c = list.get_first_child ();
            while (c != null) { var n = c.get_next_sibling (); list.remove (c); c = n; }
            empty.visible = events.size == 0 && query == "";
            no_match.visible = events.size == 0 && query != "";
            scroll.visible = events.size > 0;
            empty.subtitle = _("Nothing planned in the next 60 days");
            no_match.description = _("No events match “%s”.").printf (query);
            string last_day = "";
            var today = new DateTime.now_local ();
            foreach (var evt in events) {
                string key = evt.start_time.format ("%Y-%m-%d");
                if (key != last_day) {
                    last_day = key;
                    string text = evt.start_time.format ("%A %-d %B %Y");
                    if (CalendarLayout.same_day (evt.start_time, today)) text = _("Today") + ", " + text;
                    var header = new Label (text);
                    header.add_css_class ("cal-agenda-day");
                    header.xalign = 0;
                    list.append (header);
                }
                var row = new Button ();
                row.add_css_class ("flat");
                row.add_css_class ("cal-agenda-row");
                var hbox = new Box (Orientation.HORIZONTAL, 10);
                var swatch = new Box (Orientation.HORIZONTAL, 0);
                swatch.add_css_class ("cal-color-swatch");
                swatch.valign = Align.CENTER;
                CalendarLayout.tint (swatch, evt.color);
                hbox.append (swatch);
                var time = new Label (evt.all_day ? _("All day") : CalendarLayout.time_label (evt.start_time));
                time.width_chars = 8;
                time.xalign = 0;
                time.add_css_class ("dim-label");
                hbox.append (time);
                var title = new Label (evt.title);
                title.xalign = 0;
                title.hexpand = true;
                title.ellipsize = Pango.EllipsizeMode.END;
                hbox.append (title);
                if (evt.location != null && evt.location != "") {
                    var loc = new Label (evt.location);
                    loc.add_css_class ("dim-label");
                    loc.ellipsize = Pango.EllipsizeMode.END;
                    loc.max_width_chars = 30;
                    hbox.append (loc);
                }
                row.child = hbox;
                var cap = evt;
                row.clicked.connect (() => event_activated (cap, row));
                list.append (row);
            }
        }
    }
}
