using GLib;
using Gee;
using Singularity.Calendar;

namespace Singularity.Apps.Calendar {

    public enum EditScope {
        THIS,
        FOLLOWING,
        ALL
    }

    public class EventStore : Object {
        private CalendarManager mgr;

        public EventStore (CalendarManager mgr) {
            this.mgr = mgr;
        }

        public WritableCalendarProvider? writable (string? calendar_id) {
            if (calendar_id == null) return null;
            var provider = mgr.get_provider (calendar_id);
            return is_editable (provider) ? (WritableCalendarProvider) provider : null;
        }

        public static bool is_editable (CalendarProvider? provider) {
            if (!(provider is WritableCalendarProvider)) return false;
            var online = provider as AccountCalendarProvider;
            return online == null || !online.read_only;
        }

        public static string label_for (CalendarProvider provider) {
            var online = provider as AccountCalendarProvider;
            if (online == null) return provider.name;
            return "%s, %s".printf (provider.name, online.account_name);
        }

        public static Gee.List<WritableCalendarProvider> editable_providers (CalendarManager mgr) {
            var result = new Gee.ArrayList<WritableCalendarProvider> ();
            foreach (var provider in mgr.get_writable_providers ()) {
                if (is_editable (provider)) result.add (provider);
            }
            return result;
        }

        public static CalendarEvent blank (DateTime start, DateTime end, bool all_day) {
            var evt = CalendarEvent ();
            evt.id = Uuid.string_random ();
            evt.title = "";
            evt.description = "";
            evt.location = "";
            evt.recurrence = "";
            evt.organizer = "";
            evt.organizer_name = "";
            evt.color = "";
            evt.calendar_id = "";
            evt.exdates = {};
            evt.alarms = {};
            evt.attendees = new Gee.ArrayList<CalendarAttendee> ();
            evt.start_time = start;
            evt.end_time = end;
            evt.all_day = all_day;
            evt.occurrence_start = null;
            return evt;
        }

        public static Gee.ArrayList<CalendarAttendee> copy_attendees (Gee.List<CalendarAttendee>? list) {
            var result = new Gee.ArrayList<CalendarAttendee> ();
            if (list != null) foreach (var a in list) result.add (a.copy ());
            return result;
        }

        public void add (CalendarEvent evt) {
            var provider = writable (evt.calendar_id);
            if (provider == null) return;
            CalendarEvent stored = evt;
            stored.occurrence_start = null;
            provider.add_event (stored);
        }

        private static string[] without (string[] values, string key) {
            string[] result = {};
            foreach (string value in values) {
                var parsed = new DateTime.from_iso8601 (value, new TimeZone.local ());
                if (parsed != null && RecurrenceRule.occurrence_key (parsed) == key) continue;
                result += value;
            }
            return result;
        }

        private static string truncate_rule (string rrule, DateTime master_start, DateTime cut, out int remaining) {
            remaining = 0;
            var rule = RecurrenceRule.parse (rrule);
            if (rule == null) return rrule;
            if (rule.count > 0) {
                var before = rule.occurrences (master_start, master_start, cut);
                remaining = int.max (0, rule.count - before.size);
                rule.count = int.max (1, before.size);
            } else {
                rule.until = cut.add_seconds (-1);
            }
            return rule.to_rrule ();
        }

