import QtQuick

// Settings › About: app identity, version, live backend status and where prefs
// are stored.
Flickable {
    id: sec
    contentHeight: col.implicitHeight + 8
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    readonly property int accountN: (CalDav.accounts ?? []).length
    readonly property int calN: (CalDav.calendars ?? []).filter(c => c.vevent).length
    readonly property int listN: (Local.lists ?? []).length
    readonly property int icsN: (Local.icsSubs ?? []).length

    Column {
        id: col
        width: parent.width
        spacing: 12

        // Identity banner
        SettingCard {
            Item {
                width: parent.width; implicitHeight: 84
                Rectangle {
                    id: logo
                    anchors { left: parent.left; leftMargin: 18; verticalCenter: parent.verticalCenter }
                    width: 52; height: 52; radius: 14
                    color: Qt.alpha(Theme.accent, 0.18)
                    border.width: 1; border.color: Qt.alpha(Theme.accent, 0.5)
                    Text { anchors.centerIn: parent; text: "󰃭"; color: Theme.accent
                           font.pixelSize: 26; font.family: Theme.fontFamily }
                }
                Column {
                    anchors { left: logo.right; leftMargin: 16; right: verBadge.left; rightMargin: 12
                              verticalCenter: parent.verticalCenter }
                    spacing: 3
                    Text { text: "Disponera"; color: Theme.fgBright
                           font.pixelSize: 21; font.bold: true; font.family: Theme.fontFamily }
                    Text { width: parent.width; wrapMode: Text.WordWrap
                           text: "Calendar · Todos · Quick-notes — CalDAV-backed, markdown-first."
                           color: Theme.fgMuted; font.pixelSize: 13; font.family: Theme.fontFamily }
                }
                Rectangle {
                    id: verBadge
                    anchors { right: parent.right; rightMargin: 18; verticalCenter: parent.verticalCenter }
                    width: verTxt.implicitWidth + 20; height: 26; radius: 13; color: Theme.bgElement
                    Text { id: verTxt; anchors.centerIn: parent; text: "v" + Settings.version
                           color: Theme.fgPrimary; font.pixelSize: 13; font.weight: Font.Medium; font.family: Theme.fontFamily }
                }
            }
        }

        Item { width: 1; height: 6 }

        SectionLabel { text: "AT A GLANCE" }
        SettingCard {
            Item {
                width: parent.width; implicitHeight: 92
                Row {
                    anchors.centerIn: parent
                    spacing: 0
                    Repeater {
                        model: [
                            { n: sec.accountN, l: "connections" },
                            { n: sec.calN,     l: "calendars" },
                            { n: sec.listN,    l: "local lists" },
                            { n: sec.icsN,     l: "ICS feeds" }]
                        delegate: Item {
                            required property var modelData
                            required property int index
                            width: (sec.width - 36) / 4; height: 64
                            Column {
                                anchors.centerIn: parent; spacing: 4
                                Text { anchors.horizontalCenter: parent.horizontalCenter
                                       text: modelData.n; color: Theme.fgBright
                                       font.pixelSize: 26; font.bold: true; font.family: Theme.fontFamily }
                                Text { anchors.horizontalCenter: parent.horizontalCenter
                                       text: modelData.l; color: Theme.fgMuted
                                       font.pixelSize: 12; font.family: Theme.fontFamily }
                            }
                            Rectangle { visible: index > 0
                                        anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                                        width: 1; height: 34; color: Qt.alpha(Theme.boNormal, 0.3) }
                        }
                    }
                }
            }
        }

        Item { width: 1; height: 6 }

        SectionLabel { text: "SYSTEM" }
        SettingCard {
            Column {
                width: parent.width
                Repeater {
                    model: [
                        { k: "Theme source", v: Settings.theme === "auto" ? "wallust (live)" : Settings.theme },
                        { k: "UI font",      v: Theme.fontFamily },
                        { k: "Config folder",v: Settings.configDir }]
                    delegate: Column {
                        required property var modelData
                        required property int index
                        width: parent.width
                        Rectangle { visible: index > 0; width: parent.width - 36; x: 18
                                    height: 1; color: Qt.alpha(Theme.boNormal, 0.22) }
                        Item {
                            width: parent.width; height: 46
                            Text { anchors { left: parent.left; leftMargin: 18; verticalCenter: parent.verticalCenter }
                                   text: modelData.k; color: Theme.fgPrimary
                                   font.pixelSize: 14; font.family: Theme.fontFamily }
                            Text { anchors { right: parent.right; rightMargin: 18; left: parent.horizontalCenter
                                             verticalCenter: parent.verticalCenter }
                                   horizontalAlignment: Text.AlignRight; elide: Text.ElideMiddle
                                   text: modelData.v; color: Theme.fgMuted
                                   font.pixelSize: 13; font.family: Theme.fontFamily }
                        }
                    }
                }
            }
        }
    }
}
