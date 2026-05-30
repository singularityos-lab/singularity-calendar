using GLib;
using Gee;
using Singularity.Calendar;

namespace Singularity.Goa {

    public class GoaCalendarProvider : GLib.Object, CalendarProvider {
        private global::Goa.Object object;
        private string _id;
        private string _name;
        private string _color;
        private bool _is_visible = true;
        public string name { get { return _name; } }
        public string id { get { return _id; } }
        public string color { get { return _color; } }
        public bool is_visible {
            get { return _is_visible; }
            set {
                if (_is_visible != value) {
                    _is_visible = value;
                    events_changed();
                }
            }
        }

        public GoaCalendarProvider(global::Goa.Object object) {
            this.object = object;
            var account = object.get_account();
            this._id = "goa-" + account.id;
            this._name = account.presentation_identity;
            if (account.provider_type == "google") {
                _color = "#4285F4";
            } else if (account.provider_type == "owncloud" || account.provider_type == "nextcloud") {
                _color = "#0082C9";
            } else if (account.provider_type == "exchange") {
                _color = "#0078D7";
            } else {
                _color = CalendarManager.generate_color(_name);
            }
        }

        public async Gee.List<CalendarEvent?> get_events(DateTime start, DateTime end) throws GLib.Error {
            var list = new Gee.ArrayList<CalendarEvent?>();

            var cal_iface = object.get_calendar();
            if (cal_iface == null) return list;

            string caldav_uri = cal_iface.uri;
            if (caldav_uri == null || caldav_uri == "") return list;

            string? auth_header = get_auth_header();
            if (auth_header == null) return list;

            // RFC 4791 calendar-query REPORT to fetch events in the date range
            string start_str = start.to_utc().format("%Y%m%dT%H%M%SZ");
            string end_str   = end.to_utc().format("%Y%m%dT%H%M%SZ");
            string report_body = """<?xml version="1.0" encoding="utf-8"?>
<c:calendar-query xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">
  <d:prop><d:getetag/><c:calendar-data/></d:prop>
  <c:filter>
    <c:comp-filter name="VCALENDAR">
      <c:comp-filter name="VEVENT">
        <c:time-range start="%s" end="%s"/>
      </c:comp-filter>
    </c:comp-filter>
  </c:filter>
</c:calendar-query>""".printf(start_str, end_str);

            var session = new Soup.Session();
            session.user_agent = "SingularityDesktop/1.0";

            var msg = new Soup.Message("REPORT", caldav_uri);
            msg.request_headers.append("Authorization", auth_header);
            msg.request_headers.append("Content-Type", "application/xml; charset=utf-8");
            msg.request_headers.append("Depth", "1");
            msg.set_request_body_from_bytes("application/xml", new GLib.Bytes(report_body.data));

            try {
                var bytes = yield session.send_and_read_async(msg, GLib.Priority.DEFAULT, null);
                // 207 Multi-Status is the expected success response
                if (msg.status_code != 207 && msg.status_code != 200) return list;
                string xml = (string) bytes.get_data();
                extract_events_from_multistatus(xml, list);
            } catch (Error e) {
                warning("GOA CalDAV request failed for %s: %s", _name, e.message);
            }
            return list;
        }

        private string? get_auth_header() {
            // Try OAuth2 first (Google, Nextcloud with OAuth)
            var oauth2 = object.get_oauth2_based();
            if (oauth2 != null) {
                try {
                    string access_token; int expires_in;
                    oauth2.call_get_access_token_sync(out access_token, out expires_in, null);
                    if (access_token != null && access_token.length > 0)
                        return "Bearer " + access_token;
                } catch (Error e) {
                    warning("GOA OAuth2 token error for %s: %s", _name, e.message);
                }
            }
            // Fall back to HTTP Basic (ownCloud, generic CalDAV)
            var password_based = object.get_password_based();
            if (password_based != null) {
                try {
                    string password;
                    var account = object.get_account();
                    password_based.call_get_password_sync(account.id, out password, null);
                    if (password != null && password.length > 0) {
                        string creds = GLib.Base64.encode((account.presentation_identity + ":" + password).data);
                        return "Basic " + creds;
                    }
                } catch (Error e) {
                    warning("GOA password error for %s: %s", _name, e.message);
                }
            }
            return null;
        }

        /**
         * Extract calendar-data blocks from a CalDAV multi-status XML response
         * and parse each VEVENT into a CalendarEvent.
         */