        public void save (CalendarEvent? original, CalendarEvent edited, EditScope scope) {
            if (original == null) {
                add (edited);
                return;
            }
            var old_provider = writable (original.calendar_id);
            var new_provider = writable (edited.calendar_id);
            if (old_provider == null || new_provider == null) return;
            var master = old_provider.find_event (original.id);
            if (master == null) {
                add (edited);
                return;
            }

            if (!master.is_recurring () || original.occurrence_start == null || scope == EditScope.ALL) {
                CalendarEvent updated = edited;
                updated.id = master.id;
                updated.occurrence_start = null;
                if (master.is_recurring () && original.occurrence_start != null) {
                    int64 shift = edited.start_time.difference (original.start_time);
                    int64 duration = edited.end_time.difference (edited.start_time);
                    updated.start_time = master.start_time.add (shift);
                    updated.end_time = updated.start_time.add (duration);
                    updated.exdates = shift == 0 ? master.exdates : new string[0];
                }
                if (old_provider == new_provider) {
                    new_provider.update_event (updated);
                } else {
                    old_provider.delete_event (master.id);
                    new_provider.add_event (updated);
                }
                return;
            }

            string key = RecurrenceRule.occurrence_key (original.occurrence_start);
            if (scope == EditScope.THIS) {
                CalendarEvent m = master;
                m.exdates = Ics.with_string (m.exdates, original.occurrence_start.format_iso8601 ());
                old_provider.update_event (m);
                CalendarEvent single = edited;
                single.id = Uuid.string_random ();
                single.recurrence = "";
                single.exdates = {};
                single.occurrence_start = null;
                new_provider.add_event (single);
                return;
            }

            int remaining;
            CalendarEvent m = master;
            m.recurrence = truncate_rule (master.recurrence, master.start_time, original.occurrence_start, out remaining);
            m.exdates = without (m.exdates, key);
            old_provider.update_event (m);
            CalendarEvent series = edited;
            series.id = Uuid.string_random ();
            series.occurrence_start = null;
            series.exdates = {};
            if (remaining > 0 && series.is_recurring () && series.recurrence == master.recurrence) {
                var rule = RecurrenceRule.parse (series.recurrence);
                if (rule != null) {
                    rule.count = remaining;
                    series.recurrence = rule.to_rrule ();
                }
            }
            new_provider.add_event (series);
        }

        public void remove (CalendarEvent evt, EditScope scope) {
            var provider = writable (evt.calendar_id);
            if (provider == null) return;
            var master = provider.find_event (evt.id);
            if (master == null) return;
            if (!master.is_recurring () || evt.occurrence_start == null || scope == EditScope.ALL) {
                provider.delete_event (master.id);
                return;
            }
            CalendarEvent m = master;
            if (scope == EditScope.THIS) {
                m.exdates = Ics.with_string (m.exdates, evt.occurrence_start.format_iso8601 ());
            } else {
                if (evt.occurrence_start.compare (master.start_time) <= 0) {
                    provider.delete_event (master.id);
                    return;
                }
                int remaining;
                m.recurrence = truncate_rule (master.recurrence, master.start_time, evt.occurrence_start, out remaining);
            }
            provider.update_event (m);
        }

        public CalendarEvent? copy_to (CalendarEvent evt, DateTime new_start, string? calendar_id = null) {
            string target = calendar_id ?? evt.calendar_id;
            if (writable (target) == null) return null;
            CalendarEvent copy = evt;
            int64 duration = evt.end_time.difference (evt.start_time);
            copy.id = Uuid.string_random ();
            copy.calendar_id = target;
            copy.start_time = new_start;
            copy.end_time = new_start.add (duration);
            copy.occurrence_start = null;
            copy.recurrence = "";
            copy.exdates = {};
            copy.attendees = copy_attendees (evt.attendees);
            add (copy);
            return copy;
        }

        public void move (CalendarEvent evt, DateTime new_start) {
            CalendarEvent edited = evt;
            int64 duration = evt.end_time.difference (evt.start_time);
            edited.start_time = new_start;
            edited.end_time = new_start.add (duration);
            save (evt, edited, evt.occurrence_start != null ? EditScope.THIS : EditScope.ALL);
        }

        public void set_my_status (CalendarEvent evt, string email, string status) {
            var provider = writable (evt.calendar_id);
            if (provider == null) return;
            var master = provider.find_event (evt.id);
            if (master == null || master.attendees == null) return;
            CalendarEvent m = master;
            m.attendees = copy_attendees (master.attendees);
            foreach (var attendee in m.attendees) {
                if (attendee.email.down () == email.down ()) attendee.status = status;
            }
            provider.update_event (m);
        }
    }
}
