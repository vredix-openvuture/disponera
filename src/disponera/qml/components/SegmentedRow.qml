import QtQuick

// A settings row offering a small set of mutually-exclusive choices, shown as a
// segmented pill control below the title. `options` is [{ v, l }] (v = value,
// l = label); the current `value` is highlighted; `picked(v)` fires on select.
Item {
    id: row
    property string title: ""
    property string desc: ""
    property var options: []
    property var value
    signal picked(var v)

    width: parent ? parent.width : 0
    implicitHeight: head.implicitHeight + seg.implicitHeight + 15 + 12 + 15

    Column {
        id: head
        anchors { left: parent.left; leftMargin: 18; right: parent.right; rightMargin: 18
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

    Flow {
        id: seg
        anchors { left: parent.left; leftMargin: 18; right: parent.right; rightMargin: 18
                  top: head.bottom; topMargin: 12 }
        spacing: 8
        Repeater {
            model: row.options
            delegate: Rectangle {
                id: pill
                required property var modelData
                readonly property bool on: row.value === modelData.v
                width: pillLbl.implicitWidth + 30; height: 34; radius: 9
                color: on ? Qt.alpha(Theme.accent, 0.32)
                     : pillHov.containsMouse ? Theme.bgSecondary : Theme.bgElement
                border.width: on ? 1.5 : 0; border.color: Theme.accent
                Behavior on color { ColorAnimation { duration: 100 } }
                Text {
                    id: pillLbl; anchors.centerIn: parent; text: pill.modelData.l
                    color: pill.on ? Theme.fgBright : Theme.fgPrimary
                    font.pixelSize: 14; font.bold: pill.on; font.family: Theme.fontFamily
                }
                MouseArea {
                    id: pillHov; anchors.fill: parent; hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: row.picked(pill.modelData.v)
                }
            }
        }
    }
}
