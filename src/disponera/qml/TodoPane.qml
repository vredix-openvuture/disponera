import QtQuick
import "components"

// Todo tab (M2 #181/#182/#185): a Vikunja-style project OVERVIEW is the landing
// view — root projects as cards (background image + rolled-up open count). Click
// a card to drill into that project: its subprojects show as a card strip and
// its tasks in the grouped board. Back walks up the tree (parent → … → overview).
Item {
    id: pane
    property string view: "overview"        // "overview" | "board"
    property string selProject: ""          // "" board = All tasks

    function projectById(id) {
        var ps = Todo.projects ?? []
        for (var i = 0; i < ps.length; i++) if (ps[i].id === id) return ps[i]
        return null
    }
    function open(id) { pane.selProject = id; pane.view = "board" }
    function goBack() {
        var p = pane.projectById(pane.selProject)
        if (p && p.parentId && p.parentId !== "") pane.open(p.parentId)
        else { pane.view = "overview"; pane.selProject = "" }
    }
    readonly property int openTotal: {
        var n = 0, ts = Todo.tasks ?? []
        for (var i = 0; i < ts.length; i++) if (!ts[i].done) n++
        return n
    }

    // ── Overview (root project cards) ────────────────────────────────────────
    Flickable {
        anchors.fill: parent
        visible: pane.view === "overview"
        contentHeight: ovCol.implicitHeight + 28
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: ovCol
            x: 16; y: 16; width: parent.width - 32
            spacing: 14

            Item {
                width: parent.width; height: 34
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Projects"
                    color: Theme.fgBright; font.pixelSize: 21; font.bold: true; font.family: Theme.fontFamily
                }
                Row {
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    spacing: 8
                    Rectangle {   // "New project" button
                        width: newLbl.implicitWidth + 30; height: 32; radius: 8
                        color: newHov.containsMouse ? Theme.bgHover : Theme.accent
                        Text {
                            id: newLbl
                            anchors.centerIn: parent
                            text: "󰐕  New project"
                            color: Theme.fgBright; font.pixelSize: 14; font.bold: true; font.family: Theme.fontFamily
                        }
                        MouseArea { anchors.fill: parent; hoverEnabled: true; id: newHov
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: projectDialog.openNew("") }
                    }
                    Rectangle {   // "All tasks" pill
                        width: allLbl.implicitWidth + 30; height: 32; radius: 8
                        color: allHov.containsMouse ? Theme.bgSecondary : Theme.bgElement
                        Behavior on color { ColorAnimation { duration: 90 } }
                        Text {
                            id: allLbl
                            anchors.centerIn: parent
                            text: "󰒺  All tasks" + (pane.openTotal > 0 ? "  " + pane.openTotal : "")
                            color: Theme.fgPrimary; font.pixelSize: 14; font.family: Theme.fontFamily
                        }
                        MouseArea { id: allHov; anchors.fill: parent; hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: pane.open("") }
                    }
                }
            }

            OverviewGrid {
                width: parent.width
                parentId: ""
                onPick: id => pane.open(id)
                onEdit: id => projectDialog.openEdit(id)
            }

            Text {
                visible: (Todo.projects ?? []).length === 0
                text: Todo.syncing ? "loading projects…" : "no projects"
                color: Theme.fgMuted; font.pixelSize: 14; font.family: Theme.fontFamily
            }
        }
    }

    // ── Board (one project, or all tasks) ────────────────────────────────────
    Item {
        anchors.fill: parent
        visible: pane.view === "board"

        Item {
            id: backBar
            anchors { top: parent.top; left: parent.left; right: parent.right; margins: 14 }
            height: 34
            Rectangle {
                id: backBtn
                anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                width: backLbl.implicitWidth + 26; height: 32; radius: 8
                color: backHov.containsMouse ? Theme.bgSecondary : Theme.bgElement
                Behavior on color { ColorAnimation { duration: 90 } }
                Text {
                    id: backLbl
                    anchors.centerIn: parent
                    readonly property var par: pane.projectById(pane.selProject)
                    text: "󰅁  " + (par && par.parentId && par.parentId !== ""
                                    ? (pane.projectById(par.parentId)?.title ?? "Overview")
                                    : "Overview")
                    color: Theme.fgPrimary; font.pixelSize: 14; font.family: Theme.fontFamily
                }
                MouseArea { id: backHov; anchors.fill: parent; hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: pane.goBack() }
            }
            readonly property var curProj: pane.projectById(pane.selProject)
            readonly property bool vkProj: (backBar.curProj?.source ?? "") === "vikunja"

            Text {
                anchors { left: backBtn.right; leftMargin: 14; right: projActions.left; rightMargin: 12
                          verticalCenter: parent.verticalCenter }
                elide: Text.ElideRight
                text: pane.selProject === "" ? "All tasks"
                                             : (backBar.curProj?.title ?? "")
                color: Theme.fgBright; font.pixelSize: 18; font.bold: true; font.family: Theme.fontFamily
            }
            Row {
                id: projActions
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                spacing: 8
                visible: backBar.vkProj
                Rectangle {
                    width: subLbl.implicitWidth + 26; height: 32; radius: 8
                    color: subHov.containsMouse ? Theme.bgSecondary : Theme.bgElement
                    Text { id: subLbl; anchors.centerIn: parent; text: "󰐕  Subproject"
                           color: Theme.fgPrimary; font.pixelSize: 13; font.family: Theme.fontFamily }
                    MouseArea { id: subHov; anchors.fill: parent; hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: projectDialog.openNew(pane.selProject) }
                }
                Rectangle {
                    width: edLbl.implicitWidth + 26; height: 32; radius: 8
                    color: edHov.containsMouse ? Theme.bgSecondary : Theme.bgElement
                    Text { id: edLbl; anchors.centerIn: parent; text: "󰏫  Edit"
                           color: Theme.fgPrimary; font.pixelSize: 13; font.family: Theme.fontFamily }
                    MouseArea { id: edHov; anchors.fill: parent; hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: projectDialog.openEdit(pane.selProject) }
                }
            }
        }

        OverviewGrid {
            id: subGrid
            anchors { top: backBar.bottom; left: parent.left; right: parent.right
                      topMargin: 12; leftMargin: 14; rightMargin: 14 }
            parentId: pane.selProject
            cardMinW: 220; cardH: 118
            visible: pane.selProject !== "" && cards.length > 0
            height: visible ? implicitHeight : 0
            onPick: id => pane.open(id)
            onEdit: id => projectDialog.openEdit(id)
        }

        TaskBoard {
            anchors { top: subGrid.visible ? subGrid.bottom : backBar.bottom
                      topMargin: subGrid.visible ? 14 : 8
                      left: parent.left; right: parent.right; bottom: parent.bottom; margins: 14 }
            filterProject: pane.selProject
            onOpenTask: task => taskDialog.openEdit(task)
        }
    }

    ProjectDialog { id: projectDialog; anchors.fill: parent }
    TaskDialog { id: taskDialog; anchors.fill: parent }
}
