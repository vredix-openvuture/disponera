import QtQuick

// Calendar editor — relabel a calendar (name), recolour it with a full picker,
// give it a description and file it under a group. Everything persists to the
// local CalPrefs overrides (calendars.json), so it works uniformly for CalDAV,
// ICS and local calendars WITHOUT a server-side rename (a CalDAV PROPPATCH the
// backend doesn't do). openEdit(calId). Overlay dialog; pickers open as their
// own overlays so nothing grows the card.
Item {
    id: dlg
    property bool open: false
    property string calId: ""
    property var groupSuggestions: []       // existing group names, for quick-fill
    visible: open
    z: 520

    // push-loop merge (Array.concat on a QVariantList wrapper is O(n²)).
    function _merge(a, b) {
        var out = [], i; a = a ?? []; b = b ?? []
        for (i = 0; i < a.length; i++) out.push(a[i])
        for (i = 0; i < b.length; i++) out.push(b[i])
        return out
    }
    function _cal(id) {
        var cs = dlg._merge(CalDav.calendars, Local.calendars)
        for (var i = 0; i < cs.length; i++) if (cs[i].id === id) return cs[i]
        return null
    }
    readonly property var cal: dlg._cal(dlg.calId)
    readonly property string origName: dlg.cal ? (dlg.cal.name || "calendar") : "calendar"
    readonly property string origColor: dlg.cal ? (dlg.cal.color || "") : ""

    property string selColor: ""

    function openEdit(id) {
        dlg.calId = id
        var c = dlg._cal(id)
        nameF.text = (CalPrefs.names[id] || (c ? c.name || "" : ""))
        descF.text = (CalPrefs.descriptions[id] || "")
        groupF.text = (CalPrefs.groups[id] || "")
        dlg.selColor = (CalPrefs.colors[id] || (c ? c.color || "" : ""))
        // gather existing groups (deduped) as quick-fill chips
        var seen = {}, out = []
        var gs = CalPrefs.groups || {}
        for (var k in gs) { var g = (gs[k] || "").trim(); if (g && !seen[g]) { seen[g] = 1; out.push(g) } }
        dlg.groupSuggestions = out
        dlg.open = true
    }

    function submit() {
        // A name equal to the calendar's own is stored as "" (no override) so the
        // relabel cleanly falls back if the source name later changes.
        var nm = nameF.text.trim()
        CalPrefs.apply(dlg.calId, {
            name: (nm === dlg.origName ? "" : nm),
            color: dlg.selColor,
            description: descF.text.trim(),
            group: groupF.text.trim()
        })
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

            Row {
                width: parent.width; spacing: 10
                Rectangle { anchors.verticalCenter: parent.verticalCenter
                            width: 16; height: 16; radius: 8
                            color: dlg.selColor !== "" ? dlg.selColor : Theme.boActive }
                Text { anchors.verticalCenter: parent.verticalCenter
                       text: "Edit calendar"; color: Theme.fgBright
                       font.pixelSize: 18; font.bold: true; font.family: Theme.fontFamily }
            }

            Column {
                width: parent.width; spacing: 5
                Text { text: "Name"; color: Theme.fgMuted; font.pixelSize: 12; font.family: Theme.fontFamily }
                SettingsField { id: nameF; width: parent.width; placeholder: dlg.origName }
            }

            Row {
                width: parent.width; spacing: 12
                Column {
                    width: (parent.width - 12) / 2; spacing: 5
                    Text { text: "Colour"; color: Theme.fgMuted; font.pixelSize: 12; font.family: Theme.fontFamily }
                    ColorField { width: parent.width; color: dlg.selColor; onPicked: c => dlg.selColor = c }
                }
                Column {
                    width: (parent.width - 12) / 2; spacing: 5
                    Text { text: "Group"; color: Theme.fgMuted; font.pixelSize: 12; font.family: Theme.fontFamily }
                    SettingsField { id: groupF; width: parent.width; placeholder: "ungrouped" }
                }
            }
            // Quick-fill chips for the groups that already exist.
            Flow {
                width: parent.width; spacing: 6; visible: dlg.groupSuggestions.length > 0
                Repeater {
                    model: dlg.groupSuggestions
                    delegate: Rectangle {
                        required property var modelData
                        readonly property bool on: groupF.text.trim() === modelData
                        height: 24; radius: 12; width: gcT.implicitWidth + 22
                        color: on ? Qt.alpha(Theme.accent, 0.3) : gcHov.containsMouse ? Theme.bgSecondary : Theme.bgElement
                        Text { id: gcT; anchors.centerIn: parent; text: modelData
                               color: parent.on ? Theme.fgBright : Theme.fgPrimary
                               font.pixelSize: 12; font.family: Theme.fontFamily }
                        MouseArea { id: gcHov; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: groupF.text = modelData }
                    }
                }
            }

            Column {
                width: parent.width; spacing: 5
                Text { text: "Description"; color: Theme.fgMuted; font.pixelSize: 12; font.family: Theme.fontFamily }
                NotesField { id: descF; width: parent.width; placeholder: "optional description" }
            }

            Text {
                width: parent.width; wrapMode: Text.WordWrap
                text: "󰋽 Name, colour, description & group are stored locally in Disponera — they relabel the calendar in this app without touching the server."
                color: Theme.fgMuted; font.pixelSize: 11; font.family: Theme.fontFamily
            }

            // actions
            Item {
                width: parent.width; height: 36
                Row {
                    anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                    spacing: 8
                    Rectangle {
                        width: rstLbl.implicitWidth + 24; height: 36; radius: 8
                        color: rstHov.containsMouse ? Theme.bgSecondary : Theme.bgElement
                        Text { id: rstLbl; anchors.centerIn: parent; text: "󰦛  Reset"; color: Theme.fgMuted
                               font.pixelSize: 13; font.family: Theme.fontFamily }
                        MouseArea { id: rstHov; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                nameF.text = ""; descF.text = ""; groupF.text = ""
                                dlg.selColor = dlg.origColor
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
                        color: savHov.containsMouse ? Theme.bgHover : Theme.accent
                        Text { id: savLbl; anchors.centerIn: parent; text: "󰄬  Save"; color: Theme.fgBright
                               font.pixelSize: 14; font.bold: true; font.family: Theme.fontFamily }
                        MouseArea { id: savHov; anchors.fill: parent; hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor; onClicked: dlg.submit() }
                    }
                }
            }
        }
    }
}
