import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// velorganize — focused working over the same data the shell's quick-view flyout
// shows: the unified todo model (Vikunja project tree + CalDAV lists), CalDAV
// events, and local markdown notes. Colors + font follow the live velumeron
// theme (ThemeBridge watches wallust's colors.json).
ApplicationWindow {
    id: win
    visible: true
    width: 1280; height: 800
    title: "velorganize"
    color: Theme.windowBg

    property int tab: 1   // land on Todos — the focused-working default

    Component.onCompleted: { Todo.load(); Todo.sync(); CalDav.load(); CalDav.sync() }

    // ── Header: tabs + sync state ────────────────────────────────────────────
    header: Rectangle {
        height: 46
        color: Theme.windowBg

        Row {
            id: tabRow
            anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
            spacing: 6
            Repeater {
                model: [{ icon: "󰃭", label: "Calendar" },
                        { icon: "",  label: "Todos" },
                        { icon: "󰠮", label: "Notes" }]
                delegate: Rectangle {
                    id: tabBtn
                    required property var modelData
                    required property int index
                    readonly property bool on: win.tab === index
                    width: tabLbl.implicitWidth + 28; height: 32; radius: 8
                    color: on ? Qt.alpha(Theme.accent, 0.35)
                         : tabHov.containsMouse ? Theme.bgSecondary : "transparent"
                    Behavior on color { ColorAnimation { duration: 90 } }
                    Text {
                        id: tabLbl
                        anchors.centerIn: parent
                        text: tabBtn.modelData.icon + "  " + tabBtn.modelData.label
                        color: tabBtn.on ? Theme.fgBright : Theme.fgPrimary
                        font.pixelSize: 15; font.family: Theme.fontFamily; font.bold: tabBtn.on
                    }
                    MouseArea { id: tabHov; anchors.fill: parent; hoverEnabled: true
                                onClicked: win.tab = tabBtn.index }
                }
            }
        }

        Row {
            anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
            spacing: 10
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: Todo.lastError !== "" ? "󰀦 " + Todo.lastError
                    : Todo.syncing || CalDav.syncing ? "syncing…"
                    : Todo.syncedAt > 0
                      ? "synced " + Qt.formatTime(new Date(Todo.syncedAt), "hh:mm") : ""
                color: Todo.lastError !== "" ? Theme.fgUrgent : Theme.fgMuted
                font.pixelSize: 12; font.family: Theme.fontFamily
            }
            Text {
                id: syncBtn
                anchors.verticalCenter: parent.verticalCenter
                text: "󰑐"; color: syncHov.containsMouse ? Theme.fgBright : Theme.fgMuted
                font.pixelSize: 17; font.family: Theme.fontFamily
                RotationAnimation on rotation {
                    running: Todo.syncing || CalDav.syncing; from: 0; to: 360
                    duration: 900; loops: Animation.Infinite
                    onRunningChanged: if (!running) syncBtn.rotation = 0
                }
                MouseArea { id: syncHov; anchors.fill: parent; anchors.margins: -6
                            hoverEnabled: true
                            onClicked: { Todo.sync(); CalDav.sync() } }
            }
        }

        Rectangle {   // hairline under the header
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            height: 1; color: Qt.alpha(Theme.boNormal, 0.5)
        }
    }

    StackLayout {
        anchors.fill: parent
        currentIndex: win.tab

        CalendarPane {}
        TodoPane {}

        // ── Notes (skeleton pane, themed) ────────────────────────────────────
        RowLayout {
            spacing: 0
            ListView {
                Layout.preferredWidth: 260
                Layout.fillHeight: true
                clip: true
                model: Notes.notes
                delegate: Rectangle {
                    id: noteRow
                    required property var modelData
                    width: ListView.view.width; height: 36
                    color: noteHov.containsMouse ? Theme.bgSecondary : "transparent"
                    Text {
                        anchors { left: parent.left; leftMargin: 14; right: parent.right; rightMargin: 8
                                  verticalCenter: parent.verticalCenter }
                        elide: Text.ElideRight
                        text: noteRow.modelData.name
                        color: Theme.fgPrimary; font.pixelSize: 15; font.family: Theme.fontFamily
                    }
                    MouseArea {
                        id: noteHov
                        anchors.fill: parent; hoverEnabled: true
                        onClicked: {
                            editor.noteName = noteRow.modelData.name
                            editor.text = Notes.read(noteRow.modelData.name)
                        }
                    }
                }
                header: Rectangle {
                    width: ListView.view.width; height: 40
                    color: "transparent"
                    Rectangle {
                        anchors { fill: parent; margins: 6 }
                        radius: 8
                        color: newHov.containsMouse ? Theme.bgSecondary : Theme.bgElement
                        Text { anchors.centerIn: parent; text: "󰐕  new note"
                               color: Theme.fgPrimary; font.pixelSize: 13; font.family: Theme.fontFamily }
                        MouseArea {
                            id: newHov
                            anchors.fill: parent; hoverEnabled: true
                            onClicked: {
                                var n = Notes.create()
                                editor.noteName = n
                                editor.text = Notes.read(n)
                            }
                        }
                    }
                }
            }
            Rectangle { Layout.preferredWidth: 1; Layout.fillHeight: true
                        color: Qt.alpha(Theme.boNormal, 0.5) }
            TextArea {
                id: editor
                property string noteName: ""
                Layout.fillWidth: true
                Layout.fillHeight: true
                placeholderText: "pick or create a note…"
                color: Theme.fgPrimary
                placeholderTextColor: Theme.fgMuted
                background: Rectangle { color: Theme.windowBg }
                font.family: Theme.fontFamily
                onEditingFinished: if (noteName !== "") Notes.save(noteName, text)
            }
        }
    }
}
