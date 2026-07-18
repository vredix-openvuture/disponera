import QtQuick

// Grouped task board (port of velumeron's quickshell/calendar/TaskBoard.qml —
// Colors/Style → Theme, TodoService → Todo context property). Adds the app's
// inline due-date editor (vikunja tasks only; caldav-client has no set-due yet).
Item {
    id: board
    property string filterProject: ""      // "" = all projects
    signal openTask(var task)              // row-body click → task editor

    property bool showDone: false
    property var _folded: ({})
    function _toggleFold(id) {
        var m = {}
        for (var k in board._folded) m[k] = board._folded[k]
        if (m[id]) delete m[id]
        else       m[id] = true
        board._folded = m
    }
    property string editDueFor: ""         // task id whose due chip is in edit mode

    // Todo.tasks marshals the whole (~400-row) list across the Python↔QML
    // boundary on every read; pull it ONCE per model change and filter the local
    // copy everywhere below instead of re-marshalling it per bucket/per row.
    readonly property var _allTasks: Todo.tasks ?? []
    function subtasksOf(id) { return board._allTasks.filter(t => t.parentTaskId === id) }
    function projectById(id) {
        var ps = Todo.projects ?? []
        for (var i = 0; i < ps.length; i++) if (ps[i].id === id) return ps[i]
        return null
    }
    function colorFor(pid) {
        var p = board.projectById(pid)
        return (p && p.color !== "") ? p.color : Theme.accent
    }

    readonly property real _day0: {
        void board._allTasks
        return new Date(new Date().setHours(0, 0, 0, 0)).getTime()
    }
    readonly property real _dayEnd: board._day0 + 86400000

    function _mine(t) {
        return (board.filterProject === "" || t.projectId === board.filterProject)
               && t.parentTaskId === ""
    }
    readonly property var overdue:  board._allTasks.filter(t => board._mine(t) && !t.done && t.dueMs > 0 && t.dueMs <  board._day0)
    readonly property var today:    board._allTasks.filter(t => board._mine(t) && !t.done && t.dueMs >= board._day0 && t.dueMs < board._dayEnd)
    readonly property var upcoming: board._allTasks.filter(t => board._mine(t) && !t.done && (t.dueMs === 0 || t.dueMs >= board._dayEnd))
    readonly property var done:     board._allTasks.filter(t => board._mine(t) && t.done).slice(0, 30)
    readonly property int  openTotal: overdue.length + today.length + upcoming.length

    readonly property string addTarget: {
        if (board.filterProject !== "") {
            var p = board.projectById(board.filterProject)
            if (p && p.writable) return p.id
        }
        var ps = Todo.projects ?? []
        for (var j = 0; j < ps.length; j++) if (ps[j].writable) return ps[j].id
        return ""
    }

    InputRow {
        id: quickAdd
        anchors { top: parent.top; left: parent.left; right: parent.right }
        visible: board.addTarget !== ""
        placeholder: "new task in " + (board.projectById(board.addTarget)?.title ?? "…")
                     + "   (“jul 20 title” sets a due date)"
        onSubmit: text => {
            // Optional leading due date: "2026-07-20 title" or "jul 20 title".
            var m = text.match(/^(\d{4}-\d{2}-\d{2})\s+(.+)$/)
            if (m) Todo.addTask(board.addTarget, m[2], m[1], "")
            else   Todo.addTask(board.addTarget, text, "", "")
        }
    }

    Flickable {
        anchors { top: quickAdd.visible ? quickAdd.bottom : parent.top; topMargin: 10
                  left: parent.left; right: parent.right; bottom: parent.bottom }
        contentHeight: taskCol.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: taskCol
            width: parent.width
            spacing: 4

            TGroup { title: "OVERDUE";  items: board.overdue;  urgent: true }
            TGroup { title: "TODAY";    items: board.today }
            TGroup { title: "UPCOMING"; items: board.upcoming }

            Item { width: 1; height: 4; visible: board.done.length > 0 }
            Row {
                visible: board.done.length > 0
                spacing: 6
                Text {
                    text: (board.showDone ? "▾" : "▸") + "  COMPLETED  " + board.done.length
                    color: Theme.fgMuted; font.pixelSize: 12; font.bold: true
                    font.letterSpacing: 0.5; font.family: Theme.fontFamily
                    MouseArea { anchors.fill: parent; anchors.margins: -4
                                onClicked: board.showDone = !board.showDone }
                }
            }
            TGroup { title: ""; items: board.showDone ? board.done : [] }

            Text {
                visible: board.openTotal === 0 && board.done.length === 0
                text: "all clear ✓"; color: Theme.fgMuted
                font.pixelSize: 13; font.family: Theme.fontFamily
            }
        }
    }

    // ── Recurring-completion toast ───────────────────────────────────────────
    // Checking a recurring task doesn't stay checked — Vikunja resets it to
    // open with an advanced due date instead. Without this the row just
    // silently flickers back, which reads as a broken checkbox (user report).
    // recurringCompleted only fires once the server has CONFIRMED the rollover.
    property string toastText: ""
    Connections {
        target: Todo
        function onRecurringCompleted(title, dueMs) {
            board.toastText = "✓ " + title + "  ·  next: "
                + Qt.formatDateTime(new Date(dueMs), Settings.dateTimeFmt)
            toastTimer.restart()
        }
    }
    Timer { id: toastTimer; interval: 3000; onTriggered: board.toastText = "" }

    Rectangle {
        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 14 }
        z: 500
        radius: 9; height: 34; width: toastLbl.implicitWidth + 28
        color: Theme.bgElement
        border.width: 1; border.color: Qt.alpha(Theme.accent, 0.4)
        opacity: board.toastText !== "" ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 180 } }
        Text {
            id: toastLbl
            anchors.centerIn: parent
            text: board.toastText
            color: Theme.fgPrimary; font.pixelSize: 13; font.family: Theme.fontFamily
        }
    }

    component TGroup: Column {
        id: tgroup
        property string title:  ""
        property var    items:  []
        property bool   urgent: false
        width: parent ? parent.width : 0
        spacing: 4
        visible: items.length > 0

        readonly property var rows: {
            var out = []
            for (var i = 0; i < tgroup.items.length; i++) {
                var t = tgroup.items[i]
                var kids = board.subtasksOf(t.id)
                out.push({ t: t, sub: false, kids: kids.length,
                           folded: board._folded[t.id] === true })
                if (kids.length > 0 && board._folded[t.id] !== true)
                    for (var j = 0; j < kids.length; j++)
                        out.push({ t: kids[j], sub: true, kids: 0, folded: false })
            }
            return out
        }

        Text {
            visible: tgroup.title !== ""
            text:  tgroup.title
            color: tgroup.urgent ? Theme.fgUrgent : Theme.fgMuted
            font.pixelSize: 12; font.bold: true; font.letterSpacing: 0.5; font.family: Theme.fontFamily
            topPadding: 4
        }
        Repeater {
            model: tgroup.rows
            delegate: TaskRow { required property var modelData; row: modelData }
        }
    }

    component TaskRow: Rectangle {
        id: task
        property var row: ({})
        readonly property var  t:       row.t ?? ({})
        readonly property bool overdue: !t.done && t.dueMs > 0 && t.dueMs < board._day0
        readonly property bool editing: board.editDueFor === t.id
        width: parent ? parent.width : 0
        height: 38
        radius: 8
        color: taskHov.containsMouse ? Theme.bgSecondary : Theme.bgElement
        Behavior on color { ColorAnimation { duration: 90 } }

        readonly property int indent: row.sub ? 28 : 0

        // Row body click → open the full task editor. Declared first so it sits
        // BELOW the checkbox / due / delete controls, which keep their own clicks.
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: board.openTask(task.t)
        }

        Text {
            visible: task.row.kids > 0
            anchors { left: parent.left; leftMargin: 5; verticalCenter: parent.verticalCenter }
            text: task.row.folded ? "▸" : "▾"
            color: Theme.fgMuted; font.pixelSize: 11; font.family: Theme.fontFamily
            MouseArea { anchors.fill: parent; anchors.margins: -6
                        onClicked: board._toggleFold(task.t.id) }
        }

        Rectangle {
            id: check
            anchors { left: parent.left; leftMargin: 17 + task.indent; verticalCenter: parent.verticalCenter }
            width: 18; height: 18; radius: 9
            color: task.t.done ? Theme.accent : "transparent"
            border.width: 1
            border.color: task.t.done ? Theme.accent
                        : checkHov.containsMouse ? Theme.accent : Theme.fgMuted
            Behavior on color { ColorAnimation { duration: 120 } }
            Text {
                anchors.centerIn: parent
                visible: task.t.done || checkHov.containsMouse
                text: "󰄬"; color: task.t.done ? Theme.fgBright : Theme.fgMuted
                font.pixelSize: 12; font.family: Theme.fontFamily
            }
            MouseArea { id: checkHov; anchors.fill: parent; anchors.margins: -5
                        hoverEnabled: true
                        onClicked: Todo.toggleTask(task.t) }
        }

        Row {
            anchors { left: check.right; leftMargin: 10; right: dueChip.left; rightMargin: 8
                      verticalCenter: parent.verticalCenter }
            spacing: 6
            Text {
                visible: (task.t.priority ?? 0) >= 4 && !task.t.done
                anchors.verticalCenter: parent.verticalCenter
                text: "󰈻"; color: Theme.fgUrgent
                font.pixelSize: 12; font.family: Theme.fontFamily
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, parent.width - 20)
                elide: Text.ElideRight
                text:  task.t.title
                color: task.t.done ? Theme.fgMuted : Theme.fgPrimary
                font.pixelSize: 15; font.family: Theme.fontFamily
                font.strikeout: task.t.done === true
            }
            Text {
                visible: task.row.kids > 0 && task.row.folded
                anchors.verticalCenter: parent.verticalCenter
                text: "󰳟 " + task.row.kids
                color: Theme.fgMuted; font.pixelSize: 12; font.family: Theme.fontFamily
            }
        }

        Row {
            id: dueChip
            anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
            spacing: 8

            // Inline due editor (vikunja tasks): YYYY-MM-DD, empty clears.
            Rectangle {
                visible: task.editing
                width: 110; height: 24; radius: 6
                color: Theme.windowBg
                border.width: 1; border.color: Theme.accent
                anchors.verticalCenter: parent.verticalCenter
                TextInput {
                    id: dueInput
                    anchors.fill: parent; anchors.margins: 4
                    color: Theme.fgBright; font.pixelSize: 12; font.family: Theme.fontFamily
                    selectByMouse: true
                    onAccepted: {
                        var v = text.trim()
                        if (v === "" || /^\d{4}-\d{2}-\d{2}$/.test(v)) {
                            Todo.setDue(task.t, v)
                            board.editDueFor = ""
                        }
                    }
                    Keys.onEscapePressed: board.editDueFor = ""
                }
            }
            Text {
                visible: !task.editing && (task.t.dueMs > 0 || taskHov.containsMouse)
                anchors.verticalCenter: parent.verticalCenter
                text: task.t.dueMs > 0 ? Qt.formatDate(new Date(task.t.dueMs), "MMM d") : "󰃭"
                color: task.overdue ? Theme.fgUrgent : Theme.fgMuted
                font.pixelSize: 12; font.family: Theme.fontFamily; font.bold: task.overdue
                MouseArea {
                    anchors.fill: parent; anchors.margins: -4
                    enabled: ("" + task.t.id).indexOf("vk:") === 0
                    onClicked: {
                        board.editDueFor = task.t.id
                        dueInput.text = task.t.dueMs > 0
                            ? Qt.formatDate(new Date(task.t.dueMs), "yyyy-MM-dd") : ""
                        dueInput.forceActiveFocus()
                    }
                }
            }
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 7; height: 7; radius: 3.5
                visible: !taskHov.containsMouse && board.filterProject === "" && !task.row.sub
                color: board.colorFor(task.t.projectId)
            }
            Text {
                visible: taskHov.containsMouse && !task.editing
                anchors.verticalCenter: parent.verticalCenter
                text: "󰅖"; color: tDelHov.containsMouse ? Theme.fgBright : Theme.fgMuted
                font.pixelSize: 15; font.family: Theme.fontFamily
                MouseArea { id: tDelHov; anchors.fill: parent; anchors.margins: -5
                            hoverEnabled: true
                            onClicked: Todo.deleteTask(task.t) }
            }
        }
        MouseArea { id: taskHov; anchors.fill: parent; hoverEnabled: true
                    acceptedButtons: Qt.NoButton }
    }
}
