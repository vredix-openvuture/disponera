import QtQuick

// Settings › Calendar: week/day time-grid behaviour.
Flickable {
    id: sec
    contentHeight: col.implicitHeight + 8
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    readonly property real minOpacity: 0.05
    readonly property real maxOpacity: 1.0

    function _setFrac(frac) {
        var t = Math.max(0, Math.min(1, frac))
        Settings.setPastEventOpacity(sec.minOpacity + t * (sec.maxOpacity - sec.minOpacity))
    }

    Column {
        id: col
        width: parent.width
        spacing: 22

        Text {
            text: "Past events"; color: Theme.fgBright
            font.pixelSize: 17; font.bold: true; font.family: Theme.fontFamily
        }
        Text {
            width: parent.width; wrapMode: Text.WordWrap
            text: "In the Week/Day grid, events that have already ended fade to this opacity. Events still to come always stay fully opaque."
            color: Theme.fgMuted; font.pixelSize: 13; font.family: Theme.fontFamily
        }

        Item {
            id: row
            width: parent.width; height: 36
            readonly property real t: (sec.maxOpacity > sec.minOpacity)
                ? Math.max(0, Math.min(1, (Settings.pastEventOpacity - sec.minOpacity) / (sec.maxOpacity - sec.minOpacity)))
                : 0

            Rectangle {
                id: track
                anchors { left: parent.left; right: valLbl.left; rightMargin: 14; verticalCenter: parent.verticalCenter }
                height: 8; radius: 4
                color: Theme.bgElement

                Rectangle {
                    width: parent.width * row.t; height: parent.height; radius: parent.radius
                    color: Theme.accent
                }
                Rectangle {   // knob
                    width: 18; height: 18; radius: 9
                    x: parent.width * row.t - width / 2
                    anchors.verticalCenter: parent.verticalCenter
                    color: Theme.fgBright
                    border.width: 2; border.color: Theme.accent
                }
                MouseArea {
                    anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
                    height: 24
                    cursorShape: Qt.PointingHandCursor
                    onPressed: sec._setFrac(mouseX / width)
                    onPositionChanged: if (pressed) sec._setFrac(mouseX / width)
                }
            }
            Text {
                id: valLbl
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                width: 46; horizontalAlignment: Text.AlignRight
                text: Math.round(Settings.pastEventOpacity * 100) + "%"
                color: Theme.fgBright; font.pixelSize: 13; font.family: Theme.fontFamily
            }
        }
    }
}
