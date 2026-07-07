import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// velorganize skeleton — three panes over one data base: CalDAV events,
// CalDAV todos, local markdown notes. Everything below is placeholder UI;
// the bridges (CalDav, Notes) already speak the real backends.
ApplicationWindow {
    id: win
    visible: true
    width: 1100; height: 720
    title: "velorganize"
    color: "#161616"

    Component.onCompleted: CalDav.load()

    header: TabBar {
        id: tabs
        TabButton { text: "󰃭  Calendar" }
        TabButton { text: "  Todos" }
        TabButton { text: "󰠮  Notes" }
    }

    StackLayout {
        anchors.fill: parent
        currentIndex: tabs.currentIndex

        // ── Calendar (placeholder: dumps the cache state) ────────────────
        Item {
            Label {
                anchors.centerIn: parent
                width: parent.width * 0.8
                wrapMode: Text.WordWrap
                horizontalAlignment: Text.AlignHCenter
                color: "#c8c8c8"
                text: CalDav.cache.error
                      ? "CalDAV: " + CalDav.cache.error
                      : "Calendar pane — month view lands here.\n(cache loaded: "
                        + Object.keys(CalDav.cache || {}).length + " top-level keys)"
            }
        }

        // ── Todos ─────────────────────────────────────────────────────────
        Item {
            Label {
                anchors.centerIn: parent
                color: "#c8c8c8"
                text: "Todo pane — VTODO lists land here."
            }
        }

        // ── Notes ─────────────────────────────────────────────────────────
        RowLayout {
            spacing: 0
            ListView {
                Layout.preferredWidth: 260
                Layout.fillHeight: true
                model: Notes.notes
                delegate: ItemDelegate {
                    required property var modelData
                    width: ListView.view.width
                    text: modelData.name
                    onClicked: {
                        editor.noteName = modelData.name
                        editor.text = Notes.read(modelData.name)
                    }
                }
                header: Button {
                    width: ListView.view.width
                    text: "+ new note"
                    onClicked: {
                        var n = Notes.create()
                        editor.noteName = n
                        editor.text = Notes.read(n)
                    }
                }
            }
            TextArea {
                id: editor
                property string noteName: ""
                Layout.fillWidth: true
                Layout.fillHeight: true
                placeholderText: "pick or create a note…"
                font.family: "monospace"
                onEditingFinished: if (noteName !== "") Notes.save(noteName, text)
            }
        }
    }
}
