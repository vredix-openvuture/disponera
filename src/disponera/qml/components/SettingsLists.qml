import QtQuick

// Settings › Local lists (blueprint #7): calendars / todo lists stored locally,
// no CalDAV server. Create, rename, recolour, delete. Local todo lists show up
// as projects in the Todos tab; local calendars in the Calendar tab. Items are
// added from those tabs (the + / add dialog offers local lists as targets).
Flickable {
    id: sec
    contentHeight: col.implicitHeight + 8
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    property string newKind: "todo"
    property string newColor: ""

    function _count(l) {
        if (l.kind === "todo")
            return (Todo.tasks ?? []).filter(t => t.projectId === "loc:" + l.id && !t.done).length
        return (Local.events ?? []).filter(e => e.cal === "loc:" + l.id).length
    }

    Column {
        id: col
        width: parent.width
        spacing: 16

        SectionLabel { text: "LOCAL LISTS" }
        Text {
            width: parent.width; wrapMode: Text.WordWrap
            text: "Local lists live only on this machine — no server needed. Add items from the Todos and Calendar tabs (the + offers your local lists as targets)."
            color: Theme.fgMuted; font.pixelSize: 13; font.family: Theme.fontFamily
        }

        Text {
            visible: (Local.lists ?? []).length === 0
            text: "No local lists yet."
            color: Theme.fgMuted; font.pixelSize: 14; font.family: Theme.fontFamily
        }

        Repeater {
            model: Local.lists ?? []
            delegate: Rectangle {
                id: lrow
                required property var modelData
                width: parent.width; height: 60; radius: 12; color: Theme.bgPrimary
                border.width: 1; border.color: Qt.alpha(Theme.boNormal, 0.4)

                ColorField {
                    id: cfield
                    anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                    width: 132
                    color: lrow.modelData.color || ""
                    onPicked: c => Local.setListColor(lrow.modelData.id, c)
                }
                Rectangle {   // editable name
                    anchors { left: cfield.right; leftMargin: 12; right: kindBadge.left; rightMargin: 12
                              verticalCenter: parent.verticalCenter }
                    height: 34; radius: 8; color: Theme.bgPrimary
                    border.width: nameIn.activeFocus ? 1 : 0; border.color: Theme.accent
                    TextInput {
                        id: nameIn
                        anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
                        verticalAlignment: TextInput.AlignVCenter
                        text: lrow.modelData.name
                        color: Theme.fgBright; font.pixelSize: 14; font.family: Theme.fontFamily
                        clip: true; selectByMouse: true
                        onEditingFinished: if (text.trim() !== "") Local.renameList(lrow.modelData.id, text.trim())
                    }
                }
                Rectangle {
                    id: kindBadge
                    anchors { right: del.left; rightMargin: 10; verticalCenter: parent.verticalCenter }
                    width: kindLbl.implicitWidth + 20; height: 24; radius: 12; color: Theme.bgElement
                    Text { id: kindLbl; anchors.centerIn: parent
                           text: (lrow.modelData.kind === "todo" ? "󰄲 todo" : "󰃭 calendar")
                                 + "  ·  " + sec._count(lrow.modelData)
                           color: Theme.fgMuted; font.pixelSize: 11; font.family: Theme.fontFamily }
                }
                Rectangle {
                    id: del
                    anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                    width: 34; height: 34; radius: 8
                    color: delHov.containsMouse ? Qt.alpha(Theme.fgUrgent, 0.2) : "transparent"
                    Text { anchors.centerIn: parent; text: "󰩹"
                           color: delHov.containsMouse ? Theme.fgUrgent : Theme.fgMuted
                           font.pixelSize: 16; font.family: Theme.fontFamily }
                    MouseArea { id: delHov; anchors.fill: parent; hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Local.deleteList(lrow.modelData.id) }
                }
            }
        }

        // New local list
        Rectangle {
            width: parent.width; height: addCol.implicitHeight + 32; radius: 12; color: Theme.bgElement
            Column {
                id: addCol
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 16 }
                spacing: 12

                Text { text: "New local list"; color: Theme.fgPrimary
                       font.pixelSize: 14; font.bold: true; font.family: Theme.fontFamily }

                Row {
                    width: parent.width; spacing: 10
                    SettingsField { id: nName; width: parent.width - 260; placeholder: "list name" }
                    // kind toggle
                    Row {
                        spacing: 6
                        Repeater {
                            model: [{ v: "todo", l: "󰄲  Todo" }, { v: "calendar", l: "󰃭  Calendar" }]
                            delegate: Rectangle {
                                required property var modelData
                                readonly property bool on: sec.newKind === modelData.v
                                width: ktLbl.implicitWidth + 22; height: 38; radius: 8
                                color: on ? Qt.alpha(Theme.accent, 0.35)
                                     : ktHov.containsMouse ? Theme.bgSecondary : Theme.bgSecondary
                                Text { id: ktLbl; anchors.centerIn: parent; text: modelData.l
                                       color: on ? Theme.fgBright : Theme.fgPrimary
                                       font.pixelSize: 13; font.bold: on; font.family: Theme.fontFamily }
                                MouseArea { id: ktHov; anchors.fill: parent; hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor; onClicked: sec.newKind = modelData.v }
                            }
                        }
                    }
                    ColorField { width: 120; color: sec.newColor; onPicked: c => sec.newColor = c }
                }

                Rectangle {
                    width: createLbl.implicitWidth + 34; height: 36; radius: 8
                    readonly property bool ready: nName.text.trim() !== ""
                    color: !ready ? Theme.bgSecondary : createHov.containsMouse ? Theme.bgHover : Theme.accent
                    opacity: ready ? 1.0 : 0.5
                    Text { id: createLbl; anchors.centerIn: parent; text: "󰐕  Create list"
                           color: Theme.fgBright; font.pixelSize: 14; font.family: Theme.fontFamily }
                    MouseArea { id: createHov; anchors.fill: parent; hoverEnabled: true
                        cursorShape: parent.ready ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: {
                            if (!parent.ready) return
                            Local.addList(nName.text.trim(), sec.newKind, sec.newColor)
                            nName.text = ""; sec.newColor = ""
                        } }
                }
            }
        }
    }
}
