using Gtk;
using Singularity.Calendar;
using Singularity.Widgets;

namespace Singularity.Apps.Calendar {

    public class AgendaRows : Object {
        public const string STYLE = """
.cal-color-swatch {
    border-radius: 999px;
    min-width: 10px;
    min-height: 10px;
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
""";

        public static Label day_header (DateTime day) {
            string text = day.format ("%A %-d %B %Y");
            if (CalendarLayout.same_day (day, new DateTime.now_local ())) text = _("Today") + ", " + text;
            var header = new Label (text);
            header.add_css_class ("cal-agenda-day");
            header.xalign = 0;
            return header;
        }

        public static Button event_row (CalendarEvent evt) {
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
            return row;
        }
    }
}
