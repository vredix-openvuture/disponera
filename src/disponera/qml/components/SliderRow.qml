import QtQuick

// A settings row with a title/description and a horizontal slider beneath it.
// Works on an arbitrary [from, to] range with optional snapping (stepSize > 0);
// `value` is the real value, `moved(v)` fires with the new real value.
Item {
    id: row
    property string title: ""
    property string desc: ""
    property real from: 0
    property real to: 1
    property real stepSize: 0          // 0 ⇒ continuous
    property real value: 0
    // default label is a percentage of the range; override for e.g. hour labels
    property string valueText: Math.round(row.t * 100) + "%"
    signal moved(real v)

    readonly property real t: row.to > row.from
                              ? Math.max(0, Math.min(1, (row.value - row.from) / (row.to - row.from))) : 0

    function _emit(frac) {
        frac = Math.max(0, Math.min(1, frac))
        var v = row.from + frac * (row.to - row.from)
        if (row.stepSize > 0) v = row.from + Math.round((v - row.from) / row.stepSize) * row.stepSize
        row.moved(v)
    }

    width: parent ? parent.width : 0
    implicitHeight: head.implicitHeight + 62

    Column {
        id: head
        anchors { left: parent.left; leftMargin: 18; right: valLbl.left; rightMargin: 14
                  top: parent.top; topMargin: 15 }
        spacing: 3
        Text {
            width: parent.width; elide: Text.ElideRight
            text: row.title; color: Theme.fgBright
            font.pixelSize: 15; font.weight: Font.Medium; font.family: Theme.fontFamily
        }
        Text {
            visible: row.desc !== ""
            width: parent.width; wrapMode: Text.WordWrap; text: row.desc
            color: Theme.fgMuted; font.pixelSize: 13; font.family: Theme.fontFamily
        }
    }

    Rectangle {
        id: valLbl
        anchors { right: parent.right; rightMargin: 18; top: parent.top; topMargin: 13 }
        width: valTxt.implicitWidth + 18; height: 24; radius: 8
        color: Theme.bgElement
        Text {
            id: valTxt; anchors.centerIn: parent; text: row.valueText
            color: Theme.fgBright; font.pixelSize: 13; font.weight: Font.Medium; font.family: Theme.fontFamily
        }
    }

    Item {
        anchors { left: parent.left; leftMargin: 18; right: parent.right; rightMargin: 18
                  top: head.bottom; topMargin: 14 }
        height: 22
        Rectangle {
            id: track
            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
            height: 6; radius: 3; color: Theme.bgElement
            Rectangle {
                width: track.width * row.t; height: track.height; radius: track.radius
                color: Theme.accent
            }
            Rectangle {   // knob
                width: 18; height: 18; radius: 9
                x: track.width * row.t - width / 2
                anchors.verticalCenter: parent.verticalCenter
                color: Theme.fgBright; border.width: 2; border.color: Theme.accent
                scale: drag.pressed ? 1.15 : 1.0
                Behavior on scale { NumberAnimation { duration: 90 } }
            }
            MouseArea {
                id: drag
                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
                height: 26; cursorShape: Qt.PointingHandCursor
                onPressed: row._emit(mouseX / width)
                onPositionChanged: if (pressed) row._emit(mouseX / width)
            }
        }
    }
}
