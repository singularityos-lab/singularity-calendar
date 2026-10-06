using GLib;
using Gee;
using Singularity.Calendar;

namespace Singularity.Apps.Calendar {

    public class Invitations : Object {
        public static string outbox_dir () {
            return Path.build_filename (Environment.get_user_cache_dir (), "singularity-calendar", "outbox");
        }

        private static string safe_name (string text) {
            var builder = new StringBuilder ();
            unichar c;
            int index = 0;
            while (text.get_next_char (ref index, out c)) {
                builder.append_unichar (c.isalnum () ? c : '-');
            }
            string name = builder.str;
            if (name == "") return "event";
            if (name.char_count () > 40) return name.substring (0, name.index_of_nth_char (40));
            return name;
        }

        public static string write_ics (CalendarEvent evt, string method, string? reply_email = null, string? reply_status = null) throws Error {
            DirUtils.create_with_parents (outbox_dir (), 0700);
            string path = Path.build_filename (outbox_dir (), "%s-%s.ics".printf (safe_name (evt.title ?? ""), method.down ()));
            string text;
            if (method == "REPLY") {
                text = Ics.reply (evt, reply_email, reply_status);
            } else {
                var list = new Gee.ArrayList<CalendarEvent?> ();
                CalendarEvent copy = evt;
                copy.occurrence_start = null;
                copy.alarms = {};
                list.add (copy);
                text = Ics.serialize (list, method);
            }
            FileUtils.set_contents (path, text);
            return path;
        }

        public static string summary (CalendarEvent evt) {
            var text = new StringBuilder ();
            text.append (evt.title ?? "");
            text.append ("\n");
            text.append (Singularity.Widgets.CalendarLayout.time_range (evt));
            text.append (" ");
            text.append (evt.start_time.format ("%A %-d %B %Y"));
            text.append ("\n");
            if (evt.is_recurring ()) {
                var rule = RecurrenceRule.parse (evt.recurrence);
                if (rule != null) text.append (rule.describe (evt.start_time) + "\n");
            }
            if (evt.location != null && evt.location != "") text.append (evt.location + "\n");
            if (evt.description != null && evt.description != "") text.append ("\n" + evt.description + "\n");
            return text.str;
        }

        public static bool compose (string[] recipients, string subject, string body, string attachment) {
            string? tool = Environment.find_program_in_path ("xdg-email");
            if (tool != null) {
                string[] argv = { tool, "--utf8", "--subject", subject, "--body", body, "--attach", attachment };
                foreach (string r in recipients) argv += r;
                try {
                    Process.spawn_async (null, argv, null, SpawnFlags.SEARCH_PATH, null, null);
                    return true;
                } catch (SpawnError e) {
                    warning ("Failed to open the mail composer: %s", e.message);
                }
            }
            var uri = new StringBuilder ("mailto:");
            uri.append (Uri.escape_string (string.joinv (",", recipients), "@", false));
            uri.append ("?subject=" + Uri.escape_string (subject, null, false));
            uri.append ("&body=" + Uri.escape_string (body + "\n" + _("The invitation file is saved at %s").printf (attachment), null, false));
            try {
                AppInfo.launch_default_for_uri (uri.str, null);
                return true;
            } catch (Error e) {
                warning ("Failed to open mail: %s", e.message);
                return false;
            }
        }

        public static bool send_invites (CalendarEvent evt, bool cancel = false) {
            if (evt.attendees == null || evt.attendees.size == 0) return false;
            string[] recipients = {};
            foreach (var a in evt.attendees) recipients += a.email;
            try {
                string path = write_ics (evt, cancel ? "CANCEL" : "REQUEST");
                string subject = cancel ? _("Cancelled: %s").printf (evt.title) : _("Invitation: %s").printf (evt.title);
                return compose (recipients, subject, summary (evt), path);
            } catch (Error e) {
                warning ("Failed to write invitation: %s", e.message);
                return false;
            }
        }

        public static bool send_reply (CalendarEvent evt, string my_email, string status) {
            if (evt.organizer == null || evt.organizer == "") return false;
            try {
                string path = write_ics (evt, "REPLY", my_email, status);
                string verb;
                switch (status) {
                    case "ACCEPTED": verb = _("Accepted"); break;
                    case "DECLINED": verb = _("Declined"); break;
                    default: verb = _("Tentative"); break;
                }
                return compose ({ evt.organizer }, "%s: %s".printf (verb, evt.title), summary (evt), path);
            } catch (Error e) {
                warning ("Failed to write reply: %s", e.message);
                return false;
            }
        }
    }
}
