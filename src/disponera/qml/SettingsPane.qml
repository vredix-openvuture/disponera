import QtQuick
import QtQuick.Layouts
import "components"

// Settings tab: a left sidebar of sections (icon + label + hint) and a main card
// that shows the selected section under a sticky header. Sections crossfade in.
Item {
    id: pane

    property int section: 0
    readonly property var sections: [
        { icon: "󰒓", label: "General",      hint: "Startup, clock",
          blurb: "Launch behaviour and how times are shown." },
        { icon: "󰏘", label: "Appearance",   hint: "Theme, colours",
          blurb: "Follow your live wallust palette or pin a preset." },
        { icon: "󰃭", label: "Calendar",     hint: "Grid & events",
          blurb: "View defaults, the visible day range and how events render." },
        { icon: "󰛳", label: "Integrations", hint: "CalDAV, ICS",
          blurb: "Connect calendar servers and subscribe to feeds." },
        { icon: "󰉒", label: "Local lists",  hint: "On this machine",
          blurb: "Calendars and todo lists stored locally, no server needed." },
        { icon: "󰋼", label: "About",        hint: "Version & status",
          blurb: "What Disponera is and where it keeps your preferences." }]

    // ── Sidebar ──────────────────────────────────────────────────────────────
    Rectangle {
        id: sidebar
        anchors { left: parent.left; top: parent.top; bottom: parent.bottom; margins: 20 }
        width: 236; radius: 18; color: Theme.surface
        border.width: 1; border.color: Qt.alpha(Theme.boNormal, 0.25)

        Text {
            id: sbTitle
            anchors { left: parent.left; top: parent.top; leftMargin: 20; topMargin: 20 }
            text: "Settings"; color: Theme.fgBright
            font.pixelSize: 19; font.bold: true; font.family: Theme.fontFamily
        }

        Column {
            anchors { left: parent.left; right: parent.right; top: sbTitle.bottom
                      leftMargin: 12; rightMargin: 12; topMargin: 16 }
            spacing: 4
            Repeater {
                model: pane.sections
                delegate: Rectangle {
                    id: secRow
                    required property var modelData
                    required property int index
                    readonly property bool on: pane.section === index
                    width: parent.width; height: 54; radius: 12
                    color: on ? Qt.alpha(Theme.accent, 0.16)
                         : secHov.containsMouse ? Theme.bgElement : "transparent"
                    Behavior on color { ColorAnimation { duration: 110 } }

                    Rectangle {   // active accent bar
                        anchors { left: parent.left; leftMargin: 4; verticalCenter: parent.verticalCenter }
                        width: 3; height: secRow.on ? 26 : 0; radius: 1.5; color: Theme.accent
                        Behavior on height { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                    }
                    Text {
                        id: secIcon
                        anchors { left: parent.left; leftMargin: 18; verticalCenter: parent.verticalCenter }
                        text: secRow.modelData.icon; color: secRow.on ? Theme.accent : Theme.fgMuted
                        font.pixelSize: 18; font.family: Theme.fontFamily
                    }
                    Column {
                        anchors { left: secIcon.right; leftMargin: 14; right: parent.right; rightMargin: 10
                                  verticalCenter: parent.verticalCenter }
                        spacing: 1
                        Text { text: secRow.modelData.label
                               color: secRow.on ? Theme.fgBright : Theme.fgPrimary
                               font.pixelSize: 15; font.weight: Font.Medium
                               font.bold: secRow.on; font.family: Theme.fontFamily }
                        Text { width: parent.width; elide: Text.ElideRight; text: secRow.modelData.hint
                               color: Theme.fgMuted; font.pixelSize: 12; font.family: Theme.fontFamily }
                    }
                    MouseArea { id: secHov; anchors.fill: parent; hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor; onClicked: pane.section = index }
                }
            }
        }

        Text {   // footer version
            anchors { left: parent.left; bottom: parent.bottom; leftMargin: 20; bottomMargin: 18 }
            text: "Disponera  ·  v" + Settings.version
            color: Qt.alpha(Theme.fgMuted, 0.8); font.pixelSize: 12; font.family: Theme.fontFamily
        }
    }

    // ── Main card ────────────────────────────────────────────────────────────
    Rectangle {
        anchors { left: sidebar.right; right: parent.right; top: parent.top; bottom: parent.bottom
                  leftMargin: 18; rightMargin: 20; topMargin: 20; bottomMargin: 20 }
        radius: 18; color: Theme.surface
        border.width: 1; border.color: Qt.alpha(Theme.boNormal, 0.25)

        // Sticky header
        Item {
            id: header
            anchors { left: parent.left; right: parent.right; top: parent.top }
            height: 78
            Column {
                anchors { left: parent.left; leftMargin: 26; verticalCenter: parent.verticalCenter
                          right: parent.right; rightMargin: 26 }
                spacing: 4
                Text { text: pane.sections[pane.section].label; color: Theme.fgBright
                       font.pixelSize: 22; font.bold: true; font.family: Theme.fontFamily }
                Text { width: parent.width; elide: Text.ElideRight
                       text: pane.sections[pane.section].blurb; color: Theme.fgMuted
                       font.pixelSize: 13; font.family: Theme.fontFamily }
            }
            Rectangle { anchors { left: parent.left; right: parent.right; bottom: parent.bottom
                                  leftMargin: 26; rightMargin: 26 }
                        height: 1; color: Qt.alpha(Theme.boNormal, 0.3) }
        }

        // Section body — crossfades on change
        StackLayout {
            id: stack
            anchors { left: parent.left; right: parent.right; top: header.bottom; bottom: parent.bottom
                      topMargin: 20; leftMargin: 26; rightMargin: 26; bottomMargin: 22 }
            currentIndex: pane.section
            opacity: 1
            SettingsGeneral {}
            SettingsAppearance {}
            SettingsCalendar {}
            SettingsIntegrations {}
            SettingsLists {}
            SettingsAbout {}
        }
        Connections {
            target: pane
            function onSectionChanged() { fade.restart() }
        }
        NumberAnimation { id: fade; target: stack; property: "opacity"
                          from: 0.0; to: 1.0; duration: 170; easing.type: Easing.OutCubic }
    }
}
