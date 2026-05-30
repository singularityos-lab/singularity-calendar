using GLib;
using Gee;
using Json;

namespace Singularity.Calendar {

    public class LocalProvider : GLib.Object, CalendarProvider, WritableCalendarProvider {
        private ArrayList<CalendarEvent?> events;
        private bool _is_visible = true;
        private File storage_file;
        private bool loaded = false;
        private string _name;
        private string _id;
        private string _color;
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

        public LocalProvider(string name = "Local", string id = "local-provider", string filename = "local.json", string color = "#3584e4") {
            this._name = name;
            this._id = id;
            this._color = color;
            events = new ArrayList<CalendarEvent?>();
            string data_dir = Environment.get_user_data_dir();
            string calendar_dir = GLib.Path.build_filename(data_dir, "singularity", "calendar");
            DirUtils.create_with_parents(calendar_dir, 0755);
            storage_file = File.new_for_path(GLib.Path.build_filename(calendar_dir, filename));
        }

        public async Gee.List<CalendarEvent?> get_events(DateTime start, DateTime end) throws Error {
            ensure_loaded();
            var result = new ArrayList<CalendarEvent?>();
            foreach (var evt in events) {
                if (evt.start_time.compare(end) < 0 && evt.end_time.compare(start) > 0) {
                    result.add(evt);
                }
            }
            return result;
        }

        public async void import_file(string path) throws Error {
            ensure_loaded();
            try {
                var file = File.new_for_path(path);
                var dis = new DataInputStream(file.read());
                string line;
                CalendarEvent? current_event = null;
                bool changed = false;
                while ((line = dis.read_line(null)) != null) {
                    line = line.strip();
                    if (line == "BEGIN:VEVENT") {
                        current_event = CalendarEvent();
                        current_event.id = GLib.Uuid.string_random();
                        current_event.color = "#3584e4";
                    } else if (line == "END:VEVENT") {
                        if (current_event != null) {
                            events.add(current_event);
                            current_event = null;
                            changed = true;
                        }
                    } else if (current_event != null) {
                        if (line.has_prefix("SUMMARY:")) {
                            current_event.title = line.substring(8);
                        } else if (line.has_prefix("DTSTART:")) {
                            current_event.start_time = parse_ics_date(line.substring(8));
                        } else if (line.has_prefix("DTEND:")) {
                            current_event.end_time = parse_ics_date(line.substring(6));
                        } else if (line.has_prefix("DESCRIPTION:")) {
                            current_event.description = line.substring(12);
                        }
                    }
                }
                if (changed) {
                    save_events();
                    events_changed();
                }
            } catch (Error e) {
                warning("Failed to import ICS: %s", e.message);
                throw e;
            }
        }

        private void load_events() {
            if (!storage_file.query_exists()) return;
            try {
                var parser = new Json.Parser();
                parser.load_from_file(storage_file.get_path());
                var root = parser.get_root().get_array();
                events.clear();
                root.foreach_element((arr, index, node) => {
                    if (node.get_node_type() != Json.NodeType.OBJECT) return;
                    var obj = node.get_object();
                    CalendarEvent evt = CalendarEvent();
                    evt.id = obj.get_string_member("id");
                    evt.title = obj.get_string_member("title");
                    evt.description = obj.has_member("description") ? obj.get_string_member("description") : "";
                    evt.color = obj.has_member("color") ? obj.get_string_member("color") : "#3584e4";
                    evt.all_day = obj.has_member("all_day") ? obj.get_boolean_member("all_day") : false;
                    // Skip events with missing or unparseable start_time
                    if (!obj.has_member("start_time") || obj.get_string_member("start_time") == null)
                        return;
                    string start_str = obj.get_string_member("start_time");
                    var parsed_start = new DateTime.from_iso8601(start_str, new TimeZone.local());
                    if (parsed_start == null) return;
                    evt.start_time = parsed_start;

                    if (obj.has_member("end_time") && obj.get_string_member("end_time") != null) {
                        string end_str = obj.get_string_member("end_time");
                        var parsed_end = new DateTime.from_iso8601(end_str, new TimeZone.local());
                        evt.end_time = parsed_end ?? evt.start_time.add_hours(1);
                    } else {
                        evt.end_time = evt.start_time.add_hours(1);
                    }
                    events.add(evt);
                });
            } catch (Error e) {
                warning("Failed to load events: %s", e.message);
            }
        }

        private void ensure_loaded() {
            if (loaded) return;
            loaded = true;
            load_events();
        }

        private void save_events() {
            try {
                var builder = new Json.Builder();
                builder.begin_array();
                foreach (var evt in events) {
                    builder.begin_object();
                    builder.set_member_name("id");
                    builder.add_string_value(evt.id);
                    builder.set_member_name("title");
                    builder.add_string_value(evt.title);
                    builder.set_member_name("description");
                    builder.add_string_value(evt.description);
                    builder.set_member_name("color");
                    builder.add_string_value(evt.color);
                    builder.set_member_name("all_day");
                    builder.add_boolean_value(evt.all_day);
                    builder.set_member_name("start_time");
                    builder.add_string_value(evt.start_time.format_iso8601());
                    builder.set_member_name("end_time");
                    builder.add_string_value(evt.end_time.format_iso8601());
                    builder.end_object();
                }
                builder.end_array();
                var generator = new Json.Generator();
                generator.set_root(builder.get_root());
                generator.to_file(storage_file.get_path());
            } catch (Error e) {
                warning("Failed to save events: %s", e.message);
            }
        }

        private DateTime parse_ics_date(string ics_date) {
            try {
                if (ics_date.length >= 8) {
                    int year = int.parse(ics_date.substring(0, 4));
                    int month = int.parse(ics_date.substring(4, 2));
                    int day = int.parse(ics_date.substring(6, 2));
                    int hour = 0;
                    int minute = 0;
                    int second = 0;
                    if (ics_date.contains("T")) {
                        var parts = ics_date.split("T");
                        if (parts.length > 1) {
                            var time_part = parts[1];
                            if (time_part.length >= 6) {
                                hour = int.parse(time_part.substring(0, 2));
                                minute = int.parse(time_part.substring(2, 2));
                                second = int.parse(time_part.substring(4, 2));
                            }
                        }
                    }
                    return new DateTime.utc(year, month, day, hour, minute, second).to_local();
                }
            } catch (Error e) {}
            return new DateTime.now_local();
        }

        public void add_event(CalendarEvent evt) {
            ensure_loaded();
            events.add(evt);
            save_events();
            events_changed();
        }

        public void delete_event(string id) {
            ensure_loaded();
            for (int i = 0; i < events.size; i++) {
                if (events[i].id == id) {
                    events.remove_at(i);
                    save_events();
                    events_changed();
                    return;
                }
            }
        }

        public void update_event(CalendarEvent evt) {
            ensure_loaded();
            for (int i = 0; i < events.size; i++) {
                if (events[i].id == evt.id) {
                    events[i] = evt;
                    save_events();
                    events_changed();
                    return;
                }
            }
        }

        public void delete() {
            try {
                if (storage_file.query_exists()) {
                    storage_file.delete();
                }
            } catch (Error e) {
                warning("Failed to delete calendar storage: %s", e.message);
            }
        }
    }
}
