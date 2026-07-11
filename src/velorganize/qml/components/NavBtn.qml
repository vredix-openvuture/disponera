import QtQuick

// Small icon button (port of the flyout's NavBtn).
Rectangle {
    id: nb
    property string sym: ""
    property bool   dim: false
    signal tap()
    width: 30; height: 30; radius: 8
    color: nbHov.containsMouse ? Theme.bgSecondary : Theme.bgElement
    opacity: dim ? 0.4 : 1.0
    Text { anchors.centerIn: parent; text: nb.sym; color: Theme.fgPrimary
           font.pixelSize: 15; font.family: Theme.fontFamily }
    MouseArea { id: nbHov; anchors.fill: parent; hoverEnabled: true; onClicked: nb.tap() }
}
