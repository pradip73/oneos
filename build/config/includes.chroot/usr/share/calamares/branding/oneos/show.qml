/* Shown while OneOS copies itself onto the disk.
 *
 * Deliberately plain. This is the one moment a user is guaranteed to read the
 * screen, so it is spent setting accurate expectations rather than making
 * claims -- particularly about the Windows and Android layers, where a
 * surprise later costs far more trust than a caveat now. */

import QtQuick 2.5
import calamares.slideshow 1.0

Presentation {
    id: presentation

    Timer {
        interval: 8000
        running: true
        repeat: true
        onTriggered: presentation.goToNextSlide()
    }

    Slide {
        Text {
            anchors.centerIn: parent
            width: parent.width * 0.8
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            color: "#0F1E1B"
            font.pixelSize: 22
            text: qsTr("Welcome to OneOS\n\nA desktop that runs Linux, Windows and Android software on one machine.")
        }
    }

    Slide {
        Text {
            anchors.centerIn: parent
            width: parent.width * 0.8
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            color: "#0F1E1B"
            font.pixelSize: 20
            text: qsTr("Windows programs\n\nDouble-click an .exe and OneOS installs it, giving each program its own private workspace.\n\nSoftware needing anti-cheat or hardware drivers will not run.")
        }
    }

    Slide {
        Text {
            anchors.centerIn: parent
            width: parent.width * 0.8
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            color: "#0F1E1B"
            font.pixelSize: 20
            text: qsTr("Android apps\n\nDouble-click an .apk. The first one downloads about 700 MB of Android.\n\nApps that check for Google Play — banking and streaming — will not run.")
        }
    }

    function onActivate() {}
    function onLeave() {}
}
