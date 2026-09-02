/*
 * OneOS "This computer" — the page from the design, as a real window.
 *
 * Left half is the disk, right half is the machine. That split is the whole
 * layout decision: the two questions people open this page to answer are "how
 * much room is left" and "what is in this thing", and mixing them produces the
 * list of unrelated facts that Windows' System Properties has become.
 *
 * WHAT IS DELIBERATELY NOT HERE
 * The design had the ring broken down by category -- photos, apps, documents.
 * That needs a disk-usage scanner with caching, which does not exist yet, and
 * the design review said so at the time: ship the version that is always right,
 * leave the space, add the breakdown when the scanner lands. A page that
 * reports categories wrongly is worse than one that never promised them.
 *
 * Run with `plasmawindowed org.oneos.thiscomputer`.
 */

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.plasma.plasmoid
import org.kde.plasma.extras as PlasmaExtras
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasma5support as P5Support

PlasmoidItem {
    id: root

    preferredRepresentation: fullRepresentation
    Layout.minimumWidth: Kirigami.Units.gridUnit * 38
    Layout.minimumHeight: Kirigami.Units.gridUnit * 24

    property string hostName: ""
    property string osName: "OneOS"
    property string cpuName: ""
    property string gpuName: ""
    property int    memTotalKb: 0
    property int    memAvailKb: 0
    property string winState: "checking…"
    property string androidState: "checking…"
    property var    drives: []

    readonly property real memUsedFrac:
        memTotalKb > 0 ? (memTotalKb - memAvailKb) / memTotalKb : 0

    function human(bytes) {
        if (bytes >= 1099511627776) return (bytes / 1099511627776).toFixed(1) + " TB"
        if (bytes >= 1073741824)    return Math.round(bytes / 1073741824) + " GB"
        if (bytes >= 1048576)       return Math.round(bytes / 1048576) + " MB"
        return Math.round(bytes / 1024) + " KB"
    }

    P5Support.DataSource {
        id: exec
        engine: "executable"
        connectedSources: []

        onNewData: function (source, data) {
            var out = (data["stdout"] || "").trim()

            if (source.indexOf("hostname") === 0) {
                root.hostName = out
            } else if (source.indexOf("oneos-probe-cpu") !== -1) {
                root.cpuName = out
            } else if (source.indexOf("oneos-probe-gpu") !== -1) {
                root.gpuName = out || "Unknown graphics"
            } else if (source.indexOf("oneos-probe-mem") !== -1) {
                var m = out.split(/\s+/)
                root.memTotalKb = parseInt(m[0]) || 0
                root.memAvailKb = parseInt(m[1]) || 0
            } else if (source.indexOf("oneos-probe-os") !== -1) {
                root.osName = out || "OneOS"
            } else if (source.indexOf("oneos-probe-compat") !== -1) {
                var c = out.split("|")
                root.winState = c[0] || "Unknown"
                root.androidState = c[1] || "Unknown"
            } else if (source.indexOf("oneos-probe-df") !== -1) {
                /* One line per mounted filesystem: target, size, used, avail.
                 * Parsed here rather than in the shell so the units stay
                 * numbers all the way to the bar widths. */
                var list = []
                out.split("\n").forEach(function (line) {
                    var f = line.trim().split(/\s+/)
                    if (f.length < 4) return
                    var size = parseFloat(f[1]), used = parseFloat(f[2]), avail = parseFloat(f[3])
                    if (!(size > 0)) return
                    list.push({
                        mount: f[0],
                        label: f[0] === "/" ? i18n("Main drive") : f[0].split("/").pop(),
                        size: size, used: used, avail: avail,
                        frac: used / size,
                        removable: f[0].indexOf("/media") === 0 || f[0].indexOf("/run/media") === 0
                    })
                })
                root.drives = list
            }
            disconnectSource(source)
        }
        function run(cmd) { if (cmd) connectSource(cmd) }
    }

    function refresh() {
        exec.run("hostname")
        exec.run("sh -c '# oneos-probe-cpu\nsed -n \"s/^model name[[:space:]]*: //p\" /proc/cpuinfo | head -n1'")
        exec.run("sh -c '# oneos-probe-gpu\nlspci 2>/dev/null | sed -n \"s/.*VGA compatible controller: //p\" | head -n1'")
        exec.run("sh -c '# oneos-probe-mem\nawk \"/MemTotal/{t=\\$2}/MemAvailable/{a=\\$2}END{print t, a}\" /proc/meminfo'")
        exec.run("sh -c '# oneos-probe-os\n. /etc/os-release; echo \"$PRETTY_NAME\"'")
        exec.run("sh -c '# oneos-probe-df\ndf -B1 --output=target,size,used,avail -x tmpfs -x devtmpfs -x squashfs -x overlay 2>/dev/null | tail -n +2'")
        exec.run("sh -c '# oneos-probe-compat\nif command -v wine >/dev/null; then if command -v bwrap >/dev/null; then w=\"Working, in a sandbox\"; else w=\"Working, NOT sandboxed\"; fi; else w=\"Not installed\"; fi; if command -v waydroid >/dev/null; then if [ -f /var/lib/waydroid/waydroid.cfg ]; then a=\"Ready\"; else a=\"Needs one-time setup\"; fi; else a=\"Not installed\"; fi; echo \"$w|$a\"'")
    }

    Component.onCompleted: refresh()
    Timer { interval: 10000; running: true; repeat: true; onTriggered: root.refresh() }

    fullRepresentation: Item {
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Kirigami.Units.largeSpacing
            spacing: Kirigami.Units.largeSpacing

            /* ---- who this machine is ---- */
            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.largeSpacing
                Kirigami.Icon {
                    source: "computer"
                    Layout.preferredWidth: Kirigami.Units.iconSizes.huge
                    Layout.preferredHeight: Kirigami.Units.iconSizes.huge
                }
                ColumnLayout {
                    spacing: 0
                    PlasmaExtras.Heading { level: 2; text: root.hostName }
                    QQC2.Label { text: root.osName; opacity: 0.7 }
                }
                Item { Layout.fillWidth: true }
                QQC2.Button {
                    text: i18n("Open drives")
                    icon.name: "drive-harddisk"
                    onClicked: exec.run("xdg-open computer:///")
                }
            }

            Kirigami.Separator { Layout.fillWidth: true }

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: Kirigami.Units.gridUnit

                /* ================= LEFT: the disk ================= */
                ColumnLayout {
                    Layout.preferredWidth: parent.width * 0.5
                    spacing: Kirigami.Units.smallSpacing

                    PlasmaExtras.Heading { level: 5; text: i18n("STORAGE"); opacity: 0.6 }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.largeSpacing

                        /* The ring. Used against free -- no category breakdown,
                         * because there is no scanner to compute one honestly. */
                        Item {
                            Layout.preferredWidth: Kirigami.Units.gridUnit * 8
                            Layout.preferredHeight: Kirigami.Units.gridUnit * 8

                            property var main: root.drives.length > 0
                                ? (root.drives.filter(function (d) { return d.mount === "/" })[0] || root.drives[0])
                                : null

                            Canvas {
                                id: ring
                                anchors.fill: parent
                                property real frac: parent.main ? parent.main.frac : 0
                                onFracChanged: requestPaint()
                                onPaint: {
                                    var ctx = getContext("2d")
                                    ctx.reset()
                                    var cx = width / 2, cy = height / 2
                                    var r = Math.min(width, height) / 2 - 10
                                    var lw = Math.max(10, r * 0.28)

                                    ctx.lineWidth = lw
                                    ctx.lineCap = "butt"

                                    ctx.strokeStyle = Qt.rgba(Kirigami.Theme.textColor.r,
                                                              Kirigami.Theme.textColor.g,
                                                              Kirigami.Theme.textColor.b, 0.12)
                                    ctx.beginPath(); ctx.arc(cx, cy, r, 0, Math.PI * 2); ctx.stroke()

                                    if (frac > 0) {
                                        /* Amber past 90%: the number is easy to
                                         * ignore, the colour is not. */
                                        ctx.strokeStyle = frac > 0.9 ? "#C9622C"
                                                                     : Kirigami.Theme.highlightColor
                                        ctx.beginPath()
                                        ctx.arc(cx, cy, r, -Math.PI / 2,
                                                -Math.PI / 2 + Math.PI * 2 * frac)
                                        ctx.stroke()
                                    }
                                }
                            }

                            ColumnLayout {
                                anchors.centerIn: parent
                                spacing: 0
                                QQC2.Label {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: parent.parent.main ? root.human(parent.parent.main.avail) : "—"
                                    font.bold: true
                                    font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.4
                                }
                                QQC2.Label {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: i18n("free")
                                    font: Kirigami.Theme.smallFont
                                    opacity: 0.7
                                }
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: Kirigami.Units.smallSpacing

                            Repeater {
                                model: root.drives
                                delegate: ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2
                                    RowLayout {
                                        Layout.fillWidth: true
                                        QQC2.Label {
                                            text: modelData.label
                                            font.bold: true
                                            elide: Text.ElideRight
                                            Layout.fillWidth: true
                                        }
                                        QQC2.Label {
                                            text: i18n("%1 free of %2",
                                                       root.human(modelData.avail),
                                                       root.human(modelData.size))
                                            font: Kirigami.Theme.smallFont
                                            opacity: 0.7
                                        }
                                    }
                                    Rectangle {
                                        Layout.fillWidth: true
                                        height: Kirigami.Units.smallSpacing
                                        radius: height / 2
                                        color: Qt.rgba(Kirigami.Theme.textColor.r,
                                                       Kirigami.Theme.textColor.g,
                                                       Kirigami.Theme.textColor.b, 0.12)
                                        Rectangle {
                                            width: parent.width * Math.min(1, modelData.frac)
                                            height: parent.height
                                            radius: parent.radius
                                            color: modelData.frac > 0.9 ? "#C9622C"
                                                                        : Kirigami.Theme.highlightColor
                                        }
                                    }
                                }
                            }

                            QQC2.Label {
                                visible: root.drives.length === 0
                                text: i18n("Reading drives…")
                                opacity: 0.6
                            }
                        }
                    }

                    Item { Layout.fillHeight: true }
                }

                Kirigami.Separator { Layout.fillHeight: true }

                /* ================= RIGHT: the machine ================= */
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing

                    PlasmaExtras.Heading { level: 5; text: i18n("RIGHT NOW"); opacity: 0.6 }

                    RowLayout {
                        Layout.fillWidth: true
                        QQC2.Label { text: i18n("Memory"); font.bold: true; Layout.fillWidth: true }
                        QQC2.Label {
                            text: root.memTotalKb > 0
                                ? i18n("%1 of %2 in use",
                                       root.human((root.memTotalKb - root.memAvailKb) * 1024),
                                       root.human(root.memTotalKb * 1024))
                                : "—"
                            font: Kirigami.Theme.smallFont
                            opacity: 0.7
                        }
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        height: Kirigami.Units.smallSpacing
                        radius: height / 2
                        color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g,
                                       Kirigami.Theme.textColor.b, 0.12)
                        Rectangle {
                            width: parent.width * root.memUsedFrac
                            height: parent.height
                            radius: parent.radius
                            color: Kirigami.Theme.highlightColor
                        }
                    }

                    Item { height: Kirigami.Units.largeSpacing }

                    PlasmaExtras.Heading { level: 5; text: i18n("ABOUT THIS COMPUTER"); opacity: 0.6 }

                    Fact { k: i18n("Processor");   v: root.cpuName || "—" }
                    Fact { k: i18n("Graphics");    v: root.gpuName || "—" }
                    Fact { k: i18n("Memory");      v: root.memTotalKb > 0 ? root.human(root.memTotalKb * 1024) : "—" }
                    Fact { k: i18n("System type"); v: "64-bit" }

                    Item { height: Kirigami.Units.largeSpacing }

                    /* The two lines nothing else in the system reports, and the
                     * reason someone chose this OS. "Supported" on a website is
                     * worth nothing if the layer failed to install here. */
                    Fact { k: i18n("Windows programs"); v: root.winState;     strong: true }
                    Fact { k: i18n("Android apps");     v: root.androidState; strong: true }

                    Item { Layout.fillHeight: true }
                }
            }
        }
    }

    component Fact: RowLayout {
        property string k
        property string v
        property bool strong: false
        Layout.fillWidth: true
        QQC2.Label { text: k; opacity: 0.7 }
        Item { Layout.fillWidth: true }
        QQC2.Label {
            text: v
            font.bold: true
            color: strong && v.indexOf("NOT") !== -1 ? "#C9622C" : Kirigami.Theme.textColor
            elide: Text.ElideRight
            Layout.maximumWidth: Kirigami.Units.gridUnit * 14
            horizontalAlignment: Text.AlignRight
        }
    }
}
