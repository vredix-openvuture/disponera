import QtQuick

// Settings › Integrations: CalDAV connections (list + add). Provider icons and
// per-connection role live here (blueprint #6). Accounts are the same ones the
// shell's caldav-client.py owns (caldav-accounts.json).
Flickable {
    id: sec
    contentHeight: col.implicitHeight + 8
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    // Provider presets: icon + URL hint, keyed off the account name/URL. iCloud
    // and Google are ordinary CalDAV servers, so they work over the same client.
    function _provider(name, url) {
        var s = ((name || "") + " " + (url || "")).toLowerCase()
        if (s.indexOf("icloud") >= 0 || s.indexOf("apple") >= 0) return { icon: "󰘲", label: "iCloud" }
        if (s.indexOf("google") >= 0 || s.indexOf("gmail") >= 0)  return { icon: "󰊭", label: "Google" }
        if (s.indexOf("nextcloud") >= 0)                          return { icon: "󰅟", label: "Nextcloud" }
        if (s.indexOf("vikunja") >= 0 || s.indexOf("/dav/") >= 0) return { icon: "󰸞", label: "Vikunja" }
        if (s.indexOf(".ics") >= 0)                               return { icon: "󰃭", label: "ICS feed" }
        return { icon: "󰛳", label: "CalDAV" }
    }

    Column {
        id: col
        width: parent.width
        spacing: 16

        Text { text: "CalDAV connections"; color: Theme.fgBright
               font.pixelSize: 17; font.bold: true; font.family: Theme.fontFamily }

        Text {
            visible: (CalDav.accounts ?? []).length === 0
            text: "No connection yet. Add one below — Nextcloud, iCloud, Google or any CalDAV server."
            color: Theme.fgMuted; font.pixelSize: 14; font.family: Theme.fontFamily; width: parent.width; wrapMode: Text.WordWrap
        }

        // Existing connections
        Repeater {
            model: CalDav.accounts ?? []
            delegate: Rectangle {
                id: acc
                required property var modelData
                readonly property var prov: sec._provider(acc.modelData.name, acc.modelData.url)
                readonly property int calN: (CalDav.calendars ?? []).filter(c => c.account === acc.modelData.name && c.vevent).length
                readonly property int taskN: (CalDav.calendars ?? []).filter(c => c.account === acc.modelData.name && c.vtodo).length
                readonly property string role: (Local.roles[acc.modelData.name]) || "both"
                width: parent.width; height: 108; radius: 12; color: Theme.bgPrimary
                border.width: 1; border.color: Qt.alpha(Theme.boNormal, 0.4)

                Rectangle {   // provider icon badge
                    id: badge
                    anchors { left: parent.left; leftMargin: 14; top: parent.top; topMargin: 14 }
                    width: 38; height: 38; radius: 10; color: Theme.bgElement
                    Text { anchors.centerIn: parent; text: acc.prov.icon; color: Theme.fgBright
                           font.pixelSize: 19; font.family: Theme.fontFamily }
                    Rectangle {   // status dot
                        anchors { right: parent.right; top: parent.top; rightMargin: -2; topMargin: -2 }
                        width: 12; height: 12; radius: 6
                        color: acc.modelData.ok ? "#98c379" : Theme.fgUrgent
                        border.width: 2; border.color: Theme.surface
                    }
                }
                // editable connection name
                Rectangle {
                    id: nameBox
                    anchors { left: badge.right; leftMargin: 14; right: rm.left; rightMargin: 12; top: parent.top; topMargin: 14 }
                    height: 34; radius: 8; color: nameIn.activeFocus ? Theme.bgPrimary : "transparent"
                    border.width: nameIn.activeFocus ? 1 : 0; border.color: Theme.accent
                    TextInput {
                        id: nameIn
                        anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
                        verticalAlignment: TextInput.AlignVCenter
                        text: acc.modelData.name || "connection"
                        color: Theme.fgBright; font.pixelSize: 15; font.bold: true; font.family: Theme.fontFamily
                        clip: true; selectByMouse: true
                        onEditingFinished: if (text.trim() !== "" && text.trim() !== acc.modelData.name)
                                               CalDav.renameAccount(acc.modelData.name, text.trim())
                    }
                }
                Text {
                    anchors { left: badge.right; leftMargin: 22; right: rm.left; rightMargin: 12; top: nameBox.bottom; topMargin: 2 }
                    elide: Text.ElideRight
                    text: (acc.modelData.error && acc.modelData.error !== "")
                          ? "󰀦 " + acc.modelData.error
                          : acc.prov.label + " · " + acc.calN + " calendars · " + acc.taskN + " task lists"
                    color: (acc.modelData.error && acc.modelData.error !== "") ? Theme.fgUrgent : Theme.fgMuted
                    font.pixelSize: 12; font.family: Theme.fontFamily
                }
                // Use-for role: Tasks / Calendar / Both (blueprint #6)
                Row {
                    anchors { left: badge.right; leftMargin: 22; bottom: parent.bottom; bottomMargin: 12 }
                    spacing: 6
                    Text { anchors.verticalCenter: parent.verticalCenter; text: "Use for"
                           color: Theme.fgMuted; font.pixelSize: 12; font.family: Theme.fontFamily }
                    Repeater {
                        model: [{ v: "both", l: "Both" }, { v: "tasks", l: "Tasks" }, { v: "calendar", l: "Calendar" }]
                        delegate: Rectangle {
                            required property var modelData
                            readonly property bool on: acc.role === modelData.v
                            width: roleLbl.implicitWidth + 20; height: 26; radius: 13
                            color: on ? Qt.alpha(Theme.accent, 0.35)
                                 : roleHov.containsMouse ? Theme.bgSecondary : Theme.bgElement
                            Text { id: roleLbl; anchors.centerIn: parent; text: modelData.l
                                   color: on ? Theme.fgBright : Theme.fgPrimary
                                   font.pixelSize: 12; font.bold: on; font.family: Theme.fontFamily }
                            MouseArea { id: roleHov; anchors.fill: parent; hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: Local.setRole(acc.modelData.name, modelData.v) }
                        }
                    }
                }
                Rectangle {
                    id: rm
                    anchors { right: parent.right; rightMargin: 12; top: parent.top; topMargin: 16 }
                    width: 34; height: 34; radius: 8
                    color: rmHov.containsMouse ? Qt.alpha(Theme.fgUrgent, 0.2) : "transparent"
                    Text { anchors.centerIn: parent; text: "󰩹"
                           color: rmHov.containsMouse ? Theme.fgUrgent : Theme.fgMuted
                           font.pixelSize: 16; font.family: Theme.fontFamily }
                    MouseArea { id: rmHov; anchors.fill: parent; hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: CalDav.removeAccount(acc.modelData.name) }
                }
            }
        }

        // Add-connection form
        Rectangle {
            width: parent.width; height: addCol.implicitHeight + 32; radius: 12; color: Theme.bgElement

            Column {
                id: addCol
                property string pendingName: ""
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 16 }
                spacing: 10

                Text { text: "Add connection"; color: Theme.fgPrimary
                       font.pixelSize: 14; font.bold: true; font.family: Theme.fontFamily }

                // Provider presets — pre-fill the URL/name hint.
                Row {
                    spacing: 8
                    Repeater {
                        model: [
                            { icon: "󰅟", label: "Nextcloud", url: "https://cloud.example.com/remote.php/dav/" },
                            { icon: "󰘲", label: "iCloud",    url: "https://caldav.icloud.com/" },
                            { icon: "󰊭", label: "Google",    url: "https://apidata.googleusercontent.com/caldav/v2/" },
                            { icon: "󰛳", label: "Generic",   url: "https://" }]
                        delegate: Rectangle {
                            required property var modelData
                            width: presetTxt.implicitWidth + 34; height: 32; radius: 8
                            color: presetHov.containsMouse ? Theme.bgHover : Theme.bgSecondary
                            Text { id: presetTxt; anchors.centerIn: parent
                                   text: modelData.icon + "  " + modelData.label
                                   color: Theme.fgPrimary; font.pixelSize: 12; font.family: Theme.fontFamily }
                            MouseArea { id: presetHov; anchors.fill: parent; hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: { fName.text = modelData.label === "Generic" ? "" : modelData.label
                                             fUrl.text = modelData.url } }
                        }
                    }
                }

                SettingsField { id: fName; width: parent.width; placeholder: "name (e.g. Nextcloud)" }
                SettingsField { id: fUrl;  width: parent.width; placeholder: "server URL (https://…/dav/)" }
                SettingsField { id: fUser; width: parent.width; placeholder: "username" }
                SettingsField { id: fPass; width: parent.width; placeholder: "app password"; password: true }

                Row {
                    spacing: 12
                    Rectangle {
                        width: addBtnLbl.implicitWidth + 34; height: 36; radius: 8
                        readonly property bool ready: fName.text.trim() !== "" && fUrl.text.trim() !== ""
                                                      && fUser.text.trim() !== "" && fPass.text !== ""
                        color: !ready ? Theme.bgSecondary : addHov.containsMouse ? Theme.bgHover : Theme.accent
                        opacity: ready ? 1.0 : 0.5
                        Text { id: addBtnLbl; anchors.centerIn: parent; text: "󰐕  Connect"
                               color: Theme.fgBright; font.pixelSize: 14; font.family: Theme.fontFamily }
                        MouseArea { id: addHov; anchors.fill: parent; hoverEnabled: true
                            cursorShape: parent.ready ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: {
                                if (!parent.ready) return
                                addCol.pendingName = fName.text.trim()
                                CalDav.addAccount(fName.text.trim(), fUrl.text.trim(), fUser.text.trim(), fPass.text)
                            } }
                    }
                    Text { anchors.verticalCenter: parent.verticalCenter
                           text: CalDav.syncing ? "connecting…" : "stored locally, chmod 600 — use an app password"
                           color: Theme.fgMuted; font.pixelSize: 12; font.family: Theme.fontFamily }
                }

                Text {
                    visible: addCol.pendingName !== "" && CalDav.lastError !== "" && !CalDav.syncing
                    width: parent.width; wrapMode: Text.WordWrap
                    text: "󰀦 " + CalDav.lastError
                    color: Theme.fgUrgent; font.pixelSize: 12; font.family: Theme.fontFamily
                }

                Connections {
                    target: CalDav
                    function onCacheChanged() {
                        if (addCol.pendingName === "") return
                        var accs = CalDav.accounts ?? []
                        for (var i = 0; i < accs.length; i++)
                            if (accs[i].name === addCol.pendingName) {
                                fName.text = ""; fUrl.text = ""; fUser.text = ""; fPass.text = ""
                                addCol.pendingName = ""; return
                            }
                    }
                }
            }
        }

        // ── ICS subscriptions (read-only calendar feeds) ─────────────────────
        Item { width: parent.width; height: 6 }
        Text { text: "Subscribed calendars (ICS)"; color: Theme.fgBright
               font.pixelSize: 17; font.bold: true; font.family: Theme.fontFamily }
        Text {
            width: parent.width; wrapMode: Text.WordWrap
            text: "Read-only .ics feeds (holidays, shared calendars, …). Fetched and shown in the Calendar tab."
            color: Theme.fgMuted; font.pixelSize: 13; font.family: Theme.fontFamily
        }

        Repeater {
            model: Local.icsSubs ?? []
            delegate: Rectangle {
                id: ics
                required property var modelData
                width: parent.width; height: 56; radius: 12; color: Theme.bgPrimary
                border.width: 1; border.color: Qt.alpha(Theme.boNormal, 0.4)
                Rectangle {
                    id: icsDot
                    anchors { left: parent.left; leftMargin: 16; verticalCenter: parent.verticalCenter }
                    width: 12; height: 12; radius: 6
                    color: (ics.modelData.color && ics.modelData.color !== "") ? ics.modelData.color : Theme.accent
                }
                Column {
                    anchors { left: icsDot.right; leftMargin: 14; right: icsRm.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
                    spacing: 2
                    Text { width: parent.width; elide: Text.ElideRight; text: ics.modelData.name || "feed"
                           color: Theme.fgBright; font.pixelSize: 14; font.bold: true; font.family: Theme.fontFamily }
                    Text { width: parent.width; elide: Text.ElideRight; text: ics.modelData.url
                           color: Theme.fgMuted; font.pixelSize: 12; font.family: Theme.fontFamily }
                }
                Rectangle {
                    id: icsRm
                    anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                    width: 34; height: 34; radius: 8
                    color: icsRmHov.containsMouse ? Qt.alpha(Theme.fgUrgent, 0.2) : "transparent"
                    Text { anchors.centerIn: parent; text: "󰩹"
                           color: icsRmHov.containsMouse ? Theme.fgUrgent : Theme.fgMuted
                           font.pixelSize: 16; font.family: Theme.fontFamily }
                    MouseArea { id: icsRmHov; anchors.fill: parent; hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor; onClicked: Local.removeIcs(ics.modelData.id) }
                }
            }
        }

        Rectangle {
            width: parent.width; height: icsCol.implicitHeight + 32; radius: 12; color: Theme.bgElement
            Column {
                id: icsCol
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 16 }
                spacing: 10
                Text { text: "Subscribe to ICS feed"; color: Theme.fgPrimary
                       font.pixelSize: 14; font.bold: true; font.family: Theme.fontFamily }
                Row {
                    width: parent.width; spacing: 10
                    SettingsField { id: icsName; width: 180; placeholder: "name" }
                    SettingsField { id: icsUrl; width: parent.width - 180 - 120 - 20; placeholder: "https://…/basic.ics" }
                    ColorField { id: icsColor; width: 120; color: ""; onPicked: c => icsColor.color = c }
                }
                Rectangle {
                    width: subLbl.implicitWidth + 34; height: 36; radius: 8
                    readonly property bool ready: icsUrl.text.trim() !== ""
                    color: !ready ? Theme.bgSecondary : subHov.containsMouse ? Theme.bgHover : Theme.accent
                    opacity: ready ? 1.0 : 0.5
                    Text { id: subLbl; anchors.centerIn: parent; text: "󰐕  Subscribe"
                           color: Theme.fgBright; font.pixelSize: 14; font.family: Theme.fontFamily }
                    MouseArea { anchors.fill: parent; hoverEnabled: true; id: subHov
                        cursorShape: parent.ready ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: {
                            if (!parent.ready) return
                            Local.addIcs(icsName.text.trim(), icsUrl.text.trim(), icsColor.color)
                            icsName.text = ""; icsUrl.text = ""; icsColor.color = ""
                        } }
                }
            }
        }
    }
}
