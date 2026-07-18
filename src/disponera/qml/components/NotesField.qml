import QtQuick

// Multi-line themed text area for descriptions/notes. Fixed height with internal
// scrolling so it never grows the surrounding card.
Rectangle {
    id: nf
    property alias text: input.text
    property string placeholder: ""
    height: 92
    radius: 8
    color: Theme.bgPrimary
    border.width: input.activeFocus ? 1 : 0
    border.color: Theme.accent

    Flickable {
        id: fl
        anchors.fill: parent; anchors.margins: 10
        clip: true
        contentWidth: width; contentHeight: input.implicitHeight
        boundsBehavior: Flickable.StopAtBounds
        function ensureVisible(r) {
            if (contentY >= r.y) contentY = r.y
            else if (contentY + height <= r.y + r.height) contentY = r.y + r.height - height
        }
        TextEdit {
            id: input
            width: fl.width
            wrapMode: TextEdit.Wrap
            color: Theme.fgBright; font.pixelSize: 14; font.family: Theme.fontFamily
            selectByMouse: true
            onCursorRectangleChanged: fl.ensureVisible(cursorRectangle)
        }
    }
    Text {
        anchors { left: parent.left; leftMargin: 10; top: parent.top; topMargin: 10 }
        visible: input.text === "" && !input.activeFocus
        text: nf.placeholder
        color: Theme.fgMuted; font.pixelSize: 13; font.family: Theme.fontFamily
    }
}
