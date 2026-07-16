import QtQuick

// Project editor (blueprint #8): create a new project or edit an existing one —
// name, colour, parent, description. Vikunja projects only (the CRUD surface).
// A real overlay dialog (backdrop + centred card); pickers open as overlays so
// nothing grows the card. openNew(parentId) / openEdit(projectId).
Item {
    id: dlg
    property bool open: false
    property string editId: ""            // "" = create mode
    property string selParent: ""
    property string selColor: ""
    property bool confirmDelete: false
    visible: open
    z: 500

    readonly property bool editing: dlg.editId !== ""

    function _project(id) {
        var ps = Todo.projects ?? []
        for (var i = 0; i < ps.length; i++) if (ps[i].id === id) return ps[i]
        return null
    }
    // ids of editId + all its descendants — invalid parents (would make a cycle).
    function _descendants(id) {
        var excl = {}; excl[id] = true
        var ps = Todo.projects ?? [], changed = true
        while (changed) {
            changed = false
            for (var i = 0; i < ps.length; i++)
                if (excl[ps[i].parentId] && !excl[ps[i].id]) { excl[ps[i].id] = true; changed = true }
        }
        return excl
    }

    readonly property var parentOptions: {
        var out = [{ key: "", label: "— top level (no parent) —", color: "" }]
        var excl = dlg.editing ? dlg._descendants(dlg.editId) : {}
        var ps = Todo.projects ?? []
        for (var i = 0; i < ps.length; i++) {
            var p = ps[i]
            if (p.source === "vikunja" && p.writable && !excl[p.id])
                out.push({ key: p.id, label: p.title, color: (p.color && p.color !== "") ? p.color : Theme.accent })
        }
        return out
    }

    function openNew(parentId) {
        dlg.editId = ""; dlg.confirmDelete = false
        titleF.text = ""; notesF.text = ""
        dlg.selParent = (parentId && parentId.indexOf("vk:") === 0) ? parentId : ""
        dlg.selColor = ""
        dlg.open = true
    }
    function openEdit(projectId) {
        var p = dlg._project(projectId)
        if (!p) return
        dlg.editId = projectId; dlg.confirmDelete = false
        titleF.text = p.title; notesF.text = p.description || ""
        dlg.selParent = p.parentId || ""
        dlg.selColor = p.color || ""
        dlg.open = true
    }

    readonly property bool ready: titleF.text.trim() !== ""

    function submit() {
        if (!dlg.ready) return
        if (dlg.editing)
            Todo.updateProject(dlg.editId, { title: titleF.text.trim(), color: dlg.selColor,
                                             description: notesF.text, parentId: dlg.selParent })
        else
            Todo.addProject(titleF.text.trim(), dlg.selParent, dlg.selColor, notesF.text)
        dlg.open = false
    }

    Rectangle {
        anchors.fill: parent; color: Qt.rgba(0, 0, 0, 0.5)
        MouseArea { anchors.fill: parent; onClicked: dlg.open = false }
    }

    Rectangle {
        anchors.centerIn: parent
        width: Math.min(460, dlg.width - 60)
        height: card.implicitHeight + 40
        radius: 14; color: Theme.surface
        border.width: 1; border.color: Qt.alpha(Theme.boNormal, 0.5)
        MouseArea { anchors.fill: parent }

        Column {
            id: card
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 20 }
            spacing: 14

            Text {
                text: dlg.editing ? "Edit project" : "New project"
                color: Theme.fgBright; font.pixelSize: 18; font.bold: true; font.family: Theme.fontFamily
            }

            SettingsField { id: titleF; width: parent.width; placeholder: "project name" }

            Row {
                width: parent.width; spacing: 12
                Column {
                    width: (parent.width - 12) / 2; spacing: 5
                    Text { text: "Colour"; color: Theme.fgMuted; font.pixelSize: 12; font.family: Theme.fontFamily }
                    ColorField { width: parent.width; color: dlg.selColor; onPicked: c => dlg.selColor = c }
                }
                Column {
                    width: (parent.width - 12) / 2; spacing: 5
                    Text { text: "Parent"; color: Theme.fgMuted; font.pixelSize: 12; font.family: Theme.fontFamily }
                    Picker {
                        width: parent.width; options: dlg.parentOptions; current: dlg.selParent
                        placeholder: "top level"; onPicked: k => dlg.selParent = k
                    }
                }
            }

            Column {
                width: parent.width; spacing: 5
                Text { text: "Description"; color: Theme.fgMuted; font.pixelSize: 12; font.family: Theme.fontFamily }
                NotesField { id: notesF; width: parent.width; placeholder: "optional description" }
            }

            // actions
            Item {
                width: parent.width; height: 36
                // Delete (edit mode) — two-step confirm on the left.
                Row {
                    anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                    spacing: 8
                    visible: dlg.editing
                    Rectangle {
                        width: delLbl.implicitWidth + 26; height: 36; radius: 8
                        color: dlg.confirmDelete ? Theme.fgUrgent
                             : delHov.containsMouse ? Qt.alpha(Theme.fgUrgent, 0.2) : Theme.bgElement
                        Text { id: delLbl; anchors.centerIn: parent
                               text: dlg.confirmDelete ? "󰩹  Really delete?" : "󰩹  Delete"
                               color: dlg.confirmDelete ? Theme.fgBright : Theme.fgUrgent
                               font.pixelSize: 13; font.family: Theme.fontFamily }
                        MouseArea { id: delHov; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (dlg.confirmDelete) { Todo.deleteProject(dlg.editId); dlg.open = false }
                                else dlg.confirmDelete = true
                            } }
                    }
                }
                Row {
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    spacing: 10
                    Rectangle {
                        width: cxl.implicitWidth + 28; height: 36; radius: 8
                        color: cxlHov.containsMouse ? Theme.bgSecondary : Theme.bgElement
                        Text { id: cxl; anchors.centerIn: parent; text: "Cancel"; color: Theme.fgPrimary
                               font.pixelSize: 14; font.family: Theme.fontFamily }
                        MouseArea { id: cxlHov; anchors.fill: parent; hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor; onClicked: dlg.open = false }
                    }
                    Rectangle {
                        width: savLbl.implicitWidth + 30; height: 36; radius: 8
                        color: !dlg.ready ? Theme.bgElement : savHov.containsMouse ? Theme.bgHover : Theme.accent
                        opacity: dlg.ready ? 1.0 : 0.5
                        Text { id: savLbl; anchors.centerIn: parent
                               text: dlg.editing ? "󰄬  Save" : "󰐕  Create"; color: Theme.fgBright
                               font.pixelSize: 14; font.bold: true; font.family: Theme.fontFamily }
                        MouseArea { id: savHov; anchors.fill: parent; hoverEnabled: true
                                    cursorShape: dlg.ready ? Qt.PointingHandCursor : Qt.ArrowCursor
                                    onClicked: dlg.submit() }
                    }
                }
            }
        }
    }
}
