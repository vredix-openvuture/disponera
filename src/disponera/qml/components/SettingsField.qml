import QtQuick

// Themed single-line text input for the settings forms. `password` masks input.
Rectangle {
    id: sf
    property alias text: input.text
    property string placeholder: ""
    property bool password: false
    height: 38
    radius: 8
    color: Theme.bgPrimary
    border.width: input.activeFocus ? 1 : 0
    border.color: Theme.accent

    TextInput {
        id: input
        anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
        verticalAlignment: TextInput.AlignVCenter
        color: Theme.fgBright; font.pixelSize: 14; font.family: Theme.fontFamily
        clip: true
        selectByMouse: true
        echoMode: sf.password ? TextInput.Password : TextInput.Normal
    }
    Text {
        anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
        visible: input.text === "" && !input.activeFocus
        text: sf.placeholder
        color: Theme.fgMuted; font.pixelSize: 13; font.family: Theme.fontFamily
    }
}
