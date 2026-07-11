import QtQuick
import "components"

// Calendar tab — month grid | day agenda. Grid/index math ported from velumeron's
// CalendarMenu.qml. Day cells show event dots (per-calendar colour) AND due-task
// dots (accent) — with a todo-only account (Vikunja) the month view stays useful.
// Quick-add: events when a writable VEVENT calendar exists; otherwise the row
// creates a task due on the selected day.
Item {
    id: pane

    property var today:     new Date()
    property int viewYear:  today.getFullYear()
    property int viewMonth: today.getMonth()   // 0-based
    property var selDay:    new Date()

    function goToday() {
        pane.today     = new Date()
        pane.viewYear  = pane.today.getFullYear()
        pane.viewMonth = pane.today.getMonth()
        pane.selDay    = new Date(pane.today)
    }
    function shiftMonth(dir) {
        var m = pane.viewMonth + dir
        pane.viewYear += Math.floor(m / 12)
        pane.viewMonth = ((m % 12) + 12) % 12
    }
    function dayKey(d)  { return d.getFullYear() * 10000 + (d.getMonth() + 1) * 100 + d.getDate() }
    function ymd(d) {
        function p(n) { return (n < 10 ? "0" : "") + n }
        return d.getFullYear() + "-" + p(d.getMonth() + 1) + "-" + p(d.getDate())
    }
    readonly property int firstDow: 1   // Monday (matches velumeron's default)

    readonly property var gridDays: {
        var first = new Date(pane.viewYear, pane.viewMonth, 1)
        var off   = (first.getDay() - pane.firstDow + 7) % 7
        var dim   = new Date(pane.viewYear, pane.viewMonth + 1, 0).getDate()
        var cells = Math.ceil((off + dim) / 7) * 7
        var out = []
        for (var i = 0; i < cells; i++)
            out.push(new Date(pane.viewYear, pane.viewMonth, 1 - off + i))
        return out
    }

    // ── Events (CalDAV cache) ────────────────────────────────────────────────
    readonly property var events: (CalDav.cache.events ?? [])
    function calColor(calId) {
        var cs = CalDav.cache.calendars ?? []
        for (var i = 0; i < cs.length; i++)
            if (cs[i].id === calId && cs[i].color) return cs[i].color
        return Theme.boActive
    }
    readonly property var eventCals: (CalDav.cache.calendars ?? []).filter(c => c.vevent && c.writable)
    readonly property string eventCal: pane.eventCals.length > 0 ? pane.eventCals[0].id : ""

    readonly property var eventsByDay: {
        var map = {}
        var evs = pane.events
        for (var i = 0; i < evs.length; i++) {
            var e = evs[i]
            var s = new Date(e.startMs)
            var last = new Date(Math.max(e.startMs, e.endMs - 1))
            var d = new Date(s.getFullYear(), s.getMonth(), s.getDate())
            for (var n = 0; d <= last && n < 62; n++) {
                var k = pane.dayKey(d)
                if (!map[k]) map[k] = []
                map[k].push(e)
                d = new Date(d.getFullYear(), d.getMonth(), d.getDate() + 1)
            }
        }
        return map
    }

    // ── Due tasks per day (unified Todo model) ──────────────────────────────
    readonly property var tasksByDay: {
        var map = {}
        var ts = Todo.tasks ?? []
        for (var i = 0; i < ts.length; i++) {
            if (ts[i].done || !ts[i].dueMs) continue
            var d = new Date(ts[i].dueMs)
            var k = pane.dayKey(d)
            if (!map[k]) map[k] = []
            map[k].push(ts[i])
        }
        return map
    }

    readonly property var selEvents: {
        var l = (pane.eventsByDay[pane.dayKey(pane.selDay)] ?? []).slice()
        l.sort((a, b) => ((b.allDay ? 1 : 0) - (a.allDay ? 1 : 0)) || (a.startMs - b.startMs))
        return l
    }
    readonly property var selTasks: pane.tasksByDay[pane.dayKey(pane.selDay)] ?? []

    readonly property string addTaskTarget: {
        var ps = Todo.projects ?? []
        for (var j = 0; j < ps.length; j++) if (ps[j].writable) return ps[j].id
        return ""
    }
    function addFromText(text) {
        var t = text.trim()
        if (t === "") return
        if (pane.eventCal !== "") {
            var m = t.match(/^(\d{1,2}):(\d{2})\s+(.+)$/)
            if (m) CalDav.addEvent(pane.eventCal, m[3], pane.ymd(pane.selDay),
                                   ("0" + m[1]).slice(-2) + ":" + m[2], 60)
            else   CalDav.addEvent(pane.eventCal, t, pane.ymd(pane.selDay), "", 0)
        } else if (pane.addTaskTarget !== "") {
            Todo.addTask(pane.addTaskTarget, t, pane.ymd(pane.selDay), "")
        }
    }

    readonly property int gridW: Math.round((width - 3 * 14) * 0.58)

    // ── Month grid column ───────────────────────────────────────────────────
    Column {
        id: gridCol
        anchors { top: parent.top; left: parent.left; margins: 14 }
        width: pane.gridW
        spacing: 10

        Item {
            width: parent.width; height: 30
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text:  Qt.formatDate(new Date(pane.viewYear, pane.viewMonth, 1), "MMMM yyyy")
                color: Theme.fgBright; font.pixelSize: 19; font.bold: true; font.family: Theme.fontFamily
            }
            Row {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                spacing: 4
                NavBtn { sym: "󰅁"; onTap: pane.shiftMonth(-1) }
                NavBtn { sym: "󰋙"; dim: pane.dayKey(pane.selDay) === pane.dayKey(pane.today)
                         onTap: pane.goToday() }
                NavBtn { sym: "󰅂"; onTap: pane.shiftMonth(1) }
            }
        }

        Row {
            spacing: 4
            Repeater {
                model: 7
                delegate: Text {
                    required property int index
                    width: grid.cellW; horizontalAlignment: Text.AlignHCenter
                    // 2026-07-05 is a Sunday — a stable base to name weekdays from.
                    text:  Qt.formatDate(new Date(2026, 6, 5 + pane.firstDow + index), "ddd")
                    color: Theme.fgMuted; font.pixelSize: 12; font.bold: true; font.family: Theme.fontFamily
                }
            }
        }

        Grid {
            id: grid
            columns: 7
            spacing: 4
            readonly property int cellW: Math.floor((parent.width - 6 * 4) / 7)
            Repeater {
                model: pane.gridDays
                delegate: Rectangle {
                    id: cell
                    required property var modelData
                    readonly property int  k:       pane.dayKey(modelData)
                    readonly property bool inMonth: modelData.getMonth() === pane.viewMonth
                    readonly property bool isToday: k === pane.dayKey(pane.today)
                    readonly property bool isSel:   k === pane.dayKey(pane.selDay)
                    readonly property var  evs:     pane.eventsByDay[k] ?? []
                    readonly property var  dues:    pane.tasksByDay[k] ?? []
                    width: grid.cellW
                    height: Math.max(44, Math.round(grid.cellW * 0.62))
                    radius: 8
                    color:  isSel ? Qt.alpha(Theme.accent, 0.45)
                          : cellHov.containsMouse ? Theme.bgSecondary : "transparent"
                    border.width: isToday ? 1 : 0
                    border.color: Theme.accent
                    Behavior on color { ColorAnimation { duration: 90 } }

                    Column {
                        anchors.centerIn: parent
                        spacing: 4
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text:  cell.modelData.getDate()
                            color: cell.isSel ? Theme.fgBright
                                 : cell.inMonth ? (cell.isToday ? Theme.accent : Theme.fgPrimary)
                                 : Theme.fgMuted
                            font.pixelSize: 15; font.family: Theme.fontFamily
                            font.bold: cell.isToday || cell.isSel
                            opacity: cell.inMonth ? 1.0 : 0.45
                        }
                        Row {
                            anchors.horizontalCenter: parent.horizontalCenter
                            spacing: 3
                            height: 5
                            Repeater {   // events, per-calendar colour
                                model: Math.min(2, cell.evs.length)
                                delegate: Rectangle {
                                    required property int index
                                    width: 5; height: 5; radius: 2.5
                                    color: pane.calColor(cell.evs[index].cal)
                                }
                            }
                            Repeater {   // due tasks, accent
                                model: Math.min(3 - Math.min(2, cell.evs.length), cell.dues.length)
                                delegate: Rectangle {
                                    width: 5; height: 5; radius: 2.5
                                    color: Theme.accent
                                }
                            }
                        }
                    }
                    MouseArea {
                        id: cellHov
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: pane.selDay = new Date(cell.modelData)
                        onDoubleClicked: { pane.selDay = new Date(cell.modelData); dayInput.focusInput() }
                    }
                }
            }
        }
    }

    // ── Day agenda column ───────────────────────────────────────────────────
    Column {
        anchors { top: parent.top; left: gridCol.right; right: parent.right
                  bottom: parent.bottom; margins: 14 }
        spacing: 10

        Text {
            text:  Qt.formatDate(pane.selDay, "dddd, MMM d")
            color: Theme.fgMuted; font.pixelSize: 15; font.bold: true
            font.letterSpacing: 0.5; font.family: Theme.fontFamily
        }

        Flickable {
            width: parent.width
            height: parent.height - 30 - 46 - 30
            contentHeight: agendaCol.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id: agendaCol
                width: parent.width
                spacing: 4

                Repeater {
                    model: pane.selEvents
                    delegate: Rectangle {
                        id: evRow
                        required property var modelData
                        width: agendaCol.width; height: 44; radius: 8
                        color: Theme.bgElement
                        Rectangle {
                            anchors { left: parent.left; leftMargin: 7; verticalCenter: parent.verticalCenter }
                            width: 3; height: parent.height - 16; radius: 1.5
                            color: pane.calColor(evRow.modelData.cal)
                        }
                        Column {
                            anchors { left: parent.left; leftMargin: 18; right: parent.right; rightMargin: 8
                                      verticalCenter: parent.verticalCenter }
                            spacing: 1
                            Text {
                                width: parent.width; elide: Text.ElideRight
                                text:  evRow.modelData.summary + (evRow.modelData.recurring ? "  󰑖" : "")
                                color: Theme.fgPrimary; font.pixelSize: 15; font.family: Theme.fontFamily
                            }
                            Text {
                                width: parent.width; elide: Text.ElideRight
                                text: (evRow.modelData.allDay ? "all day"
                                       : Qt.formatTime(new Date(evRow.modelData.startMs), "hh:mm") + " – "
                                         + Qt.formatTime(new Date(evRow.modelData.endMs), "hh:mm"))
                                      + (evRow.modelData.location ? "   󰍎 " + evRow.modelData.location : "")
                                color: Theme.fgMuted; font.pixelSize: 12; font.family: Theme.fontFamily
                            }
                        }
                    }
                }

                Text {
                    visible: pane.selTasks.length > 0
                    text: "DUE"; topPadding: 6
                    color: Theme.fgMuted; font.pixelSize: 12; font.bold: true
                    font.letterSpacing: 0.5; font.family: Theme.fontFamily
                }
                Repeater {
                    model: pane.selTasks
                    delegate: Rectangle {
                        id: dueRow
                        required property var modelData
                        width: agendaCol.width; height: 38; radius: 8
                        color: Theme.bgElement
                        Rectangle {
                            anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                            width: 16; height: 16; radius: 8
                            color: "transparent"
                            border.width: 1
                            border.color: dueChk.containsMouse ? Theme.accent : Theme.fgMuted
                            Text {
                                anchors.centerIn: parent
                                visible: dueChk.containsMouse
                                text: "󰄬"; color: Theme.fgMuted
                                font.pixelSize: 11; font.family: Theme.fontFamily
                            }
                            MouseArea { id: dueChk; anchors.fill: parent; anchors.margins: -5
                                        hoverEnabled: true
                                        onClicked: Todo.toggleTask(dueRow.modelData) }
                        }
                        Text {
                            anchors { left: parent.left; leftMargin: 36; right: parent.right; rightMargin: 8
                                      verticalCenter: parent.verticalCenter }
                            elide: Text.ElideRight
                            text:  dueRow.modelData.title
                            color: Theme.fgPrimary; font.pixelSize: 15; font.family: Theme.fontFamily
                        }
                    }
                }

                Text {
                    visible: pane.selEvents.length === 0 && pane.selTasks.length === 0
                    text: "nothing scheduled"; color: Theme.fgMuted
                    font.pixelSize: 13; font.family: Theme.fontFamily
                }
            }
        }

        InputRow {
            id: dayInput
            width: parent.width
            visible: pane.eventCal !== "" || pane.addTaskTarget !== ""
            placeholder: pane.eventCal !== ""
                         ? "add event — “14:00 title” for a timed one"
                         : "add task due " + Qt.formatDate(pane.selDay, "MMM d")
            onSubmit: text => pane.addFromText(text)
        }
    }
}
