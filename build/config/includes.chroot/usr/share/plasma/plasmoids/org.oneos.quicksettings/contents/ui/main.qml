/*
 * OneOS quick settings — the clock, and the switches people actually reach for.
 *
 * The design put one panel under the clock: "one place to look for what
 * happened while I was away". This is the switches half of it.
 *
 * WHAT THIS DELIBERATELY DOES NOT DO
 * It does not implement notifications. Plasma's notification applet already
 * speaks the freedesktop notification protocol, keeps history, does grouping,
 * inline replies, actions and do-not-disturb. Reimplementing that is a month's
 * work whose best possible outcome is matching what already exists, so the
 * notification applet stays in the tray beside this one. Writing a prettier
 * switch panel is worth doing; rewriting a working notification server is not.
 *
 * The toggles drive the ordinary command-line tools rather than private Plasma
 * APIs, so they keep working across Plasma versions -- and each one reads its
 * real state back rather than remembering what it last set, which is how these
 * panels usually end up lying after something else changes the setting.
 */

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.extras as PlasmaExtras
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasma5support as P5Support

PlasmoidItem {
    id: root

    preferredRepresentation: compactRepresentation

    property bool wifiOn: false
    property bool btOn: false
    property bool nightOn: false
    property bool wifiKnown: false
    property bool btKnown: false

    P5Support.DataSource {
        id: exec
        engine: "executable"
        connectedSources: []

        onNewData: function (source, data) {
            var out = (data["stdout"] || "").trim()

            if (source.indexOf("nmcli radio wifi") === 0) {
                root.wifiOn = (out === "enabled")
                root.wifiKnown = (out.length > 0)
            } else if (source.indexOf("rfkill list bluetooth") === 0) {
                // "Soft blocked: no" means the radio is on.
                root.btOn = out.indexOf("Soft blocked: no") !== -1
                root.btKnown = (out.length > 0)
            } else if (source.indexOf("NightLight") !== -1) {
                root.nightOn = (out.indexOf("true") !== -1)
            }
            disconnectSource(source)
        }

        function run(cmd) { if (cmd) connectSource(cmd) }
    }

    function refresh() {
        exec.run("nmcli radio wifi")
        exec.run("rfkill list bluetooth")
        exec.run("qdbus6 org.kde.KWin /org/kde/KWin/NightLight org.freedesktop.DBus.Properties.Get org.kde.KWin.NightLight running")
    }

    /* Poll rather than subscribe: the state can be changed from Settings, from
     * a keyboard key, or by the hardware switch, and a panel that only tracks
     * its own clicks will confidently show the wrong thing. Five seconds is
     * cheap and fast enough that nobody notices the lag. */
    Timer {
        interval: 5000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    /* ---------------- the clock on the panel ---------------- */
    compactRepresentation: MouseArea {
        id: clockArea
        hoverEnabled: true
        onClicked: root.expanded = !root.expanded
        Layout.minimumWidth: clockCol.implicitWidth + Kirigami.Units.largeSpacing

        ColumnLayout {
            id: clockCol
            anchors.centerIn: parent
            spacing: 0

            QQC2.Label {
                Layout.alignment: Qt.AlignHCenter
                text: Qt.formatTime(clock.now, "HH:mm")
                font.pointSize: Kirigami.Theme.defaultFont.pointSize
            }
            QQC2.Label {
                Layout.alignment: Qt.AlignHCenter
                text: Qt.formatDate(clock.now, "d MMM")
                font: Kirigami.Theme.smallFont
                opacity: 0.75
                visible: plasmoid.formFactor !== PlasmaCore.Types.Vertical
            }
        }

        QtObject {
            id: clock
            property date now: new Date()
        }
        Timer {
            interval: 1000; running: true; repeat: true
            onTriggered: clock.now = new Date()
        }
    }

    /* ---------------- the panel that opens ---------------- */
    fullRepresentation: Item {
        Layout.minimumWidth: Kirigami.Units.gridUnit * 20
        Layout.minimumHeight: Kirigami.Units.gridUnit * 17

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Kirigami.Units.largeSpacing
            spacing: Kirigami.Units.largeSpacing

            PlasmaExtras.Heading {
                level: 3
                text: Qt.formatDate(new Date(), "dddd, d MMMM")
            }

            GridLayout {
                Layout.fillWidth: true
                columns: 2
                rowSpacing: Kirigami.Units.smallSpacing
                columnSpacing: Kirigami.Units.smallSpacing

                Tile {
                    label: i18n("Wi‑Fi")
                    iconName: root.wifiOn ? "network-wireless-connected" : "network-wireless-disconnected"
                    active: root.wifiOn
                    enabled: root.wifiKnown
                    onToggled: {
                        exec.run("nmcli radio wifi " + (root.wifiOn ? "off" : "on"))
                        root.wifiOn = !root.wifiOn      // optimistic; the poll corrects it
                    }
                }
                Tile {
                    label: i18n("Bluetooth")
                    iconName: root.btOn ? "network-bluetooth" : "network-bluetooth-inactive"
                    active: root.btOn
                    enabled: root.btKnown
                    onToggled: {
                        exec.run("rfkill " + (root.btOn ? "block" : "unblock") + " bluetooth")
                        root.btOn = !root.btOn
                    }
                }
                Tile {
                    label: i18n("Night light")
                    iconName: "redshift-status-on"
                    active: root.nightOn
                    onToggled: {
                        exec.run("qdbus6 org.kde.KWin /org/kde/KWin/NightLight org.kde.KWin.NightLight.toggle")
                        root.nightOn = !root.nightOn
                    }
                }
                Tile {
                    label: i18n("Settings")
                    iconName: "preferences-system"
                    active: false
                    onToggled: { exec.run("systemsettings"); root.expanded = false }
                }
            }

            Item { Layout.fillHeight: true }

            Kirigami.Separator { Layout.fillWidth: true }

            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                QQC2.Label {
                    text: i18n("Notifications appear next to the clock")
                    font: Kirigami.Theme.smallFont
                    opacity: 0.6
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
                PlasmaComponents.ToolButton {
                    icon.name: "system-lock-screen"
                    onClicked: { exec.run("loginctl lock-session"); root.expanded = false }
                    QQC2.ToolTip.text: i18n("Lock")
                    QQC2.ToolTip.visible: hovered
                }
                PlasmaComponents.ToolButton {
                    icon.name: "system-shutdown"
                    onClicked: {
                        exec.run("qdbus6 org.kde.LogoutPrompt /LogoutPrompt promptAll")
                        root.expanded = false
                    }
                    QQC2.ToolTip.text: i18n("Power")
                    QQC2.ToolTip.visible: hovered
                }
            }
        }
    }

    /* A labelled switch. The design argued for words on every control: an
     * unlabelled glyph is only obvious to someone who already knows it. */
    component Tile: QQC2.AbstractButton {
        id: tile
        property string label
        property string iconName
        property bool active: false

        Layout.fillWidth: true
        Layout.preferredHeight: Kirigami.Units.gridUnit * 3.2
        opacity: enabled ? 1.0 : 0.45
        onClicked: tile.toggled()
        signal toggled()

        background: Rectangle {
            radius: Kirigami.Units.cornerRadius
            color: tile.active ? Kirigami.Theme.highlightColor : Kirigami.Theme.backgroundColor
            border.width: 1
            border.color: tile.active ? "transparent"
                                      : Qt.rgba(Kirigami.Theme.textColor.r,
                                                Kirigami.Theme.textColor.g,
                                                Kirigami.Theme.textColor.b, 0.15)
            Behavior on color { ColorAnimation { duration: 120 } }
        }

        contentItem: RowLayout {
            spacing: Kirigami.Units.smallSpacing
            Kirigami.Icon {
                source: tile.iconName
                Layout.leftMargin: Kirigami.Units.smallSpacing
                Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
                Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
                color: tile.active ? Kirigami.Theme.highlightedTextColor : Kirigami.Theme.textColor
                isMask: true
            }
            QQC2.Label {
                Layout.fillWidth: true
                text: tile.label
                elide: Text.ElideRight
                color: tile.active ? Kirigami.Theme.highlightedTextColor : Kirigami.Theme.textColor
            }
        }
    }
}
