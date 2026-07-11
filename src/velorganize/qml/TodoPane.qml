import QtQuick
import "components"

// Todo tab — project tree | grouped task board, the focused-working counterpart
// of the shell's quick-view flyout (same unified model, same layout language).
Item {
    id: pane
    property string selProject: ""

    ProjectRail {
        id: rail
        anchors { top: parent.top; left: parent.left; bottom: parent.bottom
                  margins: 14 }
        width: 260
        visible: (Todo.projects ?? []).length > 0
        selectedId: pane.selProject
        onPick: id => pane.selProject = id
    }

    TaskBoard {
        anchors { top: parent.top; bottom: parent.bottom; right: parent.right
                  left: rail.visible ? rail.right : parent.left
                  margins: 14 }
        filterProject: pane.selProject
    }
}
