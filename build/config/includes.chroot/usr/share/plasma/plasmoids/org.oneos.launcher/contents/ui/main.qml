/*
 * OneOS launcher — the start menu from the design, as a real Plasma applet.
 *
 * WHY A PLASMOID AND NOT THE PHASE 2 COMPOSITOR
 * The designed shell needs a compositor to be truly ours, and that is eight to
 * twelve months away. But the *design* can reach the OS now: a Plasma applet is
 * QML, and QML is the language the Phase 3 shell is written in. So none of this
 * is throwaway — when the compositor exists, this file moves across rather than
 * being rewritten.
 *
 * DESIGN DECISIONS CARRIED OVER FROM THE PROTOTYPE
 *  - One button, bottom left, labelled. Not an icon a new user has to decode.
 *  - Every app shows its name. Icon-only grids assume you already know them.
 *  - Search first, because a launcher with a search field is a launcher you
 *    never have to organise.
 *  - The user and the power button share the footer, so "log out" is never
 *    somewhere else.
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
import org.kde.coreaddons as KCoreAddons

PlasmoidItem {
    id: root

    preferredRepresentation: compactRepresentation
    Plasmoid.status: PlasmaCore.Types.ActiveStatus

    /* Runs a command. Plasma 6 exposes no direct "launch this" call to applets,
     * so the executable data engine is the supported route. connectedSources is
     * cleared on each result, otherwise the engine re-runs commands on reload. */
    P5Support.DataSource {
        id: runner
        engine: "executable"
        connectedSources: []
        onNewData: function (source) { disconnectSource(source) }
        function exec(cmd) {
            if (cmd) { connectSource(cmd) }
        }
    }

    /* The favourites row. Deliberately a short, fixed list rather than every
     * installed application: a new user opening this for the first time should
     * see a page they can read, not a wall they have to scan. Everything else
     * is one keystroke away in the search field. */
    readonly property var favourites: [
        { name: "Web",            icon: "firefox",                  exec: "firefox-esr" },
        { name: "Files",          icon: "system-file-manager",      exec: "dolphin" },
        { name: "Media player",   icon: "vlc",                      exec: "vlc" },
        { name: "Text editor",    icon: "accessories-text-editor",  exec: "kate" },
        { name: "Terminal",       icon: "utilities-terminal",       exec: "konsole" },
        { name: "Windows apps",   icon: "wine",                     exec: "oneos-windows-settings" },
        { name: "Android apps",   icon: "phone",                    exec: "oneos-android-settings" },
        { name: "Control Panel",  icon: "preferences-system",       exec: "plasmawindowed org.oneos.controlpanel" },
        { name: "System info",    icon: "computer",                 exec: "plasmawindowed org.oneos.thiscomputer" },
        { name: "Software",       icon: "plasmadiscover",           exec: "plasma-discover" }
    ]

    /* ---------------- the button on the panel ---------------- */
    compactRepresentation: MouseArea {
        id: button
        Layout.minimumWidth: row.implicitWidth + Kirigami.Units.largeSpacing * 2
        Layout.preferredWidth: Layout.minimumWidth
        hoverEnabled: true
        onClicked: root.expanded = !root.expanded

        Rectangle {
            anchors.fill: parent
            anchors.margins: Kirigami.Units.smallSpacing
            radius: Kirigami.Units.cornerRadius
            color: Kirigami.Theme.highlightColor
            opacity: button.containsMouse ? 1.0 : 0.9
            Behavior on opacity { NumberAnimation { duration: 120 } }
        }

        RowLayout {
            id: row
            anchors.centerIn: parent
            spacing: Kirigami.Units.smallSpacing

            Rectangle {
                Layout.preferredWidth: Kirigami.Units.iconSizes.small
                Layout.preferredHeight: Kirigami.Units.iconSizes.small
                radius: 3
                color: Kirigami.Theme.highlightedTextColor
                QQC2.Label {
                    anchors.centerIn: parent
                    text: "1"
                    font.bold: true
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                    color: Kirigami.Theme.highlightColor
                }
            }
            QQC2.Label {
                text: i18n("Start")
                font.bold: true
                color: Kirigami.Theme.highlightedTextColor
                /* Hidden on a narrow vertical panel, where there is no room for
                 * a word and the mark alone still reads. */
                visible: plasmoid.formFactor !== PlasmaCore.Types.Vertical
            }
        }
    }

    /* ---------------- the panel that opens ---------------- */
    fullRepresentation: FocusScope {
        id: menu
        Layout.minimumWidth: Kirigami.Units.gridUnit * 26
        Layout.minimumHeight: Kirigami.Units.gridUnit * 28
        focus: true

        Component.onCompleted: search.forceActiveFocus()

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Kirigami.Units.largeSpacing
            spacing: Kirigami.Units.largeSpacing

            PlasmaExtras.SearchField {
                id: search
                Layout.fillWidth: true
                placeholderText: i18n("Search apps, files and settings")
                /* Hands the query to KRunner rather than reimplementing search.
                 * KRunner already indexes applications, files, settings, and
                 * does arithmetic and unit conversion; competing with it would
                 * be a worse launcher and a month of work. */
                onAccepted: {
                    if (text.length > 0) {
                        runner.exec("krunner --replace \"" + text.replace(/"/g, "") + "\"")
                        root.expanded = false
                        text = ""
                    }
                }
                Keys.onEscapePressed: root.expanded = false
            }

            PlasmaExtras.Heading {
                level: 5
                text: i18n("EVERYDAY")
                opacity: 0.6
            }

            GridView {
                id: grid
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                cellWidth: Math.floor(width / 5)
                cellHeight: cellWidth
                model: root.favourites
                keyNavigationEnabled: true

                delegate: MouseArea {
                    width: grid.cellWidth
                    height: grid.cellHeight
                    hoverEnabled: true
                    onClicked: {
                        runner.exec(modelData.exec)
                        root.expanded = false
                    }

                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: Kirigami.Units.smallSpacing / 2
                        radius: Kirigami.Units.cornerRadius
                        color: Kirigami.Theme.highlightColor
                        opacity: parent.containsMouse ? 0.18 : 0
                        Behavior on opacity { NumberAnimation { duration: 100 } }
                    }

                    ColumnLayout {
                        anchors.centerIn: parent
                        width: parent.width - Kirigami.Units.smallSpacing * 2
                        spacing: Kirigami.Units.smallSpacing

                        Kirigami.Icon {
                            source: modelData.icon
                            Layout.alignment: Qt.AlignHCenter
                            Layout.preferredWidth: Kirigami.Units.iconSizes.large
                            Layout.preferredHeight: Kirigami.Units.iconSizes.large
                        }
                        QQC2.Label {
                            text: modelData.name
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.WordWrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                            font.pointSize: Kirigami.Theme.smallFont.pointSize
                        }
                    }
                }
            }

            Kirigami.Separator { Layout.fillWidth: true }

            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                Kirigami.Icon {
                    source: "user-identity"
                    Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
                    Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
                }
                QQC2.Label { text: kuser.fullName || kuser.loginName }

                Item { Layout.fillWidth: true }

                PlasmaComponents.ToolButton {
                    icon.name: "system-lock-screen"
                    text: i18n("Lock")
                    display: QQC2.AbstractButton.IconOnly
                    QQC2.ToolTip.text: text
                    QQC2.ToolTip.visible: hovered
                    onClicked: { runner.exec("loginctl lock-session"); root.expanded = false }
                }
                PlasmaComponents.ToolButton {
                    icon.name: "system-shutdown"
                    text: i18n("Power")
                    onClicked: {
                        /* ksmserver's own dialog, so shutdown goes through the
                         * session manager and unsaved work still gets a prompt. */
                        runner.exec("qdbus org.kde.LogoutPrompt /LogoutPrompt promptAll")
                        root.expanded = false
                    }
                }
            }
        }
    }

    /* The real account, so the footer greets the person rather than showing
     * a placeholder. KUser gives the full name when one is set and falls back
     * to the login name when it is not. */
    KCoreAddons.KUser { id: kuser }
}
