import QtQuick

// Task detail / editor (blueprint #8): full editing of a Vikunja task — title,
// description, priority, due date, project (move), labels, and subtasks. A real
// overlay dialog; its card scrolls if the content is tall. openEdit(task).
Item {
    id: dlg
    property bool open: false
    property var task: ({})
    property string selPriority: "0"
    property string selDue: ""
    property string selProject: ""
    property var selLabelIds: []
    property bool confirmDelete: false
    visible: open
    z: 500
    readonly property string taskId: String(dlg.task.id ?? "")
    readonly property bool isVk: dlg.taskId.indexOf("vk:") === 0

    readonly property var priorities: [
        { key: "0", label: "None" }, { key: "1", label: "Low" }, { key: "2", label: "Medium" },
        { key: "3", label: "High" }, { key: "4", label: "Urgent" }, { key: "5", label: "DO NOW" }]
    readonly property var projectOptions: (Todo.projects ?? [])
        .filter(p => p.source === "vikunja" && p.writable)
        .map(p => ({ key: p.id, label: p.title, color: (p.color && p.color !== "") ? p.color : Theme.accent }))
    readonly property var subtasks: (Todo.tasks ?? []).filter(t => t.parentTaskId === dlg.taskId)

    function _fmt(ms) {
        if (!ms || ms <= 0) return ""
        var d = new Date(ms); function p(n){return (n<10?"0":"")+n}
        return d.getFullYear()+"-"+p(d.getMonth()+1)+"-"+p(d.getDate())
    }
    // Vikunja stores descriptions as HTML — show plain text for editing.
    function _plain(s) {
        return (s || "")
            .replace(/<\s*br\s*\/?>/gi, "\n").replace(/<\/\s*p\s*>/gi, "\n")
            .replace(/<[^>]+>/g, "")
            .replace(/&nbsp;/g, " ").replace(/&amp;/g, "&")
            .replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&quot;/g, '"')
            .replace(/\n{3,}/g, "\n\n").trim()
    }
    function _hasLabel(id) { return dlg.selLabelIds.indexOf(id) >= 0 }
    function _toggleLabel(id) {
        var out = dlg.selLabelIds.slice()
        var i = out.indexOf(id)
        if (i >= 0) out.splice(i, 1); else out.push(id)
        dlg.selLabelIds = out
    }

    function openEdit(task) {
        dlg.task = task || {}
        dlg.confirmDelete = false
        titleF.text = dlg.task.title || ""
        notesF.text = dlg._plain(dlg.task.notes || "")
        dlg.selPriority = String(dlg.task.priority ?? 0)
        dlg.selDue = dlg._fmt(dlg.task.dueMs)
        dlg.selProject = dlg.task.projectId || ""
        dlg.selLabelIds = (dlg.task.labels ?? []).map(l => l.id)
        subF.clear()
        dlg.open = true
    }

    readonly property bool ready: titleF.text.trim() !== ""

    function submit() {
        if (!dlg.ready || !dlg.isVk) { dlg.open = false; return }
        Todo.updateTask(dlg.task, { title: titleF.text.trim(), notes: notesF.text,
                                    priority: parseInt(dlg.selPriority), dueYmd: dlg.selDue })
        if (dlg.selProject !== "" && dlg.selProject !== dlg.task.projectId)
            Todo.moveTask(dlg.task, dlg.selProject)
        var orig = (dlg.task.labels ?? []).map(l => l.id).sort()
        var cur = dlg.selLabelIds.slice().sort()
        if (JSON.stringify(orig) !== JSON.stringify(cur))
            Todo.setLabels(dlg.task, dlg.selLabelIds)
        dlg.open = false
    }

    Rectangle {
        anchors.fill: parent; color: Qt.rgba(0, 0, 0, 0.5)
        MouseArea { anchors.fill: parent; onClicked: dlg.open = false }
    }

    Rectangle {
        anchors.centerIn: parent
        width: Math.min(500, dlg.width - 60)
        height: Math.min(dlg.height - 60, card.implicitHeight + 32)
        radius: 14; color: Theme.surface
        border.width: 1; border.color: Qt.alpha(Theme.boNormal, 0.5)
        MouseArea { anchors.fill: parent }

        Flickable {
            anchors.fill: parent; anchors.margins: 20
            contentHeight: card.implicitHeight; clip: true
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id: card
                width: parent.width
                spacing: 14

                Text { text: "Task"; color: Theme.fgBright; font.pixelSize: 18; font.bold: true; font.family: Theme.fontFamily }

                SettingsField { id: titleF; width: parent.width; placeholder: "task title" }

                Column {
                    width: parent.width; spacing: 5
                    Text { text: "Description"; color: Theme.fgMuted; font.pixelSize: 12; font.family: Theme.fontFamily }
                    NotesField { id: notesF; width: parent.width; placeholder: "add a description" }
                }

                Row {
                    width: parent.width; spacing: 12
                    Column {
                        width: (parent.width - 12) / 2; spacing: 5
                        Text { text: "Priority"; color: Theme.fgMuted; font.pixelSize: 12; font.family: Theme.fontFamily }
                        Picker { width: parent.width; options: dlg.priorities; current: dlg.selPriority
                                 placeholder: "priority"; onPicked: k => dlg.selPriority = k }
                    }
                    Column {
                        width: (parent.width - 12) / 2; spacing: 5
                        Text { text: "Due date"; color: Theme.fgMuted; font.pixelSize: 12; font.family: Theme.fontFamily }
                        DatePicker { width: parent.width; ymd: dlg.selDue; allowEmpty: true
                                     placeholder: "no due date"; onPicked: k => dlg.selDue = k }
                    }
                }

                Column {
                    width: parent.width; spacing: 5
                    Text { text: "Project"; color: Theme.fgMuted; font.pixelSize: 12; font.family: Theme.fontFamily }
                    Picker { width: parent.width; options: dlg.projectOptions; current: dlg.selProject
                             placeholder: "project"; onPicked: k => dlg.selProject = k }
                }

                // Labels — toggle chips (filled = attached).
                Column {
                    width: parent.width; spacing: 6
                    visible: (Todo.labels ?? []).length > 0 || dlg.selLabelIds.length > 0
                    Text { text: "Labels"; color: Theme.fgMuted; font.pixelSize: 12; font.family: Theme.fontFamily }
                    Flow {
                        width: parent.width; spacing: 6
                        Repeater {
                            model: Todo.labels ?? []
                            delegate: Rectangle {
                                required property var modelData
                                readonly property bool on: dlg._hasLabel(modelData.id)
                                readonly property color chip: (modelData.color && modelData.color !== "") ? modelData.color : Theme.accent
                                height: 28; radius: 14
                                width: lblTxt.implicitWidth + 28
                                color: on ? chip : Qt.alpha(chip, 0.14)
                                border.width: on ? 0 : 1; border.color: Qt.alpha(chip, 0.6)
                                Text { id: lblTxt; anchors.centerIn: parent; text: modelData.title
                                       color: on ? "#ffffff" : Theme.fgPrimary
                                       font.pixelSize: 12; font.bold: on; font.family: Theme.fontFamily }
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                            onClicked: dlg._toggleLabel(modelData.id) }
                            }
                        }
                    }
                }

                // Subtasks — existing list + quick add.
                Column {
                    width: parent.width; spacing: 6
                    Text { text: "Subtasks" + (dlg.subtasks.length > 0 ? "  " + dlg.subtasks.length : "")
                           color: Theme.fgMuted; font.pixelSize: 12; font.family: Theme.fontFamily }
                    Repeater {
                        model: dlg.subtasks
                        delegate: Rectangle {
                            required property var modelData
                            width: parent.width; height: 34; radius: 8; color: Theme.bgElement
                            Rectangle {
                                id: subChk
                                anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                                width: 16; height: 16; radius: 8
                                color: modelData.done ? Theme.accent : "transparent"
                                border.width: 1; border.color: modelData.done ? Theme.accent : Theme.fgMuted
                                Text { anchors.centerIn: parent; visible: modelData.done; text: "󰄬"
                                       color: Theme.fgBright; font.pixelSize: 11; font.family: Theme.fontFamily }
                                MouseArea { anchors.fill: parent; anchors.margins: -5
                                            onClicked: Todo.toggleTask(modelData) }
                            }
                            Text {
                                anchors { left: subChk.right; leftMargin: 10; right: subDel.left; rightMargin: 8
                                          verticalCenter: parent.verticalCenter }
                                elide: Text.ElideRight; text: modelData.title
                                color: modelData.done ? Theme.fgMuted : Theme.fgPrimary
                                font.pixelSize: 13; font.strikeout: modelData.done; font.family: Theme.fontFamily
                            }
                            Text {
                                id: subDel
                                anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                                text: "󰅖"; color: sdHov.containsMouse ? Theme.fgUrgent : Theme.fgMuted
                                font.pixelSize: 14; font.family: Theme.fontFamily
                                MouseArea { id: sdHov; anchors.fill: parent; anchors.margins: -5; hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor; onClicked: Todo.deleteTask(modelData) }
                            }
                        }
                    }
                    InputRow {
                        id: subF; width: parent.width; visible: dlg.isVk
                        placeholder: "add a subtask"
                        onSubmit: t => Todo.addTask(dlg.task.projectId, t, "", dlg.taskId)
                    }
                }

                // actions
                Item {
                    width: parent.width; height: 36
                    Rectangle {
                        anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                        width: delLbl.implicitWidth + 26; height: 36; radius: 8
                        visible: dlg.isVk
                        color: dlg.confirmDelete ? Theme.fgUrgent
                             : delHov.containsMouse ? Qt.alpha(Theme.fgUrgent, 0.2) : Theme.bgElement
                        Text { id: delLbl; anchors.centerIn: parent
                               text: dlg.confirmDelete ? "󰩹  Really delete?" : "󰩹  Delete"
                               color: dlg.confirmDelete ? Theme.fgBright : Theme.fgUrgent
                               font.pixelSize: 13; font.family: Theme.fontFamily }
                        MouseArea { id: delHov; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (dlg.confirmDelete) { Todo.deleteTask(dlg.task); dlg.open = false }
                                else dlg.confirmDelete = true
                            } }
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
                            Text { id: savLbl; anchors.centerIn: parent; text: "󰄬  Save"; color: Theme.fgBright
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
}
