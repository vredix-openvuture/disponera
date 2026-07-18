import QtQuick

// Quick-add text field; Enter submits and clears (port of the flyout's InputRow).
Rectangle {
    id: ir
    property string placeholder: ""
    signal submit(string text)
    function focusInput() { irInput.forceActiveFocus() }
    function clear() { irInput.text = "" }
    height: 36
    radius: 8
    color:  Theme.bgElement
    border.width: irInput.activeFocus ? 1 : 0
    border.color: Theme.accent

    TextInput {
        id: irInput
        anchors { left: parent.left; leftMargin: 12; right: irGo.left; rightMargin: 8
                  verticalCenter: parent.verticalCenter }
        color: Theme.fgBright; font.pixelSize: 15; font.family: Theme.fontFamily
        clip: true
        selectByMouse: true
        onAccepted: { var t = text.trim(); if (t !== "") { ir.submit(t); text = "" } }
    }
    Text {
        anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
        visible: irInput.text === "" && !irInput.activeFocus
        text: ir.placeholder
        color: Theme.fgMuted; font.pixelSize: 13; font.family: Theme.fontFamily
    }
    Text {
        id: irGo
        anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
        text: "󰐕"; color: goHov.containsMouse ? Theme.fgBright : Theme.fgMuted
        font.pixelSize: 15; font.family: Theme.fontFamily
        MouseArea {
            id: goHov
            anchors.fill: parent; anchors.margins: -4; hoverEnabled: true
            onClicked: { var t = irInput.text.trim(); if (t !== "") { ir.submit(t); irInput.text = "" } }
        }
    }
}
