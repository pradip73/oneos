/*
 * OneOS taskbar — open windows, shown by name.
 *
 * Plasma's default is an icons-only task manager. That is fine once you know
 * your applications by their icon, and hostile before then: three documents
 * open in the same program become three identical squares, and the only way to
 * find the right one is to click them all.
 *
 * So this shows the window title, like Windows does, and marks the active
 * window with an accent underline rather than a subtle background tint that
 * nobody notices.
 *
 * Grouping is off. Grouping saves panel space by hiding windows behind a
 * hover-then-choose interaction — it trades the thing a taskbar is for
 * (seeing what is open) for space that a 1366-wide panel usually has anyway.
 */

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.kirigami as Kirigami
import org.kde.taskmanager as TaskManager

PlasmoidItem {
    id: root

    preferredRepresentation: fullRepresentation
    Plasmoid.status: PlasmaCore.Types.PassiveStatus

    TaskManager.VirtualDesktopInfo { id: virtualDesktopInfo }
    TaskManager.ActivityInfo { id: activityInfo }

    TaskManager.TasksModel {
        id: tasksModel
        virtualDesktop: virtualDesktopInfo.currentDesktop
        activity: activityInfo.currentActivity
        screenGeometry: root.screenGeometry

        filterByVirtualDesktop: true
        filterByActivity: true
        filterByScreen: true

        /* One entry per window. See the note at the top of this file. */
        groupMode: TaskManager.TasksModel.GroupDisabled
        sortMode: TaskManager.TasksModel.SortManual
    }

    fullRepresentation: Item {
        id: bar
        Layout.fillWidth: true
        Layout.minimumWidth: Kirigami.Units.gridUnit * 4

        readonly property int maxButton: Kirigami.Units.gridUnit * 11
        readonly property int minButton: Kirigami.Units.gridUnit * 3

        ListView {
            id: list
            anchors.fill: parent
            orientation: ListView.Horizontal
            spacing: Kirigami.Units.smallSpacing / 2
            model: tasksModel
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            /* Buttons share the space evenly and shrink as more windows open,
             * down to a floor where the icon still reads. Past that the list
             * scrolls rather than shrinking into illegibility. */
            readonly property int perItem: count > 0
                ? Math.max(bar.minButton, Math.min(bar.maxButton, Math.floor(width / count)))
                : bar.maxButton

            delegate: MouseArea {
                id: task
                width: list.perItem
                height: list.height
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.MiddleButton

                onClicked: function (mouse) {
                    var idx = tasksModel.makeModelIndex(index)
                    if (mouse.button === Qt.MiddleButton) {
                        /* Middle-click closes, as it does on most taskbars. */
                        tasksModel.requestClose(idx)
                    } else if (model.IsActive === true) {
                        /* Clicking the window you are already in minimises it,
                         * which is what the same click does on Windows. */
                        tasksModel.requestToggleMinimized(idx)
                    } else {
                        tasksModel.requestActivate(idx)
                    }
                }

                QQC2.ToolTip.text: model.display || ""
                QQC2.ToolTip.visible: task.containsMouse && label.truncated
                QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay

                Rectangle {
                    anchors.fill: parent
                    anchors.margins: Kirigami.Units.smallSpacing / 2
                    radius: Kirigami.Units.cornerRadius
                    color: Kirigami.Theme.highlightColor
                    opacity: model.IsActive === true ? 0.16
                           : task.containsMouse     ? 0.10
                           : 0
                    Behavior on opacity { NumberAnimation { duration: 100 } }
                }

                /* The active marker. A line under the button, not a tint --
                 * a tint at 16% opacity is invisible on half the wallpapers
                 * people choose. */
                Rectangle {
                    anchors.bottom: parent.bottom
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: parent.width - Kirigami.Units.largeSpacing
                    height: Math.max(2, Kirigami.Units.smallSpacing / 2)
                    radius: height
                    color: Kirigami.Theme.highlightColor
                    visible: model.IsActive === true
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Kirigami.Units.smallSpacing
                    anchors.rightMargin: Kirigami.Units.smallSpacing
                    spacing: Kirigami.Units.smallSpacing

                    Kirigami.Icon {
                        source: model.decoration
                        Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
                        Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
                        Layout.alignment: Qt.AlignVCenter
                        /* Minimised windows are dimmed, so "open but not on
                         * screen" is distinguishable at a glance. */
                        opacity: model.IsMinimized === true ? 0.55 : 1.0
                    }

                    QQC2.Label {
                        id: label
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        text: model.display || ""
                        elide: Text.ElideRight
                        maximumLineCount: 1
                        opacity: model.IsMinimized === true ? 0.7 : 1.0
                        /* Hidden once buttons are too narrow for a word, and on
                         * a vertical panel, where the taskbar becomes icons by
                         * necessity rather than by preference. */
                        visible: list.perItem > Kirigami.Units.gridUnit * 5
                                 && plasmoid.formFactor !== PlasmaCore.Types.Vertical
                    }
                }
            }
        }

        /* Nothing open: say so quietly rather than leaving a blank stretch of
         * panel that looks like something failed to load. */
        QQC2.Label {
            anchors.centerIn: parent
            text: i18n("No open windows")
            opacity: 0.45
            font: Kirigami.Theme.smallFont
            visible: tasksModel.count === 0
                     && plasmoid.formFactor !== PlasmaCore.Types.Vertical
        }
    }
}
