using Gtk;
using GLib;
using Gee;
using Singularity;
using Singularity.Calendar;
using Singularity.Widgets;

namespace Singularity.Apps.Calendar {

    public static int main (string[] args) {
        Intl.setlocale(GLib.LocaleCategory.ALL, "");
        string locale_dir = "/usr/share/locale";
        try {
            string exe = GLib.FileUtils.read_link("/proc/self/exe");
            locale_dir = GLib.Path.build_filename(GLib.Path.get_dirname(GLib.Path.get_dirname(exe)), "share", "locale");
        } catch (GLib.Error e) { }
        Intl.bindtextdomain("singularity-calendar", locale_dir);
        Intl.bind_textdomain_codeset("singularity-calendar", "UTF-8");
        Intl.textdomain("singularity-calendar");

        var app = new CalendarApp ();
        return app.run (args);
    }
}
