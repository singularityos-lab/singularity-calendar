using Gtk;
using GLib;
using Gee;
using Singularity;
using Singularity.Calendar;
using Singularity.Widgets;

namespace Singularity.Apps.Calendar {

    public static int main (string[] args) {
        var app = new CalendarApp ();
        return app.run (args);
    }
}
