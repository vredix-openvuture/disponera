import QtQuick
import Qt5Compat.GraphicalEffects
import "components"

// Calendar tab (M2). Toolbar (sidebar toggle · title+nav · view switcher) over a
// collapsible calendar sidebar and a content area that switches between Year /
// Month / Week / Day / Agenda. In Month & Week the grid sits over a resizable
// detail pane (draggable divider). The sidebar lists connected VEVENT calendars
// with per-calendar visibility + colour override (CalPrefs). VTODO task lists are
// NOT calendars — tasks with a due date surface only as accent due-dots.
Item {
    id: pane

    property var today:     new Date()
    property int viewYear:  today.getFullYear()
    property int viewMonth: today.getMonth()   // 0-based
    property var selDay:    new Date()
    // Initial view follows the Calendar setting; the binding breaks on the first
    // manual view switch (the toolbar assigns calView), so it only sets the default.
    property string calView: Settings.defaultView   // year | month | week | day | agenda
    // Immersive mode is owned by the window (one toggle hides the sidebar AND the
    // top bar). The sidebar follows it, but — like the top bar — peeks back when
    // the cursor touches the left edge (hover-to-show).
    property bool immersive: false
    readonly property bool sidebarOpen: !immersive
    readonly property bool sidebarPeek: !sidebarOpen && (sideHover.hovered || edgeHover.hovered)
    property real splitFrac: 0.6               // grid vs detail split (month/week)

    // A modal dialog is open → the whole calendar behind it goes non-interactive.
    // A disabled item tree receives NO mouse/wheel/touch, which is the only
    // reliable way to stop the background from scrolling when the dialog's own
    // Flickable hits its bounds (a WheelHandler doesn't catch that leak).
    readonly property bool modalOpen: eventDialog.open || calendarDialog.open

    // ── date helpers ─────────────────────────────────────────────────────────
    function dayKey(d)  { return d.getFullYear() * 10000 + (d.getMonth() + 1) * 100 + d.getDate() }
    function ymd(d) { function p(n){return (n<10?"0":"")+n} return d.getFullYear()+"-"+p(d.getMonth()+1)+"-"+p(d.getDate()) }
    function addDays(d, n) { return new Date(d.getFullYear(), d.getMonth(), d.getDate() + n) }
    function sameMonth(d) { return d.getFullYear() === pane.viewYear && d.getMonth() === pane.viewMonth }
    readonly property int firstDow: Settings.firstDayOfWeek

    function setSel(d) { pane.selDay = d; pane.viewYear = d.getFullYear(); pane.viewMonth = d.getMonth() }
    function goToday() { pane.today = new Date(); pane.setSel(new Date(pane.today)) }
    function shiftMonth(dir) {
        var m = pane.viewMonth + dir
        pane.viewYear += Math.floor(m / 12)
        pane.viewMonth = ((m % 12) + 12) % 12
    }
    function shift(dir) {
        if (pane.calView === "day")       pane.setSel(pane.addDays(pane.selDay, dir))
        else if (pane.calView === "week") pane.setSel(pane.addDays(pane.selDay, 7 * dir))
        else if (pane.calView === "year") pane.viewYear += dir
        else                              pane.shiftMonth(dir)
    }

    readonly property var gridDays: {
        var first = new Date(pane.viewYear, pane.viewMonth, 1)
        var off   = (first.getDay() - pane.firstDow + 7) % 7
        var dim   = new Date(pane.viewYear, pane.viewMonth + 1, 0).getDate()
        var cells = Math.ceil((off + dim) / 7) * 7
        var out = []
        for (var i = 0; i < cells; i++) out.push(new Date(pane.viewYear, pane.viewMonth, 1 - off + i))
        return out
    }
    readonly property var weekDays: {
        var off = (pane.selDay.getDay() - pane.firstDow + 7) % 7
        var mon = pane.addDays(pane.selDay, -off)
        var out = []
        for (var i = 0; i < 7; i++) out.push(pane.addDays(mon, i))
        return out
    }

    // ── calendars + prefs ────────────────────────────────────────────────────
    // CalDAV calendars + local calendars + ICS subscriptions all share one shape.
    // Merge two lists WITHOUT Array.prototype.concat/slice: those fall into a
    // catastrophically slow O(n²) path when either operand is a QVariantList
    // sequence wrapper (CalDav.events is ~1300 items → .concat took *4.4s* and
    // froze the whole UI on every sync). Indexed access is O(1), so a plain
    // push-loop does the same merge in ~4ms.
    function _merge(a, b) {
        var out = [], i
        a = a ?? []; b = b ?? []
        for (i = 0; i < a.length; i++) out.push(a[i])
        for (i = 0; i < b.length; i++) out.push(b[i])
        return out
    }
    readonly property var calendars: pane._merge(CalDav.calendars, Local.calendars)
    readonly property var displayCals: pane.calendars.filter(c => c.vevent)
    function calHidden(calId) { return CalPrefs.hidden[calId] === true }
    function calColor(calId) {
        var ov = CalPrefs.colors[calId]
        if (ov) return ov
        var cs = pane.calendars
        for (var i = 0; i < cs.length; i++) if (cs[i].id === calId && cs[i].color) return cs[i].color
        return Theme.boActive
    }
    // Display name / description honour the local CalPrefs overrides.
    function calName(calId) {
        if (CalPrefs.names[calId]) return CalPrefs.names[calId]
        var cs = pane.calendars
        for (var i = 0; i < cs.length; i++) if (cs[i].id === calId) return cs[i].name || "calendar"
        return "calendar"
    }
    function calDesc(calId) { return CalPrefs.descriptions[calId] || "" }

    // Event calendars filed into groups for the sidebar: the ungrouped section
    // ("") is emitted first, then each named group in first-seen order.
    readonly property var calGroups: {
        var cals = pane.displayCals, order = [], byGroup = {}
        for (var i = 0; i < cals.length; i++) {
            var g = (CalPrefs.groups[cals[i].id] || "").trim()
            if (byGroup[g] === undefined) { byGroup[g] = []; order.push(g) }
            byGroup[g].push(cals[i])
        }
        order.sort((a, b) => (a === "" ? -1 : b === "" ? 1 : 0))
        var out = []
        for (var j = 0; j < order.length; j++) out.push({ name: order[j], cals: byGroup[order[j]] })
        return out
    }
    readonly property var eventCals: pane.calendars.filter(c => c.vevent && c.writable)
    readonly property string eventCal: pane.eventCals.length > 0 ? pane.eventCals[0].id : ""

    // Route an event create to the right backend by calendar id.
    function addEventTo(calId, summary, ymd, hm, dur) {
        if (calId.indexOf("loc:") === 0)
            Local.addEvent(calId.slice(4), summary, ymd, hm || "", dur || 60)
        else
            CalDav.addEvent(calId, summary, ymd, hm || "", dur || 0)
    }

    // ── events + tasks by day ────────────────────────────────────────────────
    readonly property var events: pane._merge(CalDav.events, Local.events)
    readonly property var eventsByDay: {
        var hidden = CalPrefs.hidden, map = {}, evs = pane.events
        for (var i = 0; i < evs.length; i++) {
            var e = evs[i]
            if (hidden[e.cal] === true) continue
            var s = new Date(e.startMs), last = new Date(Math.max(e.startMs, e.endMs - 1))
            var d = new Date(s.getFullYear(), s.getMonth(), s.getDate())
            for (var n = 0; d <= last && n < 62; n++) {
                var k = pane.dayKey(d); if (!map[k]) map[k] = []
                map[k].push(e); d = new Date(d.getFullYear(), d.getMonth(), d.getDate() + 1)
            }
        }
        return map
    }
    readonly property var tasksByDay: {
        var map = {}, ts = Todo.tasks ?? []
        for (var i = 0; i < ts.length; i++) {
            if (ts[i].done || !ts[i].dueMs) continue
            var k = pane.dayKey(new Date(ts[i].dueMs)); if (!map[k]) map[k] = []
            map[k].push(ts[i])
        }
        return map
    }
    // Task dots are coloured by their todo project (falls back to accent).
    readonly property var projColor: {
        var m = {}, ps = Todo.projects ?? []
        for (var i = 0; i < ps.length; i++)
            m[ps[i].id] = (ps[i].color && ps[i].color !== "") ? ps[i].color : Theme.accent
        return m
    }
    function taskColor(t) { return pane.projColor[t.projectId] || Theme.accent }

    function eventsOn(d) {
        var l = (pane.eventsByDay[pane.dayKey(d)] ?? []).slice()
        l.sort((a, b) => ((b.allDay ? 1 : 0) - (a.allDay ? 1 : 0)) || (a.startMs - b.startMs))
        return l
    }
    function tasksOn(d) { return pane.tasksByDay[pane.dayKey(d)] ?? [] }
    readonly property var selEvents: pane.eventsOn(pane.selDay)
    readonly property var selTasks:  pane.tasksOn(pane.selDay)

    readonly property string addTaskTarget: {
        var ps = Todo.projects ?? []
        for (var j = 0; j < ps.length; j++) if (ps[j].writable) return ps[j].id
        return ""
    }
    function addFromText(text) {
        var t = text.trim(); if (t === "") return
        if (pane.eventCal !== "") {
            var m = t.match(/^(\d{1,2}):(\d{2})\s+(.+)$/)
            if (m) pane.addEventTo(pane.eventCal, m[3], pane.ymd(pane.selDay), ("0"+m[1]).slice(-2)+":"+m[2], 60)
            else   pane.addEventTo(pane.eventCal, t, pane.ymd(pane.selDay), "", 0)
        } else if (pane.addTaskTarget !== "") {
            Todo.addTask(pane.addTaskTarget, t, pane.ymd(pane.selDay), "")
        }
    }

    readonly property string title: {
        if (pane.calView === "year")  return "" + pane.viewYear
        if (pane.calView === "day")   return Qt.formatDate(pane.selDay, "dddd, MMMM d")
        if (pane.calView === "agenda") return "Agenda"
        if (pane.calView === "week") {
            var w = pane.weekDays
            return Qt.formatDate(w[0], "MMM d") + " – " + Qt.formatDate(w[6], "MMM d")
        }
        return Qt.formatDate(new Date(pane.viewYear, pane.viewMonth, 1), "MMMM yyyy")
    }

    // ── Toolbar ──────────────────────────────────────────────────────────────
    // Left edge follows the sidebar (not parent.left) — the sidebar now runs the
    // full height and connects with the window's topbar, so the toolbar starts
    // where the sidebar ends instead of sitting above/behind it.
    Item {
        id: toolbar
        enabled: !pane.modalOpen
        anchors { top: parent.top; left: sidebar.right; right: parent.right
                  topMargin: 12; leftMargin: 12; rightMargin: 12 }
        height: 34

        Text {
            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
            text: pane.title
            color: Theme.fgBright; font.pixelSize: 20; font.bold: true; font.family: Theme.fontFamily
        }
        Row {   // view switcher
            anchors.centerIn: parent
            spacing: 3
            Repeater {
                model: [{ v: "year", l: "Year" }, { v: "month", l: "Month" },
                        { v: "week", l: "Week" }, { v: "day", l: "Day" }, { v: "agenda", l: "Agenda" }]
                delegate: Rectangle {
                    required property var modelData
                    readonly property bool on: pane.calView === modelData.v
                    width: vlbl.implicitWidth + 22; height: 28; radius: 7
                    color: on ? Qt.alpha(Theme.accent, 0.35)
                         : vHov.containsMouse ? Theme.bgSecondary : "transparent"
                    Behavior on color { ColorAnimation { duration: 90 } }
                    Text {
                        id: vlbl; anchors.centerIn: parent; text: modelData.l
                        color: parent.on ? Theme.fgBright : Theme.fgMuted
                        font.pixelSize: 13; font.bold: parent.on; font.family: Theme.fontFamily
                    }
                    MouseArea { id: vHov; anchors.fill: parent; hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor; onClicked: pane.calView = modelData.v }
                }
            }
        }
        Row {   // prev · today · next
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            spacing: 4
            NavBtn { sym: "󰅁"; onTap: pane.shift(-1) }
            NavBtn { sym: "󰋙"; dim: pane.dayKey(pane.selDay) === pane.dayKey(pane.today); onTap: pane.goToday() }
            NavBtn { sym: "󰅂"; onTap: pane.shift(1) }
        }
    }

    // ── Sidebar (collapsible) ────────────────────────────────────────────────
    // Runs the full pane height — connects flush with the window's topbar
    // instead of starting below the toolbar row.
    // Immersive mode: the window insets the whole StackLayout by 30px so the top
    // peek-zone doesn't sit over interactive rows (see Main.qml). The sidebar is a
    // full-height panel that should stay flush with the window's top edge, so it
    // negates that inset — otherwise a 30px gap yawns above it when it peeks out.
    readonly property int _topInset: pane.immersive ? -30 : 0

    // Left-edge hover zone — peeks the sidebar back out while it's collapsed.
    Item {
        anchors { top: parent.top; left: parent.left; bottom: parent.bottom
                  topMargin: pane._topInset }
        width: 28; visible: !pane.sidebarOpen; z: 50
        HoverHandler { id: edgeHover }
    }

    Rectangle {
        id: sidebar
        enabled: !pane.modalOpen
        anchors { top: parent.top; left: parent.left; bottom: parent.bottom
                  topMargin: pane._topInset }
        width: (pane.sidebarOpen || pane.sidebarPeek) ? 236 : 0
        clip: true
        color: Theme.surface
        z: 60
        Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
        HoverHandler { id: sideHover }

        Rectangle { anchors { top: parent.top; bottom: parent.bottom; right: parent.right }
                    width: 1; color: Qt.alpha(Theme.boNormal, 0.5) }

        Text {
            id: sideHdr
            anchors { top: parent.top; left: parent.left; right: parent.right
                      topMargin: 16; leftMargin: 16; rightMargin: 16 }
            text: "CALENDARS"; color: Theme.fgMuted; font.pixelSize: 12; font.bold: true
            font.letterSpacing: 1; font.family: Theme.fontFamily
        }
        Flickable {
            anchors { top: sideHdr.bottom; left: parent.left; right: parent.right
                      bottom: parent.bottom; topMargin: 10; rightMargin: 1 }
            contentHeight: calCol.implicitHeight; clip: true
            boundsBehavior: Flickable.StopAtBounds
            Column {
                id: calCol
                width: parent.width
                Text {
                    visible: pane.displayCals.length === 0
                    anchors { left: parent.left; right: parent.right; leftMargin: 16; rightMargin: 16 }
                    text: "no event calendars"; wrapMode: Text.WordWrap
                    color: Theme.fgMuted; font.pixelSize: 13; font.family: Theme.fontFamily
                }
                // Grouped list: each named group gets a header; the ungrouped
                // section renders without one.
                Repeater {
                    model: pane.calGroups
                    delegate: Column {
                        required property var modelData
                        width: calCol.width
                        Text {
                            visible: modelData.name !== ""
                            anchors { left: parent.left; right: parent.right; leftMargin: 16; rightMargin: 16 }
                            topPadding: 12; bottomPadding: 4
                            text: modelData.name.toUpperCase(); elide: Text.ElideRight
                            color: Theme.fgMuted; font.pixelSize: 11; font.bold: true
                            font.letterSpacing: 0.8; font.family: Theme.fontFamily
                        }
                        Repeater {
                            model: modelData.cals
                            delegate: Rectangle {
                                id: calEntry
                                required property var modelData
                                readonly property string calId: calEntry.modelData.id
                                readonly property bool hidden: pane.calHidden(calEntry.calId)
                                readonly property string desc: pane.calDesc(calEntry.calId)
                                width: calCol.width
                                height: calEntry.desc !== "" ? 50 : 38
                                color: rowHH.hovered ? Theme.bgSecondary : "transparent"
                                Behavior on color { ColorAnimation { duration: 90 } }
                                // Row-level hover (visual) + background tap (open editor).
                                // Handlers, not a covering MouseArea, so the icon
                                // MouseAreas below still win their own clicks — a
                                // top-most MouseArea would steal them (z-order).
                                HoverHandler { id: rowHH; cursorShape: Qt.PointingHandCursor }
                                TapHandler { onTapped: calendarDialog.openEdit(calEntry.calId) }
                                Rectangle {
                                    id: dot
                                    anchors { left: parent.left; leftMargin: 16; verticalCenter: parent.verticalCenter }
                                    width: 14; height: 14; radius: 7
                                    color: pane.calColor(calEntry.calId)
                                    opacity: calEntry.hidden ? 0.35 : 1.0
                                }
                                Column {
                                    anchors { left: dot.right; leftMargin: 12; right: actions.left; rightMargin: 8
                                              verticalCenter: parent.verticalCenter }
                                    spacing: 1
                                    Text {
                                        width: parent.width; elide: Text.ElideRight
                                        text: pane.calName(calEntry.calId)
                                        color: calEntry.hidden ? Theme.fgMuted : Theme.fgPrimary
                                        font.pixelSize: 14; font.family: Theme.fontFamily
                                    }
                                    Text {
                                        visible: calEntry.desc !== ""
                                        width: parent.width; elide: Text.ElideRight; text: calEntry.desc
                                        color: Theme.fgMuted; font.pixelSize: 11; font.family: Theme.fontFamily
                                    }
                                }
                                Row {
                                    id: actions
                                    anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                                    spacing: 6
                                    Text {   // edit — opens the full calendar editor
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "󰏫"; opacity: (rowHH.hovered || editHov.containsMouse) ? 1.0 : 0.0
                                        color: editHov.containsMouse ? Theme.fgBright : Theme.fgMuted
                                        font.pixelSize: 15; font.family: Theme.fontFamily
                                        Behavior on opacity { NumberAnimation { duration: 90 } }
                                        MouseArea { id: editHov; anchors.fill: parent; anchors.margins: -6
                                            hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                            onClicked: calendarDialog.openEdit(calEntry.calId) }
                                    }
                                    Text {   // visibility toggle
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: calEntry.hidden ? "󰈉" : "󰈈"
                                        color: eyeHov.containsMouse ? Theme.fgBright
                                             : calEntry.hidden ? Theme.fgMuted : Theme.fgPrimary
                                        font.pixelSize: 15; font.family: Theme.fontFamily
                                        MouseArea { id: eyeHov; anchors.fill: parent; anchors.margins: -6
                                            hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                            onClicked: CalPrefs.toggleHidden(calEntry.calId) }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ── Content area ─────────────────────────────────────────────────────────
    Item {
        id: content
        enabled: !pane.modalOpen
        anchors { top: toolbar.bottom; left: sidebar.right; right: parent.right
                  bottom: parent.bottom; topMargin: 10; leftMargin: 16; rightMargin: 16; bottomMargin: 14 }

        // Split ratio in pixels for the resizable views. Week/day get the
        // TimeGrid below instead — a real calendar grid needs its full height,
        // not a squeezed top strip + a redundant list underneath.
        readonly property bool split: pane.calView === "month"
        readonly property int gridH: content.split
            ? Math.round(Math.max(0.3, Math.min(0.8, pane.splitFrac)) * (content.height - 14))
            : 0

        // MONTH ---------------------------------------------------------------
        Column {
            visible: pane.calView === "month"
            anchors { top: parent.top; left: parent.left; right: parent.right }
            height: content.gridH
            spacing: 6
            Row {
                spacing: 5
                Repeater {
                    model: 7
                    delegate: Text {
                        required property int index
                        width: monthGrid.cellW; horizontalAlignment: Text.AlignHCenter
                        text: Qt.formatDate(new Date(2026, 6, 5 + pane.firstDow + index), "ddd")
                        color: Theme.fgMuted; font.pixelSize: 12; font.bold: true; font.family: Theme.fontFamily
                    }
                }
            }
            Grid {
                id: monthGrid
                columns: 7; spacing: 5
                readonly property int cellW: Math.floor((parent.width - 6 * 5) / 7)
                readonly property int rows: Math.ceil(pane.gridDays.length / 7)
                readonly property int cellH: Math.max(30, Math.floor((content.gridH - 18 - 6 - (monthGrid.rows - 1) * 5) / monthGrid.rows))
                Repeater {
                    model: pane.gridDays
                    delegate: DayCell { required property var modelData; d: modelData; w: monthGrid.cellW; h: monthGrid.cellH }
                }
            }
        }

        // WEEK / DAY ------------------------------------------------------------
        // A real calendar grid: hour rows down the side, events as time-
        // positioned blocks (see the TimeGrid component below) — not a flat
        // list of full-width pills stacked under the date.
        TimeGrid {
            visible: pane.calView === "week" || pane.calView === "day"
            anchors.fill: parent
            days: pane.calView === "day" ? [pane.selDay] : pane.weekDays
        }

        // Divider (month) --------------------------------------------------------
        Rectangle {
            id: divider
            visible: content.split
            anchors { left: parent.left; right: parent.right }
            y: content.gridH + 4
            height: 6; radius: 3
            color: divArea.containsMouse || divArea.pressed ? Theme.accent : Qt.alpha(Theme.boNormal, 0.5)
            Behavior on color { ColorAnimation { duration: 90 } }
            MouseArea {
                id: divArea
                anchors.fill: parent; anchors.margins: -4
                hoverEnabled: true; cursorShape: Qt.SizeVerCursor
                onPositionChanged: if (pressed) {
                    var p = mapToItem(content, divArea.mouseX, divArea.mouseY).y
                    pane.splitFrac = Math.max(0.3, Math.min(0.8, p / (content.height - 14)))
                }
            }
        }

        // DETAIL / AGENDA --------------------------------------------------------
        // Month's selected-day agenda strip underneath the grid, and Agenda
        // view's own full-height list. Week/day now render via TimeGrid instead.
        DetailPane {
            id: detail
            visible: pane.calView === "month" || pane.calView === "agenda"
            x: 0
            width: content.width
            y: content.split ? content.gridH + 14 : 0
            height: content.split ? (content.height - content.gridH - 14) : content.height
            mode: pane.calView === "agenda" ? "agenda" : "day"
        }

        // YEAR ----------------------------------------------------------------
        Flickable {
            visible: pane.calView === "year"
            anchors.fill: parent
            contentHeight: yearFlow.implicitHeight; clip: true
            boundsBehavior: Flickable.StopAtBounds
            Grid {
                id: yearFlow
                width: parent.width
                columns: Math.max(1, Math.floor(width / 250))
                columnSpacing: 14; rowSpacing: 14
                Repeater {
                    model: 12
                    delegate: MiniMonth { required property int index; monthIndex: index }
                }
            }
        }
    }

    // ── Big add button (opens the Termin/Task dialog for the selected day) ────
    Rectangle {
        id: fab
        enabled: !pane.modalOpen
        anchors { right: parent.right; bottom: parent.bottom; margins: 20 }
        width: 56; height: 56; radius: 28
        color: fabHov.containsMouse ? Theme.bgHover : Theme.accent
        z: 300
        Behavior on color { ColorAnimation { duration: 120 } }
        Text { anchors.centerIn: parent; text: "󰐕"; color: Theme.fgBright
               font.pixelSize: 26; font.family: Theme.fontFamily }
        MouseArea { id: fabHov; anchors.fill: parent; hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: eventDialog.openNew(pane.ymd(pane.selDay), pane.eventCal) }
    }

    EventDialog { id: eventDialog; anchors.fill: parent }
    CalendarDialog { id: calendarDialog; anchors.fill: parent }

    // ── Day cell (month grid) ────────────────────────────────────────────────
    component DayCell: Rectangle {
        id: cell
        property var d
        property int w: 40
        property int h: 44
        readonly property int  k:       pane.dayKey(d)
        readonly property bool inMonth: pane.sameMonth(d)
        readonly property bool isToday: k === pane.dayKey(pane.today)
        readonly property bool isSel:   k === pane.dayKey(pane.selDay)
        readonly property var  evs:     pane.eventsByDay[k] ?? []
        readonly property var  dues:    pane.tasksByDay[k] ?? []
        width: w; height: h; radius: 9
        color: isSel ? Qt.alpha(Theme.accent, 0.45)
             : cellHov.containsMouse ? Theme.bgSecondary : Theme.bgPrimary
        border.width: isToday ? 1 : 0; border.color: Theme.accent
        Behavior on color { ColorAnimation { duration: 90 } }
        Text {
            anchors { top: parent.top; left: parent.left; topMargin: 6; leftMargin: 9 }
            text: cell.d.getDate()
            color: cell.isSel ? Theme.fgBright : cell.inMonth ? (cell.isToday ? Theme.accent : Theme.fgPrimary) : Theme.fgMuted
            font.pixelSize: 14; font.family: Theme.fontFamily; font.bold: cell.isToday || cell.isSel
            opacity: cell.inMonth ? 1.0 : 0.4
        }
        // Events as blocks (calendar colour bar with the title) — like a normal
        // month view. As many as fit under the date; the rest fold into "+N".
        Column {
            id: evBlocks
            anchors { top: parent.top; left: parent.left; right: parent.right
                      topMargin: 26; leftMargin: 5; rightMargin: 5 }
            spacing: 2
            readonly property int maxShow: Math.max(0, Math.floor((cell.h - 26 - 12) / 16))
            Repeater {
                model: Math.min(evBlocks.maxShow, cell.evs.length)
                delegate: Rectangle {
                    required property int index
                    width: parent.width; height: 14; radius: 3
                    color: pane.calColor(cell.evs[index].cal)
                    Text {
                        anchors { left: parent.left; right: parent.right; leftMargin: 5; rightMargin: 4
                                  verticalCenter: parent.verticalCenter }
                        elide: Text.ElideRight; text: cell.evs[index].summary ?? ""
                        color: "#ffffff"; font.pixelSize: 10; font.family: Theme.fontFamily
                    }
                }
            }
            Text {
                visible: cell.evs.length > evBlocks.maxShow
                text: "+" + (cell.evs.length - evBlocks.maxShow)
                color: Theme.fgMuted; font.pixelSize: 10; font.family: Theme.fontFamily
                leftPadding: 2
            }
        }
        // Tasks due this day → project-coloured dots, centred at the bottom edge.
        Row {
            anchors { bottom: parent.bottom; horizontalCenter: parent.horizontalCenter; bottomMargin: 6 }
            spacing: 4; height: 6
            Repeater {
                model: Math.min(6, cell.dues.length)
                delegate: Rectangle {
                    required property int index
                    width: 6; height: 6; radius: 3
                    color: pane.taskColor(cell.dues[index])
                }
            }
        }
        MouseArea { id: cellHov; anchors.fill: parent; hoverEnabled: true
            onClicked: pane.selDay = new Date(cell.d)
            onDoubleClicked: { pane.selDay = new Date(cell.d); eventDialog.openNew(pane.ymd(cell.d), pane.eventCal) } }
    }

    // ── Mini-month (year view) ───────────────────────────────────────────────
    component MiniMonth: Column {
        id: mm
        property int monthIndex: 0
        width: (yearFlow.width - (yearFlow.columns - 1) * 14) / yearFlow.columns
        spacing: 4
        readonly property var days: {
            var first = new Date(pane.viewYear, mm.monthIndex, 1)
            var off = (first.getDay() - pane.firstDow + 7) % 7
            var dim = new Date(pane.viewYear, mm.monthIndex + 1, 0).getDate()
            var cells = Math.ceil((off + dim) / 7) * 7, out = []
            for (var i = 0; i < cells; i++) out.push(new Date(pane.viewYear, mm.monthIndex, 1 - off + i))
            return out
        }
        Text {
            text: Qt.formatDate(new Date(pane.viewYear, mm.monthIndex, 1), "MMMM")
            color: Theme.fgBright; font.pixelSize: 14; font.bold: true; font.family: Theme.fontFamily
            MouseArea { anchors.fill: parent; anchors.margins: -3; cursorShape: Qt.PointingHandCursor
                onClicked: { pane.viewMonth = mm.monthIndex; pane.calView = "month" } }
        }
        Grid {
            columns: 7; columnSpacing: 2; rowSpacing: 2
            readonly property int cw: Math.floor((mm.width - 6 * 2) / 7)
            Repeater {
                model: mm.days
                delegate: Rectangle {
                    required property var modelData
                    readonly property bool inM: modelData.getMonth() === mm.monthIndex
                    readonly property bool today: pane.dayKey(modelData) === pane.dayKey(pane.today)
                    readonly property bool has: (pane.tasksByDay[pane.dayKey(modelData)] || pane.eventsByDay[pane.dayKey(modelData)]) !== undefined
                    width: parent.cw; height: parent.cw; radius: parent.cw / 2
                    color: today ? Qt.alpha(Theme.accent, 0.5) : "transparent"
                    Text {
                        anchors.centerIn: parent; text: modelData.getDate()
                        color: today ? Theme.fgBright : inM ? (has ? Theme.accent : Theme.fgPrimary) : Theme.fgMuted
                        font.pixelSize: 10; font.family: Theme.fontFamily; opacity: inM ? 1 : 0.35
                        font.bold: has || today
                    }
                    MouseArea { anchors.fill: parent; onClicked: { pane.setSel(new Date(modelData)); pane.calView = "day" } }
                }
            }
        }
    }

    // ── Time grid (week/day) ────────────────────────────────────────────────
    // Real calendar layout: an hour gutter + one column per day, events drawn
    // as blocks positioned/sized by their actual start/end time (overlapping
    // events pack into side-by-side lanes) — replaces the old flat list of
    // full-width event pills, which read as "not a real calendar" (user).
    component TimeGrid: Item {
        id: grid
        property var days: []                  // 1 (day) or 7 (week) dates
        readonly property int hourH: 56
        readonly property int gutterW: 46
        // Visible hour window (Settings › Calendar › Day grid). Clamped so the
        // range is always non-empty even if the stored prefs are odd.
        readonly property int startHour: Math.max(0, Math.min(23, Settings.dayStartHour))
        readonly property int endHour: Math.max(grid.startHour + 1, Math.min(24, Settings.dayEndHour))
        readonly property int hours: grid.endHour - grid.startHour
        readonly property real dayW: (grid.width - grid.gutterW) / Math.max(1, grid.days.length)
        // Event blocks sit inset from BOTH column edges by evPad so they never
        // ride over the day-separator line. The separator is a sepW-wide bar at
        // x:0 of each interior column, so on those columns the block is pushed a
        // further sepW to the right — otherwise the line eats the left gap and
        // the block looks tighter on the left than on the right (user feedback).
        // laneGap is the air between two side-by-side (overlapping) events.
        readonly property int evPad: 5
        readonly property int laneGap: 3
        readonly property int sepW: 2

        // Greedy lane-packing: events that overlap in time sit side by side
        // instead of stacking on top of each other.
        function layout(d) {
            var dayStart = new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime()
            var dayEnd = dayStart + 86400000
            var items = pane.eventsOn(d).filter(e => !e.allDay).map(e => ({
                ev: e,
                start: Math.max(e.startMs, dayStart),
                end: Math.min(Math.max(e.endMs, e.startMs + 15 * 60000), dayEnd),
            })).sort((a, b) => a.start - b.start)

            var laneEnd = [], placed = []       // laneEnd[i] = end time of that lane's last event
            for (var i = 0; i < items.length; i++) {
                var it = items[i], lane = 0
                while (lane < laneEnd.length && laneEnd[lane] > it.start) lane++
                laneEnd[lane] = it.end
                placed.push({ it: it, lane: lane })
            }
            var lanes = laneEnd.length || 1
            return placed.map(p => ({
                ev: p.it.ev,
                y: ((p.it.start - dayStart) / 60000 / 60 - grid.startHour) * grid.hourH,
                height: Math.max(20, (p.it.end - p.it.start) / 60000 / 60 * grid.hourH),
                laneX: p.lane / lanes,
                laneW: 1 / lanes,
            }))
        }

        readonly property int allDayMax: {
            var m = 0
            for (var i = 0; i < grid.days.length; i++)
                m = Math.max(m, pane.eventsOn(grid.days[i]).filter(e => e.allDay).length)
            return m
        }

        // All-day strip — fixed above the scrollable hour grid (these have no
        // time slot, so they don't belong inside it).
        Row {
            id: allDayRow
            visible: grid.allDayMax > 0
            anchors { top: parent.top; left: parent.left; right: parent.right; leftMargin: grid.gutterW }
            height: grid.allDayMax * 20 + 6
            Repeater {
                model: grid.days
                delegate: Column {
                    required property var modelData
                    width: grid.dayW; spacing: 2; topPadding: 4
                    Repeater {
                        model: pane.eventsOn(modelData).filter(e => e.allDay)
                        delegate: Rectangle {
                            required property var modelData
                            // inset evenly from both edges so the bar clears the
                            // day-separator lines (matches the timed blocks)
                            x: grid.evPad; width: grid.dayW - 2 * grid.evPad
                            height: 16; radius: 4
                            color: Qt.alpha(pane.calColor(modelData.cal), 0.5)
                            Text { anchors { left: parent.left; right: parent.right; leftMargin: 5; rightMargin: 4
                                             verticalCenter: parent.verticalCenter }
                                   elide: Text.ElideRight; text: modelData.summary
                                   color: Theme.fgPrimary; font.pixelSize: 10; font.family: Theme.fontFamily }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                        onClicked: eventDialog.openEdit(modelData) }
                        }
                    }
                }
            }
        }

        // Day headers — week only (day view's toolbar title already shows the date).
        Row {
            id: dayHeader
            visible: grid.days.length > 1
            anchors { top: allDayRow.visible ? allDayRow.bottom : parent.top; left: parent.left; right: parent.right
                      leftMargin: grid.gutterW }
            height: 22
            Repeater {
                model: grid.days
                delegate: Text {
                    required property var modelData
                    width: grid.dayW; horizontalAlignment: Text.AlignHCenter
                    text: Qt.formatDate(modelData, "ddd d")
                    color: pane.dayKey(modelData) === pane.dayKey(pane.today) ? Theme.accent : Theme.fgMuted
                    font.pixelSize: 12; font.bold: true; font.family: Theme.fontFamily
                }
            }
        }

        Timer { id: nowTick; property int tick: 0; interval: 60000; running: true; repeat: true
                onTriggered: tick++ }

        Flickable {
            id: flick
            anchors { top: dayHeader.visible ? dayHeader.bottom : (allDayRow.visible ? allDayRow.bottom : parent.top)
                      left: parent.left; right: parent.right; bottom: parent.bottom; topMargin: 4 }
            contentHeight: grid.hourH * grid.hours
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            Component.onCompleted: {
                // Land with "now" in view (a couple hours of lead-in above it)
                // instead of always opening at the top — the whole point of the
                // now-line is that it's visible without having to scroll first.
                var n = new Date()
                var nowMin = n.getHours() * 60 + n.getMinutes()
                contentY = Math.max(0, (nowMin / 60 - grid.startHour - 2) * grid.hourH)
            }

            Column {   // hour gutter labels, aligned to each hour's gridline
                x: 0; width: grid.gutterW
                Repeater {
                    model: grid.hours
                    delegate: Item {
                        required property int index
                        readonly property int hh: index + grid.startHour
                        width: grid.gutterW; height: grid.hourH
                        Text {
                            visible: index > 0
                            anchors { top: parent.top; right: parent.right; rightMargin: 6; topMargin: -7 }
                            text: (hh < 10 ? "0" : "") + hh + ":00"
                            color: Theme.fgMuted; font.pixelSize: 10; font.family: Theme.fontFamily
                        }
                    }
                }
            }

            Row {
                x: grid.gutterW
                Repeater {
                    model: grid.days
                    delegate: Item {
                        id: dayCol
                        required property var modelData
                        required property int index
                        width: grid.dayW; height: grid.hourH * grid.hours

                        Repeater {          // hour gridlines
                            model: grid.hours
                            delegate: Rectangle {
                                required property int index
                                y: index * grid.hourH; width: dayCol.width; height: 1
                                color: Qt.alpha(Theme.boNormal, (index + grid.startHour) % 6 === 0 ? 0.45 : 0.22)
                            }
                        }
                        Rectangle {         // day separator — stronger than the hour
                            // gridlines so columns read as distinct days at a
                            // glance instead of blurring together (user feedback)
                            visible: dayCol.index > 0
                            x: 0; width: grid.sepW; height: parent.height
                            color: Qt.alpha(Theme.boNormal, 0.85)
                        }

                        // Empty-slot double-click → new event (mirrors the month
                        // view's double-click-to-create). z:1 so event blocks
                        // (z:2 below) still win the click over this.
                        MouseArea {
                            anchors.fill: parent; z: 1
                            onDoubleClicked: {
                                pane.selDay = new Date(dayCol.modelData)
                                eventDialog.openNew(pane.ymd(dayCol.modelData), pane.eventCal)
                            }
                        }

                        Repeater {
                            model: grid.layout(dayCol.modelData)
                            delegate: Rectangle {
                                id: evBlock
                                required property var modelData
                                readonly property bool hasImg: Settings.showEventImages && (modelData.ev.image || "") !== ""
                                // Only treat as an image block once the picture actually
                                // LOADS — a stale/missing path (e.g. an old cache file from
                                // a previous name) must not suppress the past-fade or draw a
                                // frame for a picture that never shows.
                                readonly property bool imgOk: evBlock.hasImg && evImg.status === Image.Ready
                                readonly property bool isPast: { void nowTick.tick
                                                                 return modelData.ev.endMs < Date.now() }
                                // clear the interior column's separator so the gap
                                // to the line matches on both sides (see evPad note)
                                readonly property int leftSep: dayCol.index > 0 ? grid.sepW : 0
                                readonly property real usable: dayCol.width - leftSep - 2 * grid.evPad
                                x: leftSep + grid.evPad + modelData.laneX * usable
                                y: modelData.y
                                z: 2
                                // even inset on both column edges; a lane gap only
                                // between neighbours, never hanging off either edge
                                width: modelData.laneW * usable
                                       - (modelData.laneX + modelData.laneW < 0.999 ? grid.laneGap : 0)
                                height: modelData.height
                                radius: 5; clip: true
                                // No calendar-colour fill BEHIND a picture: opacity is
                                // applied per-item (not as a group), so a faded image
                                // goes semi-transparent and the fill would bleed through
                                // and tint it. The image's calendar identity comes from
                                // the frame instead. Non-image blocks keep the fill.
                                color: evBlock.imgOk ? "transparent" : pane.calColor(modelData.ev.cal)
                                border.width: 1; border.color: Qt.darker(pane.calColor(modelData.ev.cal), 1.3)
                                // Past events fade — image blocks included. Safe now
                                // that the picture is always rounded via the OpacityMask
                                // (group opacity no longer changes the corners), so a
                                // faded image block still reads as the same shape.
                                opacity: evBlock.isPast ? Settings.pastEventOpacity : 1.0
                                Behavior on opacity { NumberAnimation { duration: 300 } }
                                // Event picture (Settings › Calendar › Event images in
                                // Week/Day), rounded to the block corners with an
                                // OpacityMask — clip alone stays rectangular, which is
                                // why the un-faded block had sharp corners. A top scrim
                                // keeps the title readable.
                                Item {
                                    id: evImgGroup
                                    visible: evBlock.hasImg     // keep mounted so the Image loads (→ imgOk)
                                    anchors.fill: parent
                                    layer.enabled: evBlock.imgOk
                                    layer.effect: OpacityMask {
                                        maskSource: Rectangle { width: evImgGroup.width; height: evImgGroup.height
                                                                radius: evBlock.radius }
                                    }
                                    Image {
                                        id: evImg
                                        anchors.fill: parent
                                        source: evBlock.hasImg ? "file://" + evBlock.modelData.ev.image : ""
                                        fillMode: Image.PreserveAspectCrop; asynchronous: true; cache: true
                                    }
                                    Rectangle {
                                        visible: evBlock.imgOk
                                        anchors.fill: parent
                                        gradient: Gradient {
                                            GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0.58) }
                                            GradientStop { position: 0.6; color: Qt.rgba(0, 0, 0, 0.16) }
                                            GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.05) }
                                        }
                                    }
                                }
                                // The image covers the block's own border, so draw a
                                // calendar-colour frame on top → an image block still
                                // reads as belonging to its calendar. Only when the
                                // image actually loaded.
                                Rectangle {
                                    visible: evBlock.imgOk
                                    anchors.fill: parent
                                    color: "transparent"
                                    radius: evBlock.radius
                                    border.width: 2
                                    border.color: pane.calColor(evBlock.modelData.ev.cal)
                                }
                                Column {
                                    anchors { fill: parent; margins: 5 }
                                    spacing: 1
                                    // Title line: event icon (left) · summary · recurring glyph (right).
                                    Item {
                                        width: parent.width; height: titleT.implicitHeight
                                        Text {
                                            id: recurT
                                            visible: modelData.ev.recurring === true
                                            anchors { right: parent.right; verticalCenter: titleT.verticalCenter }
                                            text: "󰑖"; color: Qt.alpha("#ffffff", 0.9)
                                            font.pixelSize: 15; font.family: Theme.fontFamily
                                        }
                                        Text {
                                            id: iconT
                                            visible: (modelData.ev.icon || "") !== ""
                                            anchors { left: parent.left; verticalCenter: titleT.verticalCenter }
                                            text: modelData.ev.icon || ""
                                            font.pixelSize: 16; font.family: Theme.fontFamily
                                        }
                                        Text {
                                            id: titleT
                                            anchors { left: iconT.visible ? iconT.right : parent.left
                                                      leftMargin: iconT.visible ? 4 : 0
                                                      right: recurT.visible ? recurT.left : parent.right
                                                      rightMargin: recurT.visible ? 4 : 0 }
                                            elide: Text.ElideRight
                                            text: modelData.ev.summary ?? ""
                                            // White, not Theme — matches the month view's
                                            // blocks (also solid calColor fill); a
                                            // theme fg can't guarantee contrast against
                                            // an arbitrary, possibly light, cal colour.
                                            color: "#ffffff"; font.pixelSize: 15; font.bold: true
                                            font.family: Theme.fontFamily
                                        }
                                    }
                                    Text {
                                        width: parent.width; elide: Text.ElideRight
                                        visible: modelData.height > 46
                                        text: Qt.formatTime(new Date(modelData.ev.startMs), Settings.timeFmt) + "–"
                                              + Qt.formatTime(new Date(modelData.ev.endMs), Settings.timeFmt)
                                        color: Qt.alpha("#ffffff", 0.9); font.pixelSize: 13; font.family: Theme.fontFamily
                                    }
                                }
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                            onClicked: eventDialog.openEdit(modelData.ev) }
                            }
                        }

                        // "Now" indicator — today's column only. A dark casing
                        // under the bright core keeps it readable over BOTH the
                        // dark grid AND arbitrarily-coloured event blocks: a
                        // single hue (fgUrgent) can blend into a same-hue block
                        // (e.g. the pink line over a purple event), so the dark
                        // outline is what guarantees separation everywhere.
                        Item {
                            id: nowLine
                            visible: pane.dayKey(dayCol.modelData) === pane.dayKey(pane.today)
                            readonly property real nowMin: {
                                void nowTick.tick
                                var n = new Date()
                                return n.getHours() * 60 + n.getMinutes()
                            }
                            x: 0; width: parent.width; height: 10; z: 50
                            y: (nowLine.nowMin / 60 - grid.startHour) * grid.hourH - height / 2
                            Rectangle {   // dark casing — separates from any bg hue
                                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
                                height: 6; radius: 3; color: Qt.rgba(0, 0, 0, 0.65)
                            }
                            Rectangle {   // bright near-white core — high luminance
                                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
                                // fgBright (≈white) beats fgUrgent here: luminance,
                                // not hue, is what contrasts against BOTH the dark
                                // grid and a same-hue coloured block.
                                height: 3; color: Theme.fgBright
                            }
                            Rectangle {   // colored "now" handle dot with a dark ring
                                anchors.verticalCenter: parent.verticalCenter; x: -6
                                width: 13; height: 13; radius: 6.5; color: Theme.fgUrgent
                                border.width: 2; border.color: Qt.rgba(0, 0, 0, 0.65)
                            }
                        }
                    }
                }
            }
        }
    }

    // ── Detail pane (day agenda / agenda list) ───────────────────────────────
    component DetailPane: Item {
        id: dp
        property string mode: "day"     // "day" | "agenda"

        // chronological agenda: next 60 days of events + due tasks
        readonly property var agendaItems: {
            if (dp.mode !== "agenda") return []
            var out = [], start = new Date(new Date().setHours(0,0,0,0))
            for (var i = 0; i < 60; i++) {
                var day = pane.addDays(start, i), k = pane.dayKey(day)
                var evs = pane.eventsOn(day), tks = pane.tasksOn(day)
                if (evs.length === 0 && tks.length === 0) continue
                out.push({ header: true, day: day })
                for (var e = 0; e < evs.length; e++) out.push({ header: false, ev: evs[e] })
                for (var t = 0; t < tks.length; t++) out.push({ header: false, task: tks[t] })
            }
            return out
        }

        readonly property int hpad: 6      // horizontal breathing room for the rows

        Text {
            id: dTitle
            visible: dp.mode === "day"
            anchors { top: parent.top; left: parent.left; leftMargin: dp.hpad }
            text: Qt.formatDate(pane.selDay, "dddd, MMM d")
            color: Theme.fgMuted; font.pixelSize: 15; font.bold: true
            font.letterSpacing: 0.5; font.family: Theme.fontFamily
        }

        Flickable {
            anchors { top: dp.mode === "day" ? dTitle.bottom : parent.top; topMargin: dp.mode === "day" ? 10 : 0
                      left: parent.left; right: parent.right; bottom: parent.bottom
                      leftMargin: dp.hpad; rightMargin: dp.hpad }
            contentHeight: aCol.implicitHeight; clip: true
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id: aCol
                width: parent.width; spacing: 4

                // DAY mode
                Repeater {
                    model: dp.mode === "day" ? pane.selEvents : []
                    delegate: EventRow { required property var modelData; ev: modelData }
                }
                Text {
                    visible: dp.mode === "day" && pane.selTasks.length > 0
                    text: "DUE"; topPadding: 6; color: Theme.fgMuted; font.pixelSize: 12; font.bold: true
                    font.letterSpacing: 0.5; font.family: Theme.fontFamily
                }
                Repeater {
                    model: dp.mode === "day" ? pane.selTasks : []
                    delegate: TaskDue { required property var modelData; task: modelData }
                }
                Text {
                    visible: dp.mode === "day" && pane.selEvents.length === 0 && pane.selTasks.length === 0
                    text: "nothing scheduled"; color: Theme.fgMuted
                    font.pixelSize: 13; font.family: Theme.fontFamily
                }

                // AGENDA mode
                Repeater {
                    model: dp.mode === "agenda" ? dp.agendaItems : []
                    delegate: Item {
                        required property var modelData
                        readonly property bool isHdr: modelData.header === true
                        readonly property bool isEv:  !isHdr && modelData.ev !== undefined
                        width: aCol.width
                        height: isHdr ? 30 : (isEv ? 44 : 38)
                        Text {
                            visible: parent.isHdr
                            anchors { left: parent.left; bottom: parent.bottom; bottomMargin: 4 }
                            text: parent.isHdr ? Qt.formatDate(modelData.day, "ddd, MMM d") : ""
                            color: (parent.isHdr && pane.dayKey(modelData.day) === pane.dayKey(pane.today)) ? Theme.accent : Theme.fgMuted
                            font.pixelSize: 12; font.bold: true; font.letterSpacing: 0.5; font.family: Theme.fontFamily
                        }
                        EventRow { anchors.fill: parent; visible: parent.isEv; ev: modelData.ev ?? ({}) }
                        TaskDue  { anchors.fill: parent; visible: !parent.isHdr && !parent.isEv; task: modelData.task ?? ({}) }
                    }
                }
                Text {
                    visible: dp.mode === "agenda" && dp.agendaItems.length === 0
                    text: "nothing coming up"; color: Theme.fgMuted
                    font.pixelSize: 13; font.family: Theme.fontFamily
                }
            }
        }
    }

    // ── shared rows ──────────────────────────────────────────────────────────
    component EventRow: Rectangle {
        property var ev: ({})
        width: parent ? parent.width : 0; height: 44; radius: 8
        color: evHov.containsMouse ? Theme.bgSecondary : Theme.bgElement
        Behavior on color { ColorAnimation { duration: 90 } }
        MouseArea { id: evHov; anchors.fill: parent; hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor; onClicked: eventDialog.openEdit(ev) }
        Rectangle { anchors { left: parent.left; leftMargin: 7; verticalCenter: parent.verticalCenter }
                    width: 3; height: parent.height - 16; radius: 1.5; color: pane.calColor(ev.cal) }
        Column {
            anchors { left: parent.left; leftMargin: 18; right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
            spacing: 1
            Text { width: parent.width; elide: Text.ElideRight
                   text: (ev.icon ? ev.icon + " " : "") + (ev.summary ?? "") + (ev.recurring ? "  󰑖" : "")
                   color: Theme.fgPrimary; font.pixelSize: 15; font.family: Theme.fontFamily }
            Text { width: parent.width; elide: Text.ElideRight
                   text: (ev.allDay ? "all day" : Qt.formatTime(new Date(ev.startMs), Settings.timeFmt) + " – " + Qt.formatTime(new Date(ev.endMs), Settings.timeFmt))
                         + (ev.location ? "   󰍎 " + ev.location : "")
                   color: Theme.fgMuted; font.pixelSize: 12; font.family: Theme.fontFamily }
        }
    }
    component TaskDue: Rectangle {
        property var task: ({})
        width: parent ? parent.width : 0; height: 38; radius: 8; color: Theme.bgElement
        Rectangle {
            anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
            width: 16; height: 16; radius: 8; color: "transparent"
            border.width: 1; border.color: dueChk.containsMouse ? Theme.accent : Theme.fgMuted
            Text { anchors.centerIn: parent; visible: dueChk.containsMouse; text: "󰄬"
                   color: Theme.fgMuted; font.pixelSize: 11; font.family: Theme.fontFamily }
            MouseArea { id: dueChk; anchors.fill: parent; anchors.margins: -5; hoverEnabled: true
                        onClicked: Todo.toggleTask(task) }
        }
        Text {
            anchors { left: parent.left; leftMargin: 36; right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
            elide: Text.ElideRight; text: (task.title ?? "") + (task.recurring ? "  󰑖" : "")
            color: Theme.fgPrimary; font.pixelSize: 15; font.family: Theme.fontFamily
        }
    }
}
