import QtQuick

// A button that clearly REACTS: hover lightens, press darkens + dips in scale,
// both animated. `accent` = the primary (filled) style. Emits clicked().
Rectangle {
    id: btn
    property string text: ""
    property string icon: ""
    property bool accent: false
    property bool danger: false
    property bool active: true
    signal clicked()

    readonly property color _base: btn.danger ? Qt.rgba(Theme.fgUrgent.r, Theme.fgUrgent.g, Theme.fgUrgent.b, 0.16)
                                 : btn.accent ? Theme.accent : Theme.bgElement
    readonly property color _hover: btn.danger ? Qt.rgba(Theme.fgUrgent.r, Theme.fgUrgent.g, Theme.fgUrgent.b, 0.28)
                                  : btn.accent ? Theme.bgHover : Theme.bgSecondary
    implicitWidth: row.implicitWidth + 30
    implicitHeight: 36
    radius: 8
    color: !btn.active ? Theme.bgElement
         : ma.pressed ? Qt.darker(btn._hover, 1.22)
         : ma.containsMouse ? btn._hover : btn._base
    opacity: btn.active ? 1.0 : 0.5
    scale: (ma.pressed && btn.active) ? 0.955 : 1.0
    Behavior on color { ColorAnimation { duration: 110; easing.type: Easing.OutQuad } }
    Behavior on scale { NumberAnimation { duration: 90; easing.type: Easing.OutQuad } }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 7
        Text {
            visible: btn.icon !== ""
            anchors.verticalCenter: parent.verticalCenter
            text: btn.icon
            color: btn.danger ? Theme.fgUrgent : btn.accent ? Theme.fgBright : Theme.fgPrimary
            font.pixelSize: 14; font.family: Theme.fontFamily
        }
        Text {
            visible: btn.text !== ""
            anchors.verticalCenter: parent.verticalCenter
            text: btn.text
            color: btn.danger ? Theme.fgUrgent : btn.accent ? Theme.fgBright : Theme.fgPrimary
            font.pixelSize: 14; font.bold: btn.accent; font.family: Theme.fontFamily
        }
    }
    MouseArea {
        id: ma
        anchors.fill: parent; hoverEnabled: true
        cursorShape: btn.active ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: if (btn.active) btn.clicked()
    }
}
