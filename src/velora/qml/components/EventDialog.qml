import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs

// Calendar event viewer + editor. Clicking an event opens the DETAIL view first
// (read-only, Markdown description, image); an Edit button flips to the form.
// Header (icon left of the title) and footer (actions) are pinned — only the
// middle scrolls. openNew(ymd, calId) opens straight in edit mode.
Item {
    id: dlg
    property bool open: false
    property string mode: "detail"          // "detail" | "edit"
    property var event: ({})
    property bool isNew: true
    property string selCal: ""
    property bool selAllDay: false
    property string selDate: ""
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
        .map(c => ({ key: c.id, label: c.name || "calendar", color: c.color || "" }))
    function _calName(id) {
        var cs = dlg._merge(CalDav.calendars, Local.calendars)
        for (var i = 0; i < cs.length; i++) if (cs[i].id === id) return cs[i].name || "calendar"
        return "calendar"
    }

    function _fmtDate(ms) {
        var d = new Date(ms); function p(n){return (n<10?"0":"")+n}
        return d.getFullYear()+"-"+p(d.getMonth()+1)+"-"+p(d.getDate())
    }
    function _fmtTime(ms) { return Qt.formatDateTime(new Date(ms), "hh:mm") }
    function _mins(hm) { var m = /^(\d{1,2}):(\d{2})$/.exec(hm || ""); return m ? parseInt(m[1])*60 + parseInt(m[2]) : 0 }
    readonly property int durMin: { var d = dlg._mins(dlg.selEnd) - dlg._mins(dlg.selStart); return d > 0 ? d : 60 }

    function _hasCat(c) { return dlg.selCats.indexOf(c) >= 0 }
    function _toggleCat(c) { var o = dlg.selCats.slice(); var i = o.indexOf(c); if (i>=0) o.splice(i,1); else o.push(c); dlg.selCats = o }
    function _addAtt() { var a = dlg.selAtt.slice(); a.push({ name: "", email: "", phone: "" }); dlg.selAtt = a }
    function _setAtt(i, k, v) { var a = dlg.selAtt.slice(); a[i] = Object.assign({}, a[i]); a[i][k] = v; dlg.selAtt = a }
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
        dlg.selCats = (dlg.event.categories ?? []).slice()
        dlg.selAtt = (dlg.event.attendees ?? []).map(a => ({ name: a.name||"", email: a.email||"", phone: a.phone||"" }))
        dlg.selIcon = dlg.event.icon || ""
        dlg.selImage = dlg.event.image || ""
        dlg.confirmDelete = false
    }
    function openNew(ymd, calId) {
        dlg.isNew = true; dlg.mode = "edit"
        dlg._load({ cal: (calId && calId !== "") ? calId : "", startMs: 0, endMs: 0 })
        dlg.selDate = ymd || dlg._fmtDate(Date.now()); dlg.selStart = "09:00"; dlg.selEnd = "10:00"
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
        if (dlg.event.allDay) return "All day · " + Qt.formatDate(new Date(dlg.event.startMs), "ddd, MMM d yyyy")
        return Qt.formatDate(new Date(dlg.event.startMs), "ddd, MMM d yyyy") + " · "
             + dlg._fmtTime(dlg.event.startMs) + "–" + dlg._fmtTime(dlg.event.endMs)
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
        width: Math.min(560, dlg.width - 60)
        height: Math.min(dlg.height - 60, 760)
        radius: 14; color: Theme.surface
        border.width: 1; border.color: Qt.alpha(Theme.boNormal, 0.5)
        MouseArea { anchors.fill: parent }

        // ── FIXED HEADER: icon (left) + title ────────────────────────────────
        Item {
            id: header
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 18 }
            height: 40
            Rectangle {
                id: iconBtn
                anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                width: 40; height: 40; radius: 10
                color: iconMa.pressed ? Theme.bgSecondary : iconMa.containsMouse ? Theme.bgSecondary : Theme.bgElement
                scale: iconMa.pressed ? 0.94 : 1.0
                Behavior on color { ColorAnimation { duration: 100 } }
                Behavior on scale { NumberAnimation { duration: 80 } }
                Text { anchors.centerIn: parent
                       text: dlg.selIcon !== "" ? dlg.selIcon : "󰃭"
                       color: Theme.fgMuted; font.pixelSize: dlg.selIcon !== "" ? 20 : 18; font.family: Theme.fontFamily }
                MouseArea { id: iconMa; anchors.fill: parent; hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: dlg.mode === "edit" ? iconPop.open() : (dlg.mode = "edit") }
            }
            Text {
                visible: dlg.mode === "detail"
                anchors { left: iconBtn.right; leftMargin: 12; right: parent.right; verticalCenter: parent.verticalCenter }
                elide: Text.ElideRight; text: dlg.event.summary || "(untitled)"
                color: Theme.fgBright; font.pixelSize: 19; font.bold: true; font.family: Theme.fontFamily
            }
            SettingsField {
                visible: dlg.mode === "edit"
                anchors { left: iconBtn.right; leftMargin: 12; right: parent.right; verticalCenter: parent.verticalCenter }
                id: titleF; placeholder: "event title"
            }

            Popup {
                id: iconPop
                y: iconBtn.height + 6; width: 300; padding: 10
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
        Rectangle { anchors { left: parent.left; right: parent.right; top: header.bottom; topMargin: 14; leftMargin: 18; rightMargin: 18 }
                    height: 1; color: Qt.alpha(Theme.boNormal, 0.35) }

        // ── SCROLLABLE MIDDLE ────────────────────────────────────────────────
        Flickable {
            id: flick
            anchors { left: parent.left; right: parent.right; top: header.bottom; bottom: footerLine.top
                      topMargin: 22; bottomMargin: 14; leftMargin: 18; rightMargin: 18 }
            contentHeight: dlg.mode === "detail" ? detailCol.implicitHeight : editCol.implicitHeight
            clip: true; boundsBehavior: Flickable.StopAtBounds

            // ── DETAIL VIEW ──────────────────────────────────────────────────
            Column {
                id: detailCol
                visible: dlg.mode === "detail"
                anchors { left: parent.left; right: parent.right; top: parent.top }
                spacing: 14

                Image {
                    visible: dlg.selImage !== ""
                    width: parent.width; height: dlg.selImage !== "" ? Math.min(240, width * 0.5) : 0
                    source: dlg.selImage !== "" ? "file://" + dlg.selImage : ""
                    fillMode: Image.PreserveAspectCrop; clip: true; asynchronous: true
                }
                Column {
                    width: parent.width; spacing: 4
                    Text { text: "󰃭  " + dlg._calName(dlg.selCal); color: Theme.fgMuted
                           font.pixelSize: 13; font.family: Theme.fontFamily }
                    Text { text: "󰥔  " + dlg._whenText() + (dlg.recurring ? "   󰑖 recurring" : "")
                           color: Theme.fgPrimary; font.pixelSize: 14; font.family: Theme.fontFamily }
                    Text { visible: (dlg.event.location||"") !== ""; text: "󰍎  " + (dlg.event.location||"")
                           color: Theme.fgPrimary; font.pixelSize: 14; font.family: Theme.fontFamily }
                }
                Text {
                    visible: (dlg.event.notes||"") !== ""
                    width: parent.width; wrapMode: Text.WordWrap
                    text: dlg.event.notes || ""
                    textFormat: Text.MarkdownText; onLinkActivated: l => Qt.openUrlExternally(l)
                    color: Theme.fgPrimary; font.pixelSize: 14; font.family: Theme.fontFamily
                }
                Flow {
                    visible: (dlg.selCats||[]).length > 0
                    width: parent.width; spacing: 6
                    Repeater { model: dlg.selCats
                        delegate: Rectangle { required property var modelData
                            height: 26; radius: 13; width: dtT.implicitWidth + 24; color: Qt.alpha(Theme.accent, 0.22)
                            Text { id: dtT; anchors.centerIn: parent; text: modelData; color: Theme.fgBright
                                   font.pixelSize: 12; font.family: Theme.fontFamily } } }
                }
                Column {
                    visible: (dlg.selAtt||[]).length > 0
                    width: parent.width; spacing: 5
                    Text { text: "People"; color: Theme.fgMuted; font.pixelSize: 12; font.family: Theme.fontFamily }
                    Repeater { model: dlg.selAtt
                        delegate: Text { required property var modelData; width: parent.width; elide: Text.ElideRight
                            text: "󰀄  " + [modelData.name, modelData.email, modelData.phone].filter(x => x && x !== "").join(" · ")
                            color: Theme.fgPrimary; font.pixelSize: 13; font.family: Theme.fontFamily } }
                }
            }

            // ── EDIT FORM ────────────────────────────────────────────────────
            Column {
                id: editCol
                visible: dlg.mode === "edit"
                anchors { left: parent.left; right: parent.right; top: parent.top }
                spacing: 13

                Column {
                    width: parent.width; spacing: 5
                    Text { text: "Calendar"; color: Theme.fgMuted; font.pixelSize: 12; font.family: Theme.fontFamily }
                    Picker { visible: dlg.isNew; width: parent.width; options: dlg.calOptions
                             current: dlg.selCal; placeholder: "pick a calendar"; onPicked: k => dlg.selCal = k }
                    Text { visible: !dlg.isNew; text: dlg._calName(dlg.selCal); color: Theme.fgPrimary
                           font.pixelSize: 14; font.family: Theme.fontFamily }
                }

                Row {
                    spacing: 8
                    PillButton { text: "All day"; icon: dlg.selAllDay ? "󰄲" : "󰄱"; accent: dlg.selAllDay
                                 onClicked: dlg.selAllDay = !dlg.selAllDay }
                }
                Row {
                    width: parent.width; spacing: 10
                    Column {
                        width: dlg.selAllDay ? parent.width : (parent.width - 200); spacing: 5
                        Text { text: "Date"; color: Theme.fgMuted; font.pixelSize: 12; font.family: Theme.fontFamily }
                        DatePicker { width: parent.width; ymd: dlg.selDate; allowEmpty: false; onPicked: k => dlg.selDate = k }
                    }
                    Column {
                        visible: !dlg.selAllDay; spacing: 5
                        Text { text: "From – to"; color: Theme.fgMuted; font.pixelSize: 12; font.family: Theme.fontFamily }
                        Row { spacing: 6
                            TimeField { hm: dlg.selStart; onEdited: h => dlg.selStart = h }
                            Text { anchors.verticalCenter: parent.verticalCenter; text: "–"; color: Theme.fgMuted; font.pixelSize: 15 }
                            TimeField { hm: dlg.selEnd; onEdited: h => dlg.selEnd = h }
                        }
                    }
                }
                Text { visible: dlg.recurring; width: parent.width; wrapMode: Text.WordWrap
                       text: "󰑖 Recurring — date/time changes are disabled to keep the series intact."
                       color: Theme.fgMuted; font.pixelSize: 11; font.family: Theme.fontFamily }

                Column {
                    width: parent.width; spacing: 5
                    Text { text: "Location"; color: Theme.fgMuted; font.pixelSize: 12; font.family: Theme.fontFamily }
                    SettingsField { id: locF; width: parent.width; placeholder: "add a location" }
                }

                Column {
                    width: parent.width; spacing: 5
                    Text { text: "Description  ·  Markdown"; color: Theme.fgMuted; font.pixelSize: 12; font.family: Theme.fontFamily }
                    NotesField { id: notesF; width: parent.width; height: 110; placeholder: "notes / agenda — **bold**, - lists, # headings" }
                }

                // Image
                Column {
                    width: parent.width; spacing: 6
                    Text { text: "Image"; color: Theme.fgMuted; font.pixelSize: 12; font.family: Theme.fontFamily }
                    Image { visible: dlg.selImage !== ""; width: parent.width; height: dlg.selImage !== "" ? Math.min(200, width*0.45) : 0
                            source: dlg.selImage !== "" ? "file://" + dlg.selImage : ""
                            fillMode: Image.PreserveAspectCrop; clip: true; asynchronous: true }
                    Row { spacing: 8
                        PillButton { icon: "󰋩"; text: dlg.selImage !== "" ? "Change image" : "Add image"; onClicked: imgDlg.open() }
                        PillButton { visible: dlg.selImage !== ""; text: "Remove"; danger: true; onClicked: dlg.selImage = "" }
                    }
                }

                // Tags
                Column {
                    width: parent.width; spacing: 6
                    Text { text: "Tags"; color: Theme.fgMuted; font.pixelSize: 12; font.family: Theme.fontFamily }
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
                Column {
                    width: parent.width; spacing: 6
                    Text { text: "People"; color: Theme.fgMuted; font.pixelSize: 12; font.family: Theme.fontFamily }
                    Repeater {
                        model: dlg.selAtt
                        delegate: Rectangle {
                            required property var modelData
                            required property int index
                            width: parent.width; radius: 10; color: Theme.bgElement; height: attCol.implicitHeight + 16
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
