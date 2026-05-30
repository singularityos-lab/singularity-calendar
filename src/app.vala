using Gtk;
using GLib;
using Gee;
using Singularity;
using Singularity.Calendar;
using Singularity.Widgets;

namespace Singularity.Apps.Calendar {

    public class CalendarApp : Singularity.Application {
        private CalendarWindow win;

        public CalendarApp () {
            Object (application_id: "dev.sinty.calendar");
        }

        public override void activate () {
            setup_styles ();
            if (win != null) { win.present (); return; }
            win = new CalendarWindow (this);
            win.present ();
        }

        private void setup_styles () {
            var provider = new Gtk.CssProvider ();
            provider.load_from_data (CAL_CSS.data);
            Gtk.StyleContext.add_provider_for_display (
                Gdk.Display.get_default (), provider,
                Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);
        }

        private const string CAL_CSS = """
/* Calendar Widgets */

/* Nav picker (sidebar) */
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

.cal-nav-day-btn.today {
    background-color: @accent_color;
    color: white;
    font-weight: bold;
}

.cal-nav-day-btn.selected:not(.today) {
    background-color: alpha(@accent_color, 0.18);
}

.cal-nav-today-btn {
    font-size: 11px;
    padding: 2px 8px;
    border-radius: 10px;
    min-height: 22px;
    margin: 0 4px;
}

/* Day-of-week header row */
.cal-dow-header {
    border-bottom: 1px solid alpha(@borders, 0.55);
    background-color: alpha(@headerbar_bg_color, 0.35);
}

.cal-dow-label {
    font-size: 11px;
    font-weight: bold;
    opacity: 0.6;
    padding: 7px 0;
}

/* Month view */
.cal-month-view {
    background-color: transparent;
}

.cal-month-grid {
    border-top: none;
    background-color: transparent;
}

.cal-day-cell {
    border-right: 1px solid alpha(@text_color, 0.08);
    border-bottom: 1px solid alpha(@text_color, 0.08);
    min-height: 90px;
    min-width: 80px;
    background-color: transparent;
}

.cal-day-cell:last-child {
    border-right: none;
}

.cal-day-cell.out-of-month {
    background-color: transparent;
    opacity: 0.35;
}

.cal-day-cell.today {
    background-color: alpha(@accent_color, 0.07);
}

.cal-day-num {
    font-size: 12px;
    opacity: 0.75;
}

.cal-today-badge {
    background-color: @accent_color;
    color: white;
    font-weight: bold;
    font-size: 12px;
    border-radius: 12px;
    min-width: 24px;
    min-height: 24px;
    padding: 2px 4px;
}

.cal-more-label {
    font-size: 11px;
    opacity: 0.55;
}

/* Event chips */
.cal-event-chip {
    font-size: 11px;
    border-radius: 5px;
    padding: 2px 0;
    min-height: 18px;
    background-color: alpha(@accent_color, 0.12);
}

.cal-event-chip:hover {
    background-color: alpha(@accent_color, 0.22);
}

.cal-event-chip.compact {
    min-height: 16px;
    padding: 1px 0;
}

.cal-timed-event {
    border-radius: 5px;
    padding: 3px 5px;
    background-color: alpha(@accent_color, 0.18);
    font-size: 11px;
}

.cal-timed-event:hover {
    background-color: alpha(@accent_color, 0.28);
}

.cal-event-time {
    font-size: 10px;
    opacity: 0.75;
}

/* Week / Day views */
.cal-week-view,
.cal-day-view {
    background-color: transparent;
}

.cal-week-header {
    border-bottom: 1px solid alpha(@text_color, 0.08);
    background-color: alpha(@text_color, 0.03);
}

.cal-week-day-num {
    font-size: 20px;
    font-weight: 300;
    opacity: 0.9;
}

.cal-day-title {
    font-size: 15px;
    font-weight: 600;
}

.cal-time-gutter {
    min-width: 56px;
}

.cal-time-label {
    font-size: 10px;
    opacity: 0.55;
    min-width: 50px;
    padding-right: 6px;
    color: @window_fg_color;
}

.cal-hour-even {
    border-bottom: 1px solid alpha(@text_color, 0.08);
}

.cal-hour-odd {
    border-bottom: 1px dashed alpha(@text_color, 0.05);
}
""";
    }
}
