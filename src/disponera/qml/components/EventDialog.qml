import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import Qt5Compat.GraphicalEffects

// Calendar event viewer + editor. Clicking an event opens the DETAIL view first
// (read-only, Markdown description, image); an Edit button flips to the form.
// A tinted hero (coloured by the event's calendar) carries the icon + title;
// the middle scrolls as a stack of grouped, leading-icon cards. openNew(ymd,
// calId) opens straight in edit mode.
//
// Calendar features beyond a plain form: multi-day events (a separate END date —
// the backend derives DTEND from durMin, so spanning days needs no backend
// change), a live duration read-out with quick-set chips, and Today/Tomorrow
// date shortcuts.
Item {
    id: dlg
    property bool open: false
    property string mode: "detail"          // "detail" | "edit"
    property var event: ({})
    property bool isNew: true
    property string selCal: ""
    property bool selAllDay: false
    property string selDate: ""
    property string selEndDate: ""
    property string selStart: "09:00"
    property string selEnd: "10:00"
    property var selCats: []
    property var selAtt: []
    property string selIcon: ""
    property string selImage: ""
    property bool confirmDelete: false
    visible: open
    z: 500

    readonly property bool isLocal: String(dlg.selCal).indexOf("loc:") === 0
    readonly property bool recurring: dlg.event.recurring === true && !dlg.isNew
    readonly property var iconChoices: [
        "", "📅", "💼", "🎓", "🎂", "✈️", "❤️", "🏥", "📞", "🍽️", "🏃", "🎵", "🛒", "🎉", "☕", "🔔"]

    // push-loop merge — Array.concat on a QVariantList sequence wrapper is O(n²)
    // (see CalendarPane._merge); indexed access is O(1).
    function _merge(a, b) {
        var out = [], i; a = a ?? []; b = b ?? []
        for (i = 0; i < a.length; i++) out.push(a[i])
        for (i = 0; i < b.length; i++) out.push(b[i])
        return out
    }
    readonly property var calOptions: dlg._merge(CalDav.calendars, Local.calendars)
        .filter(c => c.vevent && c.writable)
        .map(c => ({ key: c.id, label: dlg._calName(c.id), color: dlg._calColor(c.id) }))
    // Display name honours the local rename override (CalPrefs) over the
    // calendar's own name, so a relabelled calendar reads consistently here too.
    function _calName(id) {
        if (CalPrefs.names && CalPrefs.names[id]) return CalPrefs.names[id]
        var cs = dlg._merge(CalDav.calendars, Local.calendars)
        for (var i = 0; i < cs.length; i++) if (cs[i].id === id) return cs[i].name || "calendar"
        return "calendar"
    }
    function _calColor(id) {
        if (CalPrefs.colors && CalPrefs.colors[id]) return CalPrefs.colors[id]
        var cs = dlg._merge(CalDav.calendars, Local.calendars)
        for (var i = 0; i < cs.length; i++) if (cs[i].id === id && cs[i].color) return cs[i].color
        return Theme.accent
    }

    function _fmtDate(ms) {
        var d = new Date(ms); function p(n){return (n<10?"0":"")+n}
        return d.getFullYear()+"-"+p(d.getMonth()+1)+"-"+p(d.getDate())
    }
    function _fmtTime(ms) { return Qt.formatDateTime(new Date(ms), Settings.timeFmt) }
    function _dtMs(ymd, hm) {
        var dm = /^(\d{4})-(\d{2})-(\d{2})$/.exec(ymd || "")
        if (!dm) return Date.now()
        var tm = /^(\d{1,2}):(\d{2})$/.exec(hm || "00:00")
        var h = tm ? parseInt(tm[1]) : 0, mi = tm ? parseInt(tm[2]) : 0
        return new Date(+dm[1], +dm[2]-1, +dm[3], h, mi).getTime()
    }
    // Whole span in minutes (may cross days). All-day → 0 (backend sets a 1-day
    // DATE range itself). Guard against an end that precedes the start.
    readonly property int durMin: {
        if (dlg.selAllDay) return 0
        var d = Math.round((dlg._dtMs(dlg.selEndDate || dlg.selDate, dlg.selEnd)
                          - dlg._dtMs(dlg.selDate, dlg.selStart)) / 60000)
        return d > 0 ? d : 60
    }
    function _durText(min) {
        if (min <= 0) return ""
        var d = Math.floor(min/1440), h = Math.floor((min%1440)/60), m = min%60, out = []
        if (d > 0) out.push(d + (d === 1 ? " day" : " days"))
        if (h > 0) out.push(h + " h")
        if (m > 0) out.push(m + " min")
        return out.join(" ")
    }
    // Move the start (keeping the current duration), or set a duration off the
    // start — the two ways a calendar keeps start/end consistent.
    function _setStart(ymd, hm) {
        var old = dlg.durMin
        dlg.selDate = ymd; dlg.selStart = hm
        dlg._setDuration(old)
    }
    function _setDuration(min) {
        var e = new Date(dlg._dtMs(dlg.selDate, dlg.selStart) + Math.max(1, min) * 60000)
        dlg.selEndDate = dlg._fmtDate(e.getTime()); dlg.selEnd = dlg._fmtTime(e.getTime())
    }
    function _todayPlus(days) {
        var d = new Date(); d.setDate(d.getDate() + days)
        if (dlg.selAllDay) dlg.selDate = dlg._fmtDate(d.getTime())
        else dlg._setStart(dlg._fmtDate(d.getTime()), dlg.selStart)
    }

    function _hasCat(c) { return dlg.selCats.indexOf(c) >= 0 }
    function _toggleCat(c) { var o = dlg.selCats.slice(); var i = o.indexOf(c); if (i>=0) o.splice(i,1); else o.push(c); dlg.selCats = o }
    function _addAtt() { var a = dlg.selAtt.slice(); a.push({ name: "", email: "", phone: "" }); dlg.selAtt = a }
    // Mutate the entry IN PLACE — reassigning dlg.selAtt would rebuild the People
    // Repeater on every keystroke and steal focus after one character. In-place
    // edits don't notify (so no rebuild); _ev() reads the same array at submit.
    function _setAtt(i, k, v) { if (dlg.selAtt[i]) dlg.selAtt[i][k] = v }
    function _rmAtt(i) { var a = dlg.selAtt.slice(); a.splice(i, 1); dlg.selAtt = a }

    function _load(ev) {
        dlg.event = ev || {}
        titleF.text = dlg.event.summary || ""
        locF.text = dlg.event.location || ""
        notesF.text = dlg.event.notes || ""
        dlg.selCal = dlg.event.cal || (dlg.calOptions.length > 0 ? dlg.calOptions[0].key : "")
        dlg.selDate = dlg._fmtDate(dlg.event.startMs || Date.now())
        dlg.selAllDay = dlg.event.allDay === true
        dlg.selStart = dlg.event.startMs ? dlg._fmtTime(dlg.event.startMs) : "09:00"
        dlg.selEnd = dlg.event.endMs ? dlg._fmtTime(dlg.event.endMs) : "10:00"
        dlg.selEndDate = dlg.event.endMs ? dlg._fmtDate(dlg.event.endMs) : dlg.selDate
        dlg.selCats = (dlg.event.categories ?? []).slice()
        dlg.selAtt = (dlg.event.attendees ?? []).map(a => ({ name: a.name||"", email: a.email||"", phone: a.phone||"" }))
        dlg.selIcon = dlg.event.icon || ""
        dlg.selImage = dlg.event.image || ""
        dlg.confirmDelete = false
    }
    function openNew(ymd, calId) {
        dlg.isNew = true; dlg.mode = "edit"
        dlg._load({ cal: (calId && calId !== "") ? calId : "", startMs: 0, endMs: 0 })
        dlg.selDate = ymd || dlg._fmtDate(Date.now()); dlg.selEndDate = dlg.selDate
        dlg.selStart = "09:00"; dlg.selEnd = "10:00"
        titleF.text = ""; locF.text = ""; notesF.text = ""
        dlg.open = true
    }
    function openEdit(ev) { dlg.isNew = false; dlg.mode = "detail"; dlg._load(ev); dlg.open = true }

    readonly property bool ready: titleF.text.trim() !== "" && dlg.selCal !== ""

    function _ev() {
        return { summary: titleF.text.trim(), ymd: dlg.selDate, hm: dlg.selAllDay ? "" : dlg.selStart,
                 durMin: dlg.durMin, location: locF.text.trim(), notes: notesF.text, categories: dlg.selCats,
                 attendees: dlg.selAtt.filter(a => (a.name||"").trim() || (a.email||"").trim() || (a.phone||"").trim()),
                 icon: dlg.selIcon, image: dlg.selImage }
    }
    function submit() {
        if (!dlg.ready) return
        var ev = dlg._ev()
        if (dlg.isNew) {
            if (dlg.isLocal) Local.addEventFull(dlg.selCal.slice(4), JSON.stringify(ev))
            else CalDav.addEventFull(dlg.selCal, JSON.stringify(ev))
        } else if (String(dlg.event.cal).indexOf("loc:") === 0) {
            Local.updateEventItem(String(dlg.event.href || dlg.event.uid), JSON.stringify(ev))
        } else {
            var patch = { summary: ev.summary, location: ev.location, notes: ev.notes, categories: ev.categories,
                          attendees: ev.attendees, icon: ev.icon, image: ev.image }
            if (!dlg.recurring) { patch.ymd = ev.ymd; patch.hm = ev.hm; patch.durMin = ev.durMin }
            CalDav.updateEvent(dlg.event.cal, dlg.event.href, JSON.stringify(patch))
        }
        dlg.open = false
    }
    function remove() {
        if (String(dlg.event.cal).indexOf("loc:") === 0) Local.deleteItem(String(dlg.event.href || dlg.event.uid))
        else CalDav.deleteItem(dlg.event.cal, dlg.event.href)
        dlg.open = false
    }
    // detail-view helpers (read from the loaded event)
    function _whenText() {
        var s = new Date(dlg.event.startMs), e = new Date(dlg.event.endMs)
        if (dlg.event.allDay) return "All day · " + Qt.formatDate(s, "ddd, MMM d yyyy")
        var sameDay = s.toDateString() === e.toDateString()
        if (sameDay)
            return Qt.formatDate(s, "ddd, MMM d yyyy") + " · " + dlg._fmtTime(dlg.event.startMs)
                 + " – " + dlg._fmtTime(dlg.event.endMs)
        return Qt.formatDateTime(s, Settings.dateTimeFmt) + "  →  " + Qt.formatDateTime(e, Settings.dateTimeFmt)
    }
    function _whenDur() {
        if (dlg.event.allDay || !dlg.event.startMs || !dlg.event.endMs) return ""
        return dlg._durText(Math.round((dlg.event.endMs - dlg.event.startMs) / 60000))
    }
    // Markdown treats a single newline as a soft break (collapses to a space), so
    // the read view ran the user's separate lines together. Turn every lone
    // newline into a hard break (trailing two spaces) while leaving blank-line
    // paragraph breaks intact — the rendered text then wraps line-for-line.
    function _mdBreaks(s) { return (s || "").replace(/([^\n])\n(?!\n)/g, "$1  \n") }

    // ── reusable inline pieces ───────────────────────────────────────────────
    // A grouped form section: rounded panel, leading accent glyph + label header,
    // then whatever fields are declared inside.
    component Card: Rectangle {
        id: card
        property string glyph: ""
        property string label: ""
        default property alias content: body.data
        width: parent ? parent.width : 0
        radius: 12
        color: Qt.alpha(Theme.boNormal, 0.10)
        border.width: 1; border.color: Qt.alpha(Theme.boNormal, 0.22)
        implicitHeight: body.implicitHeight + 28
        Column {
            id: body
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
            spacing: 11
            Row {
                width: parent.width; spacing: 9; visible: card.label !== ""
                Text { anchors.verticalCenter: parent.verticalCenter; text: card.glyph
                       color: Theme.accent; font.pixelSize: 15; font.family: Theme.fontFamily }
                Text { anchors.verticalCenter: parent.verticalCenter; text: card.label
                       color: Theme.fgMuted; font.pixelSize: 12; font.bold: true; font.family: Theme.fontFamily }
            }
        }
    }

    // A small pill for quick-set actions (duration / date shortcuts).
    component MiniChip: Rectangle {
        id: chip
        property string label: ""
        signal clicked()
        implicitWidth: chipT.implicitWidth + 22; height: 27; radius: 13
        color: chipMa.pressed ? Qt.darker(Theme.bgSecondary, 1.15)
             : chipMa.containsMouse ? Theme.bgSecondary : Theme.bgElement
        Behavior on color { ColorAnimation { duration: 90 } }
        Text { id: chipT; anchors.centerIn: parent; text: chip.label
               color: Theme.fgPrimary; font.pixelSize: 12; font.family: Theme.fontFamily }
        MouseArea { id: chipMa; anchors.fill: parent; hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor; onClicked: chip.clicked() }
    }

    // A read-only labelled line in the detail view (leading glyph + value).
    component InfoRow: Row {
        property string glyph: ""
        property alias text: infoVal.text
        property color tint: Theme.fgPrimary
        width: parent.width; spacing: 12; visible: infoVal.text !== ""
        Text { text: parent.glyph; color: Theme.fgMuted; width: 20
               horizontalAlignment: Text.AlignHCenter; font.pixelSize: 15; font.family: Theme.fontFamily }
        Text { id: infoVal; width: parent.width - 32; wrapMode: Text.WordWrap; color: parent.tint
               font.pixelSize: 14; font.family: Theme.fontFamily }
    }

    FileDialog {
        id: imgDlg
        title: "Choose an image"
        nameFilters: ["Images (*.png *.jpg *.jpeg *.webp *.gif *.bmp)"]
        onAccepted: { var p = Local.cacheImage("" + selectedFile); if (p !== "") dlg.selImage = p }
    }

    Rectangle {
        anchors.fill: parent; color: Qt.rgba(0, 0, 0, 0.5)
        MouseArea { anchors.fill: parent; onClicked: dlg.open = false }
    }

    Rectangle {
        id: cardBox
        anchors.centerIn: parent
        width: Math.min(860, dlg.width - 48)
        height: Math.min(dlg.height - 48, 920)
        radius: 16; color: Theme.surface
        border.width: 1; border.color: Qt.alpha(Theme.boNormal, 0.5)
        clip: true
        MouseArea { anchors.fill: parent }

        // ── HERO: neutral band tinted by the app accent (NOT the calendar — the
        // per-calendar wash read as a muddy colour); the calendar is identified by
        // the small legend dot next to its name below. ──
        Rectangle {
            id: header
            anchors { left: parent.left; right: parent.right; top: parent.top }
            height: 96
            topLeftRadius: cardBox.radius; topRightRadius: cardBox.radius
            readonly property color calCol: dlg._calColor(dlg.selCal)   // legend dot only
            color: Qt.alpha(Theme.accent, 0.14)

            Rectangle {
                id: iconBtn
                anchors { left: parent.left; leftMargin: 18; verticalCenter: parent.verticalCenter }
                width: 52; height: 52; radius: 14
                color: iconMa.pressed ? Qt.alpha(Theme.accent, 0.42)
                     : iconMa.containsMouse ? Qt.alpha(Theme.accent, 0.34) : Qt.alpha(Theme.accent, 0.24)
                scale: iconMa.pressed ? 0.94 : 1.0
                Behavior on color { ColorAnimation { duration: 110 } }
                Behavior on scale { NumberAnimation { duration: 80 } }
                Text { anchors.centerIn: parent
                       text: dlg.selIcon !== "" ? dlg.selIcon : "󰃭"
                       color: dlg.selIcon !== "" ? Theme.fgBright : Theme.accent
                       font.pixelSize: dlg.selIcon !== "" ? 26 : 22; font.family: Theme.fontFamily }
                Rectangle {         // little "edit" affordance in edit mode
                    visible: dlg.mode === "edit"
                    anchors { right: parent.right; bottom: parent.bottom; rightMargin: -3; bottomMargin: -3 }
                    width: 20; height: 20; radius: 10; color: Theme.surface
                    border.width: 1; border.color: Qt.alpha(Theme.boNormal, 0.6)
                    Text { anchors.centerIn: parent; text: "󰏫"; color: Theme.fgMuted
                           font.pixelSize: 11; font.family: Theme.fontFamily }
                }
                MouseArea { id: iconMa; anchors.fill: parent; hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: dlg.mode === "edit" ? iconPop.open() : (dlg.mode = "edit") }
            }

            Column {
                anchors { left: iconBtn.right; leftMargin: 15; right: parent.right; rightMargin: 18
                          verticalCenter: parent.verticalCenter }
                spacing: 5
                Text {
                    visible: dlg.mode === "detail"
                    width: parent.width; elide: Text.ElideRight
                    text: dlg.event.summary || "(untitled)"
                    color: Theme.fgBright; font.pixelSize: 21; font.bold: true; font.family: Theme.fontFamily
                }
                Item {
                    visible: dlg.mode === "edit"; width: parent.width; height: 30
                    TextInput {
                        id: titleF
                        anchors.fill: parent; verticalAlignment: TextInput.AlignVCenter
                        color: Theme.fgBright; font.pixelSize: 21; font.bold: true; font.family: Theme.fontFamily
                        selectByMouse: true; clip: true
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: titleF.text === "" && !titleF.activeFocus
                        text: "Event title"; color: Qt.alpha(Theme.fgMuted, 0.8)
                        font.pixelSize: 21; font.bold: true; font.family: Theme.fontFamily
                    }
                }
                Row {
                    width: parent.width; spacing: 7
                    Rectangle { anchors.verticalCenter: parent.verticalCenter
                                width: 9; height: 9; radius: 5; color: header.calCol }
                    Text { anchors.verticalCenter: parent.verticalCenter
                           text: dlg._calName(dlg.selCal); color: Theme.fgPrimary
                           font.pixelSize: 13; font.family: Theme.fontFamily }
                    Text { anchors.verticalCenter: parent.verticalCenter; visible: dlg.recurring
                           text: "· 󰑖 recurring"; color: Theme.fgMuted
                           font.pixelSize: 12; font.family: Theme.fontFamily }
                }
            }

            Popup {
                id: iconPop
                x: iconBtn.x; y: iconBtn.y + iconBtn.height + 6; width: 300; padding: 10
                modal: false; closePolicy: Popup.CloseOnPressOutside | Popup.CloseOnEscape
                background: Rectangle { radius: 10; color: Theme.bgPrimary
                                       border.width: 1; border.color: Qt.alpha(Theme.boNormal, 0.6) }
                contentItem: Flow {
                    spacing: 6
                    Repeater {
                        model: dlg.iconChoices
                        delegate: Rectangle {
                            required property var modelData
                            readonly property bool on: dlg.selIcon === modelData
                            width: 36; height: 36; radius: 8
                            color: on ? Qt.alpha(Theme.accent, 0.35) : icHov.pressed ? Theme.bgSecondary
                                 : icHov.containsMouse ? Theme.bgSecondary : Theme.bgElement
                            scale: icHov.pressed ? 0.9 : 1.0
                            Behavior on scale { NumberAnimation { duration: 70 } }
                            border.width: on ? 1 : 0; border.color: Theme.accent
                            Text { anchors.centerIn: parent; text: modelData === "" ? "󰜺" : modelData
                                   color: Theme.fgMuted; font.pixelSize: modelData === "" ? 15 : 18; font.family: Theme.fontFamily }
                            MouseArea { id: icHov; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                        onClicked: { dlg.selIcon = modelData; iconPop.close() } }
                        }
                    }
                }
            }
        }

        // ── SCROLLABLE MIDDLE ────────────────────────────────────────────────
        Flickable {
            id: flick
            anchors { left: parent.left; right: parent.right; top: header.bottom; bottom: footerLine.top
                      topMargin: 18; bottomMargin: 14; leftMargin: 18; rightMargin: 18 }
            contentHeight: dlg.mode === "detail" ? detailCol.implicitHeight : editCol.implicitHeight
            clip: true; boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            // ── DETAIL VIEW ──────────────────────────────────────────────────
            Column {
                id: detailCol
                visible: dlg.mode === "detail"
                anchors { left: parent.left; right: parent.right; top: parent.top }
                spacing: 15
                // Event image preview — a sharp, rounded banner at the top of the
                // detail view (the whole-card background version was removed).
                Item {
                    id: banner
                    visible: dlg.selImage !== ""
                    width: parent.width
                    height: dlg.selImage !== "" ? Math.min(210, width * 0.42) : 0
                    layer.enabled: true
                    layer.effect: OpacityMask {
                        maskSource: Rectangle { width: banner.width; height: banner.height; radius: 12 }
                    }
                    Image {
                        anchors.fill: parent
                        source: dlg.selImage !== "" ? "file://" + dlg.selImage : ""
                        fillMode: Image.PreserveAspectCrop; asynchronous: true; cache: true
                    }
                }
                Column {
                    width: parent.width; spacing: 10
                    InfoRow { glyph: "󰥔"; tint: Theme.fgBright
                              text: dlg._whenText() + (dlg._whenDur() !== "" ? "   ·   " + dlg._whenDur() : "") }
                    InfoRow { glyph: "󰍎"; text: dlg.event.location || "" }
                }
                Rectangle {
                    visible: (dlg.event.notes||"") !== ""
                    width: parent.width; radius: 12
                    // darker + more opaque over a hero image so the markdown reads
                    color: Qt.alpha(Theme.boNormal, 0.10)
                    border.width: 1; border.color: Qt.alpha(Theme.boNormal, 0.22)
                    implicitHeight: notesTxt.implicitHeight + 28
                    Text {
                        id: notesTxt
                        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
                        wrapMode: Text.WordWrap; text: dlg._mdBreaks(dlg.event.notes)
                        textFormat: Text.MarkdownText; onLinkActivated: l => Qt.openUrlExternally(l)
                        color: Theme.fgPrimary; font.pixelSize: 14; font.family: Theme.fontFamily
                    }
                }
                Flow {
                    visible: (dlg.selCats||[]).length > 0
                    width: parent.width; spacing: 6
                    Repeater { model: dlg.selCats
                        delegate: Rectangle { required property var modelData
                            height: 27; radius: 13; width: dtT.implicitWidth + 26; color: Qt.alpha(Theme.accent, 0.22)
                            Text { id: dtT; anchors.centerIn: parent; text: modelData; color: Theme.fgBright
                                   font.pixelSize: 12; font.family: Theme.fontFamily } } }
                }
                Column {
                    visible: (dlg.selAtt||[]).length > 0
                    width: parent.width; spacing: 7
                    Text { text: "PEOPLE"; color: Theme.fgMuted; font.pixelSize: 11; font.bold: true
                           font.family: Theme.fontFamily }
                    Repeater { model: dlg.selAtt
                        delegate: Row { required property var modelData; width: parent.width; spacing: 10
                            Rectangle { width: 30; height: 30; radius: 15; color: Qt.alpha(Theme.accent, 0.22)
                                anchors.verticalCenter: parent.verticalCenter
                                Text { anchors.centerIn: parent
                                       text: (modelData.name||modelData.email||"?").charAt(0).toUpperCase()
                                       color: Theme.fgBright; font.pixelSize: 13; font.bold: true; font.family: Theme.fontFamily } }
                            Text { anchors.verticalCenter: parent.verticalCenter; width: parent.width - 40; elide: Text.ElideRight
                                text: [modelData.name, modelData.email, modelData.phone].filter(x => x && x !== "").join("  ·  ")
                                color: Theme.fgPrimary; font.pixelSize: 13; font.family: Theme.fontFamily } } }
                }
            }

            // ── EDIT FORM ────────────────────────────────────────────────────
            Column {
                id: editCol
                visible: dlg.mode === "edit"
                anchors { left: parent.left; right: parent.right; top: parent.top }
                spacing: 12

                // Calendar (choose only on a new event)
                Card {
                    glyph: "󰃭"; label: "CALENDAR"
                    Picker { visible: dlg.isNew; width: parent.width; options: dlg.calOptions
                             current: dlg.selCal; placeholder: "pick a calendar"; onPicked: k => dlg.selCal = k }
                    Text { visible: !dlg.isNew; text: dlg._calName(dlg.selCal); color: Theme.fgBright
                           font.pixelSize: 14; font.family: Theme.fontFamily }
                }

                // When: all-day toggle + start/end (multi-day) + duration
                Card {
                    glyph: "󰥔"; label: "WHEN"

                    Row {
                        spacing: 8
                        PillButton { text: "All day"; icon: dlg.selAllDay ? "󰄲" : "󰄱"; accent: dlg.selAllDay
                                     onClicked: dlg.selAllDay = !dlg.selAllDay }
                        MiniChip { anchors.verticalCenter: parent.verticalCenter; visible: !dlg.recurring
                                   label: "Today"; onClicked: dlg._todayPlus(0) }
                        MiniChip { anchors.verticalCenter: parent.verticalCenter; visible: !dlg.recurring
                                   label: "Tomorrow"; onClicked: dlg._todayPlus(1) }
                    }

                    // recurring → date/time is locked to keep the series intact
                    Column {
                        visible: dlg.recurring; width: parent.width; spacing: 4
                        Text { text: dlg._whenText(); color: Theme.fgBright; font.pixelSize: 14; font.family: Theme.fontFamily }
                        Text { width: parent.width; wrapMode: Text.WordWrap
                               text: "󰑖 Recurring — date & time are locked to keep the series intact."
                               color: Theme.fgMuted; font.pixelSize: 11; font.family: Theme.fontFamily }
                    }

                    // Starts
                    Row {
                        visible: !dlg.recurring; width: parent.width; spacing: 8
                        Text { anchors.verticalCenter: parent.verticalCenter; width: 42
                               text: dlg.selAllDay ? "Date" : "Starts"; color: Theme.fgMuted
                               font.pixelSize: 12; font.family: Theme.fontFamily }
                        DatePicker {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 42 - 8 - (dlg.selAllDay ? 0 : 92)
                            ymd: dlg.selDate; allowEmpty: false
                            onPicked: k => dlg.selAllDay ? (dlg.selDate = k) : dlg._setStart(k, dlg.selStart)
                        }
                        TimeField { visible: !dlg.selAllDay; anchors.verticalCenter: parent.verticalCenter
                                    hm: dlg.selStart; onEdited: h => dlg._setStart(dlg.selDate, h) }
                    }
                    // Ends (timed only — multi-day via the end date)
                    Row {
                        visible: !dlg.recurring && !dlg.selAllDay; width: parent.width; spacing: 8
                        Text { anchors.verticalCenter: parent.verticalCenter; width: 42
                               text: "Ends"; color: Theme.fgMuted; font.pixelSize: 12; font.family: Theme.fontFamily }
                        DatePicker {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 42 - 8 - 92
                            ymd: dlg.selEndDate; allowEmpty: false
                            onPicked: k => dlg.selEndDate = (k < dlg.selDate ? dlg.selDate : k)
                        }
                        TimeField { anchors.verticalCenter: parent.verticalCenter
                                    hm: dlg.selEnd; onEdited: h => dlg.selEnd = h }
                    }
                    // Duration read-out (left) + quick-set chips (right)
                    Item {
                        visible: !dlg.recurring && !dlg.selAllDay; width: parent.width; height: 27
                        Text { anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                               text: "󰔟 " + dlg._durText(dlg.durMin); color: Theme.fgPrimary
                               font.pixelSize: 12; font.family: Theme.fontFamily }
                        Row { anchors { right: parent.right; verticalCenter: parent.verticalCenter } spacing: 6
                            MiniChip { label: "30 min"; onClicked: dlg._setDuration(30) }
                            MiniChip { label: "1 h"; onClicked: dlg._setDuration(60) }
                            MiniChip { label: "2 h"; onClicked: dlg._setDuration(120) }
                        }
                    }
                }

                // Where
                Card {
                    glyph: "󰍎"; label: "LOCATION"
                    SettingsField { id: locF; width: parent.width; placeholder: "add a location" }
                }

                // Details: description + image
                Card {
                    glyph: "󰈚"; label: "DETAILS"

                    Text { text: "Description · Markdown renders live as you type"; color: Theme.fgMuted
                           font.pixelSize: 11; font.family: Theme.fontFamily }
                    // One block, Markdown styled live in place (Obsidian-style).
                    MarkdownField { id: notesF; width: parent.width; height: 150
                                    placeholder: "notes / agenda — **bold**, - lists, # headings, > quotes" }
                    Image { visible: dlg.selImage !== ""; width: parent.width
                            height: dlg.selImage !== "" ? Math.min(200, width*0.45) : 0
                            source: dlg.selImage !== "" ? "file://" + dlg.selImage : ""
                            fillMode: Image.PreserveAspectCrop; clip: true; asynchronous: true }
                    Row { spacing: 8
                        PillButton { icon: "󰋩"; text: dlg.selImage !== "" ? "Change image" : "Add image"; onClicked: imgDlg.open() }
                        PillButton { visible: dlg.selImage !== ""; text: "Remove"; danger: true; onClicked: dlg.selImage = "" }
                    }
                }

                // Tags
                Card {
                    glyph: "󰓹"; label: "TAGS"
                    Flow {
                        width: parent.width; spacing: 6
                        Repeater {
                            model: {
                                var seen = {}, out = []
                                var known = (Local.eventTags ?? []).map(t => t.name)
                                for (var i = 0; i < known.length; i++) if (!seen[known[i]]) { seen[known[i]] = 1; out.push(known[i]) }
                                for (var j = 0; j < dlg.selCats.length; j++) if (!seen[dlg.selCats[j]]) { seen[dlg.selCats[j]] = 1; out.push(dlg.selCats[j]) }
                                return out
                            }
                            delegate: Rectangle {
                                required property var modelData
                                readonly property bool on: dlg._hasCat(modelData)
                                height: 28; radius: 14; width: tgTxt.implicitWidth + 26
                                color: on ? Theme.accent : tgHov.pressed ? Theme.bgSecondary
                                     : tgHov.containsMouse ? Theme.bgSecondary : Theme.bgElement
                                scale: tgHov.pressed ? 0.93 : 1.0
                                Behavior on scale { NumberAnimation { duration: 70 } }
                                Behavior on color { ColorAnimation { duration: 90 } }
                                border.width: on ? 0 : 1; border.color: Qt.alpha(Theme.boNormal, 0.5)
                                Text { id: tgTxt; anchors.centerIn: parent; text: modelData
                                       color: on ? "#ffffff" : Theme.fgPrimary; font.pixelSize: 12; font.bold: on; font.family: Theme.fontFamily }
                                MouseArea { id: tgHov; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                            onClicked: dlg._toggleCat(modelData) }
                            }
                        }
                    }
                    Row { width: parent.width; spacing: 8
                        SettingsField { id: newTag; width: parent.width - 108; placeholder: "new tag" }
                        PillButton { icon: "󰐕"; text: "Add tag"; active: newTag.text.trim() !== ""
                            onClicked: { var t = newTag.text.trim(); Local.addEventTag(t, ""); if (!dlg._hasCat(t)) dlg._toggleCat(t); newTag.text = "" } }
                    }
                }

                // People
                Card {
                    glyph: "󰀄"; label: "PEOPLE"
                    Repeater {
                        model: dlg.selAtt
                        delegate: Rectangle {
                            required property var modelData
                            required property int index
                            width: parent.width; radius: 10; color: Theme.bgPrimary; height: attCol.implicitHeight + 16
                            Column {
                                id: attCol
                                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 8 }
                                spacing: 6
                                Row { width: parent.width; spacing: 8
                                    SettingsField { width: parent.width - 42; placeholder: "name"; text: modelData.name || ""
                                        onTextChanged: if (text !== (modelData.name||"")) dlg._setAtt(index, "name", text) }
                                    Rectangle { width: 34; height: 38; radius: 8
                                        color: rmA.pressed ? Qt.alpha(Theme.fgUrgent,0.3) : rmA.containsMouse ? Qt.alpha(Theme.fgUrgent, 0.2) : "transparent"
                                        Text { anchors.centerIn: parent; text: "󰩹"; color: rmA.containsMouse ? Theme.fgUrgent : Theme.fgMuted
                                               font.pixelSize: 15; font.family: Theme.fontFamily }
                                        MouseArea { id: rmA; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                                    onClicked: dlg._rmAtt(index) } }
                                }
                                Row { width: parent.width; spacing: 8
                                    SettingsField { width: (parent.width - 8) * 0.58; placeholder: "email"; text: modelData.email || ""
                                        onTextChanged: if (text !== (modelData.email||"")) dlg._setAtt(index, "email", text) }
                                    SettingsField { width: (parent.width - 8) * 0.42; placeholder: "phone"; text: modelData.phone || ""
                                        onTextChanged: if (text !== (modelData.phone||"")) dlg._setAtt(index, "phone", text) }
                                }
                            }
                        }
                    }
                    PillButton { icon: "󰐕"; text: "Add person"; onClicked: dlg._addAtt() }
                }
            }
        }

        // ── FIXED FOOTER ─────────────────────────────────────────────────────
        Rectangle { id: footerLine
                    anchors { left: parent.left; right: parent.right; bottom: footer.top; bottomMargin: 16
                              leftMargin: 18; rightMargin: 18 }
                    height: 1; color: Qt.alpha(Theme.boNormal, 0.35) }
        Item {
            id: footer
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 18 }
            height: 36
            PillButton {
                anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                visible: !dlg.isNew
                danger: true; icon: "󰩹"
                text: dlg.confirmDelete ? (dlg.recurring ? "Delete series?" : "Really delete?") : "Delete"
                onClicked: { if (dlg.confirmDelete) dlg.remove(); else dlg.confirmDelete = true }
            }
            Row {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                spacing: 10
                PillButton { text: dlg.mode === "edit" && !dlg.isNew ? "Cancel edit" : "Close"
                             onClicked: { if (dlg.mode === "edit" && !dlg.isNew) { dlg.mode = "detail"; dlg._load(dlg.event) } else dlg.open = false } }
                PillButton { visible: dlg.mode === "detail"; accent: true; icon: "󰏫"; text: "Edit"; onClicked: dlg.mode = "edit" }
                PillButton { visible: dlg.mode === "edit"; accent: true; active: dlg.ready
                             icon: dlg.isNew ? "󰐕" : "󰄬"; text: dlg.isNew ? "Create" : "Save"; onClicked: dlg.submit() }
            }
        }
    }
}
