import QtQuick

// Add dialog (M2 Slice B): one entry point to create either a Termin (CalDAV
// event) or a Task (todo). Task → pick project + due date; Termin → pick calendar
// + date + optional time. Opened via openWith(ymd) from the calendar's + button.
Item {
    id: dlg
    property bool open: false
    property string defaultYmd: ""
    property string mode: "task"          // "task" | "event"
    property string selProject: ""
    property string selCal: ""
    property string dueYmd: ""            // task due (optional)
    property string evYmd: ""             // event date
    property string evHm: ""              // event time ("" = all day)
    visible: open
    z: 500

    readonly property var projects: (Todo.projects ?? [])
        .filter(p => p.writable)
        .map(p => ({ key: p.id, label: p.title, color: (p.color && p.color !== "") ? p.color : Theme.accent }))
    // push-loop merge — Array.concat on a QVariantList sequence wrapper is O(n²)
    // (see CalendarPane._merge); indexed access is O(1).
    function _merge(a, b) {
        var out = [], i; a = a ?? []; b = b ?? []
        for (i = 0; i < a.length; i++) out.push(a[i])
        for (i = 0; i < b.length; i++) out.push(b[i])
        return out
    }
    readonly property var eventCals: dlg._merge(CalDav.calendars, Local.calendars)
        .filter(c => c.vevent && c.writable)
        .map(c => ({ key: c.id, label: c.name || "calendar", color: c.color || "" }))

    function openWith(ymd) {
        dlg.defaultYmd = ymd
        dlg.mode = "task"
        dlg.selProject = dlg.projects.length > 0 ? dlg.projects[0].key : ""
        dlg.selCal = dlg.eventCals.length > 0 ? dlg.eventCals[0].key : ""
        titleF.text = ""; dlg.dueYmd = ymd; dlg.evYmd = ymd; dlg.evHm = ""
        dlg.open = true
    }

    readonly property bool ready: titleF.text.trim() !== "" &&
        (dlg.mode === "task" ? dlg.selProject !== "" : (dlg.selCal !== "" && dlg.evYmd !== ""))

    function submit() {
        if (!dlg.ready) return
        if (dlg.mode === "task") {
            Todo.addTask(dlg.selProject, titleF.text.trim(), dlg.dueYmd, "")
        } else if (dlg.selCal.indexOf("loc:") === 0) {
            Local.addEvent(dlg.selCal.slice(4), titleF.text.trim(), dlg.evYmd,
                           dlg.evHm !== "" ? dlg.evHm : "", dlg.evHm !== "" ? 60 : 60)
        } else {
            CalDav.addEvent(dlg.selCal, titleF.text.trim(), dlg.evYmd,
                            dlg.evHm !== "" ? dlg.evHm : "", dlg.evHm !== "" ? 60 : 0)
        }
        dlg.open = false
    }

    // dim backdrop (click outside closes)
    Rectangle {
        anchors.fill: parent; color: Qt.rgba(0, 0, 0, 0.5)
        MouseArea { anchors.fill: parent; onClicked: dlg.open = false }
    }

    Rectangle {
        anchors.centerIn: parent
        width: Math.min(440, dlg.width - 60)
        height: card.implicitHeight + 40
        radius: 14; color: Theme.surface
        border.width: 1; border.color: Qt.alpha(Theme.boNormal, 0.5)
        MouseArea { anchors.fill: parent }   // swallow clicks so backdrop doesn't close

        Column {
            id: card
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 20 }
            spacing: 14

            // header + mode toggle
            Item {
                width: parent.width; height: 34
                Text {
                    anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                    text: "New"; color: Theme.fgBright; font.pixelSize: 18; font.bold: true; font.family: Theme.fontFamily
                }
                Row {
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    spacing: 4
                    Repeater {
                        model: [{ v: "task", l: "󰄲  Task" }, { v: "event", l: "󰃭  Termin" }]
                        delegate: Rectangle {
                            required property var modelData
                            readonly property bool on: dlg.mode === modelData.v
                            width: mlbl.implicitWidth + 22; height: 30; radius: 7
                            color: on ? Qt.alpha(Theme.accent, 0.35)
                                 : mHov.containsMouse ? Theme.bgSecondary : Theme.bgElement
                            Text {
                                id: mlbl; anchors.centerIn: parent; text: modelData.l
                                color: parent.on ? Theme.fgBright : Theme.fgPrimary
                                font.pixelSize: 13; font.bold: parent.on; font.family: Theme.fontFamily
                            }
                            MouseArea { id: mHov; anchors.fill: parent; hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor; onClicked: dlg.mode = modelData.v }
                        }
                    }
                }
            }

            SettingsField { id: titleF; width: parent.width; placeholder: dlg.mode === "task" ? "task title" : "event title" }

            // TASK fields
            Column {
                visible: dlg.mode === "task"; width: parent.width; spacing: 14
                Column {
                    width: parent.width; spacing: 5
                    Text { text: "Project"; color: Theme.fgMuted; font.pixelSize: 12; font.family: Theme.fontFamily }
                    Picker {
                        id: projPick; width: parent.width
                        options: dlg.projects; current: dlg.selProject; placeholder: "pick a project"
                        onPicked: key => dlg.selProject = key
                    }
                }
                Column {
                    width: parent.width; spacing: 5
                    Text { text: "Due date (optional)"; color: Theme.fgMuted; font.pixelSize: 12; font.family: Theme.fontFamily }
                    DatePicker {
                        width: parent.width; ymd: dlg.dueYmd; allowEmpty: true; placeholder: "no due date"
                        onPicked: k => dlg.dueYmd = k
                    }
                }
            }

            // EVENT fields
            Column {
                visible: dlg.mode === "event"; width: parent.width; spacing: 14
                Text {
                    visible: dlg.eventCals.length === 0
                    width: parent.width; wrapMode: Text.WordWrap
                    text: "No event calendar. Add a writable CalDAV calendar in Settings first."
                    color: Theme.fgUrgent; font.pixelSize: 13; font.family: Theme.fontFamily
                }
                Column {
                    visible: dlg.eventCals.length > 0; width: parent.width; spacing: 5
                    Text { text: "Calendar"; color: Theme.fgMuted; font.pixelSize: 12; font.family: Theme.fontFamily }
                    Picker {
                        id: calPick; width: parent.width
                        options: dlg.eventCals; current: dlg.selCal; placeholder: "pick a calendar"
                        onPicked: key => dlg.selCal = key
                    }
                }
                Column {
                    visible: dlg.eventCals.length > 0; width: parent.width; spacing: 14
                    Column {
                        width: parent.width; spacing: 5
                        Text { text: "Date"; color: Theme.fgMuted; font.pixelSize: 12; font.family: Theme.fontFamily }
                        DatePicker { width: parent.width; ymd: dlg.evYmd; allowEmpty: false
                                     onPicked: k => dlg.evYmd = k }
                    }
                    Column {
                        width: parent.width; spacing: 5
                        Text { text: "Time"; color: Theme.fgMuted; font.pixelSize: 12; font.family: Theme.fontFamily }
                        TimePicker { width: parent.width; hm: dlg.evHm; onPicked: k => dlg.evHm = k }
                    }
                }
            }

            // actions
            Row {
                anchors.right: parent.right
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
                    width: addl.implicitWidth + 30; height: 36; radius: 8
                    color: !dlg.ready ? Theme.bgElement : addHov.containsMouse ? Theme.bgHover : Theme.accent
                    opacity: dlg.ready ? 1.0 : 0.5
                    Text { id: addl; anchors.centerIn: parent; text: "󰐕  Add"; color: Theme.fgBright
                           font.pixelSize: 14; font.bold: true; font.family: Theme.fontFamily }
                    MouseArea { id: addHov; anchors.fill: parent; hoverEnabled: true
                                cursorShape: dlg.ready ? Qt.PointingHandCursor : Qt.ArrowCursor
                                onClicked: dlg.submit() }
                }
            }
        }
    }
}
