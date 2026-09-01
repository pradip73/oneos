/*
 * OneOS Control Panel — the sixteen-tile grid from the design.
 *
 * Until now "Control Panel" was a renamed launcher for systemsettings. That is
 * a tree of categories designed for people who already know KDE's vocabulary:
 * "Workspace Behavior", "Window Management", "Shortcuts". A person looking for
 * their printer does not know which of those contains it.
 *
 * This is one page of labelled tiles, each naming a thing rather than a
 * subsystem, each opening the KDE settings module that actually handles it.
 * Nothing here reimplements a settings page -- the panels behind these tiles
 * are KDE's, and they work. What was missing was a way in that reads like the
 * problem the user has.
 *
 * Two tiles have no KDE equivalent at all: Windows apps and Android apps. They
 * sit beside Network and Display rather than in an Advanced page, because they
 * are the reason someone chose this OS.
 *
 * Runs as a window via `plasmawindowed org.oneos.controlpanel`, so it needs no
 * QML runtime beyond the one Plasma already ships.
 */

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.extras as PlasmaExtras
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasma5support as P5Support

PlasmoidItem {
    id: root

    preferredRepresentation: fullRepresentation
    Layout.minimumWidth: Kirigami.Units.gridUnit * 34
    Layout.minimumHeight: Kirigami.Units.gridUnit * 26

    P5Support.DataSource {
        id: exec
        engine: "executable"
        connectedSources: []
        onNewData: function (source) { disconnectSource(source) }
        function run(cmd) { if (cmd) connectSource(cmd) }
    }

    /* Named after what the user is looking for, not after the subsystem that
     * implements it: "Printers", not "Print queue management". */
    readonly property var entries: [
        { name: "Network",       hint: "Wi‑Fi and wired",        icon: "network-wired",              cmd: "systemsettings kcm_networkmanagement" },
        { name: "Display",       hint: "Size and brightness",    icon: "preferences-desktop-display",cmd: "systemsettings kcm_kscreen" },
        { name: "Sound",         hint: "Speakers and microphone",icon: "audio-volume-high",          cmd: "systemsettings kcm_pulseaudio" },
        { name: "Power",         hint: "Battery and sleep",      icon: "battery",                    cmd: "systemsettings kcm_powerdevilprofilesconfig" },
        { name: "Your account",  hint: "Name and password",      icon: "user-identity",              cmd: "systemsettings kcm_users" },
        { name: "Programs",      hint: "Install and remove",     icon: "plasmadiscover",             cmd: "plasma-discover" },
        { name: "Windows apps",  hint: "Wine, sandbox, storage", icon: "wine",                       cmd: "oneos-windows-settings" },
        { name: "Android apps",  hint: "Set up, start, stop",    icon: "phone",                      cmd: "oneos-android-settings" },
        { name: "Printers",      hint: "Add and manage",         icon: "printer",                    cmd: "systemsettings kcm_printer_manager" },
        { name: "Keyboard",      hint: "Layout and language",    icon: "input-keyboard",             cmd: "systemsettings kcm_keyboard" },
        { name: "Bluetooth",     hint: "Pair a device",          icon: "network-bluetooth",          cmd: "systemsettings kcm_bluetooth" },
        { name: "Appearance",    hint: "Wallpaper and colours",  icon: "preferences-desktop-theme",  cmd: "systemsettings kcm_wallpaper" },
        { name: "Accessibility", hint: "Text size and reader",   icon: "preferences-desktop-accessibility", cmd: "systemsettings kcm_access" },
        { name: "Date and time", hint: "Clock and time zone",    icon: "clock",                      cmd: "systemsettings kcm_clock" },
        { name: "Updates",       hint: "Keep OneOS current",     icon: "system-software-update",     cmd: "plasma-discover --mode update" },
        { name: "This computer", hint: "What is inside it",      icon: "computer",                   cmd: "oneos-about" }
    ]

    property string filter: ""

    fullRepresentation: Item {
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Kirigami.Units.largeSpacing
            spacing: Kirigami.Units.largeSpacing

            PlasmaExtras.SearchField {
                id: search
                Layout.fillWidth: true
                placeholderText: i18n("Search settings")
                onTextChanged: root.filter = text.toLowerCase()
                Keys.onEscapePressed: { text = ""; }
            }

            GridView {
                id: grid
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                cellWidth: Math.floor(width / Math.max(1, Math.floor(width / (Kirigami.Units.gridUnit * 8))))
                cellHeight: Kirigami.Units.gridUnit * 6

                model: root.entries.filter(function (e) {
                    return root.filter === ""
                        || e.name.toLowerCase().indexOf(root.filter) !== -1
                        || e.hint.toLowerCase().indexOf(root.filter) !== -1
                })

                delegate: MouseArea {
                    width: grid.cellWidth
                    height: grid.cellHeight
                    hoverEnabled: true
                    onClicked: exec.run(modelData.cmd)

                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: Kirigami.Units.smallSpacing / 2
                        radius: Kirigami.Units.cornerRadius
                        color: Kirigami.Theme.highlightColor
                        opacity: parent.containsMouse ? 0.14 : 0
                        Behavior on opacity { NumberAnimation { duration: 100 } }
                    }

                    ColumnLayout {
                        anchors.centerIn: parent
                        width: parent.width - Kirigami.Units.largeSpacing
                        spacing: Kirigami.Units.smallSpacing / 2

                        Kirigami.Icon {
                            source: modelData.icon
                            Layout.alignment: Qt.AlignHCenter
                            Layout.preferredWidth: Kirigami.Units.iconSizes.medium
                            Layout.preferredHeight: Kirigami.Units.iconSizes.medium
                        }
                        QQC2.Label {
                            Layout.fillWidth: true
                            text: modelData.name
                            horizontalAlignment: Text.AlignHCenter
                            font.bold: true
                            elide: Text.ElideRight
                        }
                        /* The hint is what makes a grid of sixteen icons
                         * scannable instead of a guessing game. */
                        QQC2.Label {
                            Layout.fillWidth: true
                            text: modelData.hint
                            horizontalAlignment: Text.AlignHCenter
                            font: Kirigami.Theme.smallFont
                            opacity: 0.65
                            wrapMode: Text.WordWrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                        }
                    }
                }
            }

            QQC2.Label {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: i18n("Nothing matches “%1”", search.text)
                opacity: 0.6
                visible: grid.count === 0
            }
        }
    }
}
