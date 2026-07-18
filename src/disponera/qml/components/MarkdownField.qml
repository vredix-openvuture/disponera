import QtQuick
import QtQuick.Controls
import Disponera

// A single editable block that renders Markdown LIVE as you type (Obsidian-style)
// — not a raw editor plus a separate preview. The text stays editable plain
// source; a MarkdownHighlighter paints heading/bold/italic/code/quote/list/link
// formats straight onto the document on every keystroke. Fixed height with
// internal scrolling so it never grows its card. `text` is the raw markdown.
Rectangle {
    id: mf
    property alias text: input.text
    property string placeholder: ""
    height: 150
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
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        function ensureVisible(r) {
            if (contentY >= r.y) contentY = r.y
            else if (contentY + height <= r.y + r.height) contentY = r.y + r.height - height
        }
        TextEdit {
            id: input
            width: fl.width
            textFormat: TextEdit.PlainText          // source stays literal; the
            wrapMode: TextEdit.Wrap                  // highlighter does the styling
            color: Theme.fgBright; font.pixelSize: 14; font.family: Theme.fontFamily
            selectByMouse: true
            persistentSelection: true
            onCursorRectangleChanged: fl.ensureVisible(cursorRectangle)
            onLinkActivated: l => Qt.openUrlExternally(l)

            // Reveal the raw markers only on the caret's line; collapse elsewhere.
            // Edits re-apply the wider line spacing (reflow).
            onCursorPositionChanged: mdhl.setCursor(activeFocus ? cursorPosition : -1)
            onTextChanged: mdhl.reflow()
            onActiveFocusChanged: mdhl.setCursor(activeFocus ? cursorPosition : -1)

            MarkdownHighlighter {
                id: mdhl
                document: input.textDocument
                baseColor: Theme.fgBright
                mutedColor: Theme.fgMuted
                accentColor: Theme.accent
                linkColor: Theme.boActive
            }
        }
    }
    Text {
        anchors { left: parent.left; leftMargin: 10; top: parent.top; topMargin: 10 }
        visible: input.text === "" && !input.activeFocus
        text: mf.placeholder
        color: Theme.fgMuted; font.pixelSize: 13; font.family: Theme.fontFamily
    }
}
