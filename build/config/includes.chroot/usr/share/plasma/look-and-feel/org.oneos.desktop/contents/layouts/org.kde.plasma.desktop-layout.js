/*
 * OneOS default desktop layout.
 *
 * Plasma runs this once, on a user's first login, when this package is the
 * LookAndFeelPackage. It is the supported way for a distribution to say what
 * its desktop looks like, and it replaces the appletsrc that used to live in
 * /etc/xdg -- which Plasma treated as an already-configured desktop and
 * therefore never laid anything out.
 *
 * THE SHAPE
 * Two surfaces, both glass, neither touching the screen edge the way a
 * classic taskbar does:
 *
 *   top    a slim bar: search on the left, the system tray on the right.
 *          Status lives up here, out of the way, the way a phone does it.
 *
 *   bottom a floating dock, centred, only as wide as what it holds: Start,
 *          the open windows, and the clock with quick settings behind it.
 *          Floating means a margin all round and rounded corners, so it
 *          reads as an object on the wallpaper rather than a strip cut
 *          off the bottom of the screen.
 *
 * This is the shape people expect a modern desktop to have. It is also,
 * deliberately, made only of OneOS's own applets and Plasma's stock ones,
 * with OneOS's own mark and colours: the arrangement is an idea, and ideas
 * are not anyone's property, but logos, icon sets and names are, and none of
 * those are borrowed.
 *
 * Every addWidget below is safe to fail: if an applet is missing Plasma
 * leaves a gap rather than aborting the script, so a broken OneOS applet
 * costs that one element and never the whole desktop.
 */

/* ---- Desktop --------------------------------------------------------- */
var desktops = desktopsForActivity(currentActivity());
for (var i = 0; i < desktops.length; i++) {
    var d = desktops[i];
    d.wallpaperPlugin = "org.kde.image";
    d.currentConfigGroup = ["Wallpaper", "org.kde.image", "General"];
    d.writeConfig("Image", "/usr/share/wallpapers/OneOS/");
    d.writeConfig("FillMode", 2);           /* scale and crop */

    /* Folder view settings: the desktop shows ~/Desktop, icons on a grid,
     * arranged left-to-right, top-to-bottom the way Windows users expect. */
    d.currentConfigGroup = ["General"];
    d.writeConfig("url", "desktop:/");
    d.writeConfig("arrangement", 0);        /* rows */
    d.writeConfig("alignment", 0);          /* left */
    d.writeConfig("iconSize", 3);           /* medium */
    d.writeConfig("labelWidth", 1);
    d.writeConfig("sortMode", 0);           /* manual: where you put it */
}

/* ---- Top bar --------------------------------------------------------- */
var top = new Panel;
top.location  = "top";
top.height    = 2 * gridUnit;
top.hiding    = "none";
top.floating  = false;
top.alignment = "left";
top.lengthMode = "fill";
top.opacity   = "translucent";

/* Global search. Typing anywhere in the launcher also searches, so this is
 * the same engine reached from a second, always-visible place. */
top.addWidget("org.kde.milou");
top.addWidget("org.kde.plasma.panelspacer");

/* The stock tray carries network, sound, battery, Bluetooth, notifications
 * and clipboard, and speaks every protocol those need. It is the one piece
 * of the panel it would be a mistake to rewrite (see quicksettings/main.qml). */
var tray = top.addWidget("org.kde.plasma.systemtray");

/* ---- Dock ------------------------------------------------------------ */
var dock = new Panel;
dock.location   = "bottom";
dock.height     = 3 * gridUnit;
dock.hiding     = "none";
dock.floating   = true;          /* the margin and the rounded corners */
dock.alignment  = "center";
dock.lengthMode = "fit";         /* as wide as its contents, no wider */
dock.opacity    = "translucent";

/* Start. Falls back to Kickoff if org.oneos.launcher fails to load, so the
 * button that matters most is never absent. */
var start = dock.addWidget("org.oneos.launcher");
if (start) {
    start.currentConfigGroup = ["General"];
    start.writeConfig("favorites",
        "firefox-esr.desktop,org.kde.dolphin.desktop,oneos-windows-settings.desktop," +
        "oneos-android-settings.desktop,org.kde.konsole.desktop,oneos-control-panel.desktop," +
        "oneos-about.desktop");
    start.writeConfig("showAppsByName", true);
} else {
    dock.addWidget("org.kde.plasma.kickoff");
}

/* Open windows, with their titles. A row of identical icons makes people
 * hunt; a title is read at a glance. */
if (!dock.addWidget("org.oneos.taskbar")) {
    dock.addWidget("org.kde.plasma.taskmanager");
}

/* Clock, and the switches behind it. */
if (!dock.addWidget("org.oneos.quicksettings")) {
    dock.addWidget("org.kde.plasma.digitalclock");
}
