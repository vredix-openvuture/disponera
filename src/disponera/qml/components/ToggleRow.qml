import QtQuick

// A settings row with a title/description on the left and an on/off switch on
// the right. The whole row is clickable, not just the switch.
Item {
    id: row
    property string title: ""
    property string desc: ""
    property bool checked: false
    signal toggled()

    width: parent ? parent.width : 0
    implicitHeight: Math.max(txt.implicitHeight + 28, 60)

    Rectangle {   // subtle hover wash across the whole row
        anchors.fill: parent
        color: hov.containsMouse ? Qt.alpha(Theme.accent, 0.06) : "transparent"
        Behavior on color { ColorAnimation { duration: 100 } }
    }

    Column {
        id: txt
        anchors { left: parent.left; leftMargin: 18; right: sw.left; rightMargin: 16
                  verticalCenter: parent.verticalCenter }
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
        id: sw
        anchors { right: parent.right; rightMargin: 18; verticalCenter: parent.verticalCenter }
        width: 46; height: 26; radius: 13
        color: row.checked ? Theme.accent : Theme.bgElement
        border.width: row.checked ? 0 : 1; border.color: Qt.alpha(Theme.boNormal, 0.5)
        Behavior on color { ColorAnimation { duration: 130 } }
        Rectangle {
            width: 20; height: 20; radius: 10
            color: row.checked ? Theme.fgBright : Theme.fgMuted
            anchors.verticalCenter: parent.verticalCenter
            x: row.checked ? parent.width - width - 3 : 3
            Behavior on x { NumberAnimation { duration: 130; easing.type: Easing.OutCubic } }
            Behavior on color { ColorAnimation { duration: 130 } }
        }
    }

    MouseArea {
        id: hov
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: row.toggled()
    }
}