        private void extract_events_from_multistatus(string xml, Gee.List<CalendarEvent?> list) {
            // Find all <cal:calendar-data> (or equivalent namespace prefix) content blocks
            string lower = xml.ascii_down();
            int search_pos = 0;
            while (true) {
                int tag_open = lower.index_of("calendar-data>", search_pos);
                if (tag_open == -1) break;
                // Rewind to the '<' of the opening tag
                int lt = tag_open;
                while (lt > 0 && xml[lt] != '<') lt--;
                int content_start = tag_open + "calendar-data>".length;
                // Find closing tag
                string open_tag = xml.substring(lt, tag_open - lt + "calendar-data>".length);
                // Build closing tag by replacing '<' with '</'
                int colon = open_tag.index_of(":");
                string prefix = colon >= 0 ? open_tag.substring(1, colon) : "";
                string close_tag = prefix.length > 0
                    ? "</" + prefix + ":calendar-data>"
                    : "</calendar-data>";
                int close_tag_pos = lower.index_of(close_tag.ascii_down(), content_start);
                if (close_tag_pos == -1) {
                    // Try generic close
                    close_tag_pos = lower.index_of("</", content_start);
                    if (close_tag_pos == -1) break;
                }
                string ical = xml.substring(content_start, close_tag_pos - content_start).strip();
                if (ical.length > 0)
                    parse_ical_events(ical, list);
                search_pos = close_tag_pos + close_tag.length;
            }
        }

        private void parse_ical_events(string ical, Gee.List<CalendarEvent?> list) {
            string[] lines = ical.replace("\r\n", "\n").replace("\r", "\n").split("\n");
            bool in_vevent = false;
            CalendarEvent? current = null;

            foreach (string raw_line in lines) {
                string line = raw_line.strip();

                if (line == "BEGIN:VEVENT") {
                    in_vevent = true;
                    current = CalendarEvent();
                    current.id = GLib.Uuid.string_random();
                    current.color = _color;
                    current.description = "";
                    current.all_day = false;
                    current.start_time = new DateTime.now_local();
                    current.end_time = current.start_time.add_hours(1);
                    continue;
                }

                if (line == "END:VEVENT") {
                    if (in_vevent && current != null && current.title != null && current.title.length > 0)
                        list.add(current);
                    in_vevent = false;
                    current = null;
                    continue;
                }

                if (!in_vevent || current == null) continue;

                if (line.has_prefix("SUMMARY:")) {
                    current.title = unescape_ical(line.substring(8));
                } else if (line.has_prefix("DESCRIPTION:")) {
                    current.description = unescape_ical(line.substring(12));
                } else if (line.has_prefix("UID:")) {
                    current.id = line.substring(4);
                } else if (line.has_prefix("DTSTART;VALUE=DATE:")) {
                    current.all_day = true;
                    current.start_time = parse_ical_date(line.substring(19));
                    current.end_time = current.start_time.add_hours(24);
                } else if (line.has_prefix("DTSTART")) {
                    int colon = line.index_of(":");
                    if (colon >= 0)
                        current.start_time = parse_ical_date(line.substring(colon + 1));
                } else if (line.has_prefix("DTEND;VALUE=DATE:")) {
                    current.end_time = parse_ical_date(line.substring(17));
                } else if (line.has_prefix("DTEND")) {
                    int colon = line.index_of(":");
                    if (colon >= 0)
                        current.end_time = parse_ical_date(line.substring(colon + 1));
                }
            }
        }

        private DateTime parse_ical_date(string s) {
            try {
                if (s.length >= 8) {
                    int year  = int.parse(s.substring(0, 4));
                    int month = int.parse(s.substring(4, 2));
                    int day   = int.parse(s.substring(6, 2));
                    int hour = 0, min = 0, sec = 0;
                    bool utc = s.has_suffix("Z");
                    if (s.contains("T") && s.length >= 15) {
                        var parts = s.split("T");
                        string t = parts[1].replace("Z", "");
                        if (t.length >= 6) {
                            hour = int.parse(t.substring(0, 2));
                            min  = int.parse(t.substring(2, 2));
                            sec  = int.parse(t.substring(4, 2));
                        }
                    }
                    if (utc)
                        return new DateTime.utc(year, month, day, hour, min, sec).to_local();
                    else
                        return new DateTime.local(year, month, day, hour, min, sec);
                }
            } catch {}
            return new DateTime.now_local();
        }

        private string unescape_ical(string s) {
            return s.replace("\\n", "\n").replace("\\,", ",").replace("\\;", ";").replace("\\\\", "\\");
        }

        public async void import_file(string path) throws GLib.Error {
            throw new IOError.NOT_SUPPORTED("Cannot import files into online accounts directly.");
        }
    }
}
