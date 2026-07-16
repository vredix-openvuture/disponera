import QtQuick
import QtQuick.Layouts
import "components"

// Settings tab (blueprint #5): a left SIDEBAR of sections (icon + text) plus a
// main card that shows the selected section — mirrors velumeron's settings,
// replacing the old flat scroll.
Item {
    id: pane

    property int section: 0
    readonly property var sections: [
        { icon: "󰏘", label: "Appearance" },
        { icon: "󰃭", label: "Calendar" },
        { icon: "󰛳", label: "Integrations" },
        { icon: "󰉒", label: "Local lists" }]

    // ── Sidebar ──────────────────────────────────────────────────────────────
    Rectangle {
        id: sidebar
        anchors { left: parent.left; top: parent.top; bottom: parent.bottom; margins: 20 }
        width: 220; radius: 14; color: Theme.bgElement

        Column {
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 10 }
            spacing: 4

            Text {
                text: "Settings"; color: Theme.fgBright
                font.pixelSize: 16; font.bold: true; font.family: Theme.fontFamily
                leftPadding: 8; topPadding: 8; bottomPadding: 10
            }
            Repeater {
                model: pane.sections
                delegate: Rectangle {
                    required property var modelData
                    required property int index
                    readonly property bool on: pane.section === index
                    width: parent.width; height: 44; radius: 10
                    color: on ? Qt.alpha(Theme.accent, 0.30)
                         : secHov.containsMouse ? Theme.bgSecondary : "transparent"
                    Behavior on color { ColorAnimation { duration: 100 } }
                    Text {
                        anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
                        text: modelData.icon; color: on ? Theme.fgBright : Theme.fgMuted
                        font.pixelSize: 17; font.family: Theme.fontFamily
                    }
                    Text {
                        anchors { left: parent.left; leftMargin: 44; verticalCenter: parent.verticalCenter }
                        text: modelData.label; color: on ? Theme.fgBright : Theme.fgPrimary
                        font.pixelSize: 14; font.bold: on; font.family: Theme.fontFamily
                    }
                    MouseArea { id: secHov; anchors.fill: parent; hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor; onClicked: pane.section = index }
                }
            }
        }
    }

    // ── Main card ────────────────────────────────────────────────────────────
    Rectangle {
        anchors { left: sidebar.right; right: parent.right; top: parent.top; bottom: parent.bottom
                  leftMargin: 18; rightMargin: 20; topMargin: 20; bottomMargin: 20 }
        radius: 14; color: Theme.surface
        border.width: 1; border.color: Qt.alpha(Theme.boNormal, 0.4)

        Text {
            id: cardHeader
            anchors { left: parent.left; top: parent.top; margins: 22 }
            text: pane.sections[pane.section].label
            color: Theme.fgBright; font.pixelSize: 20; font.bold: true; font.family: Theme.fontFamily
        }
        Rectangle {
            anchors { left: parent.left; right: parent.right; top: cardHeader.bottom; topMargin: 14; leftMargin: 22; rightMargin: 22 }
            height: 1; color: Qt.alpha(Theme.boNormal, 0.35)
        }

        StackLayout {
            anchors { left: parent.left; right: parent.right; top: cardHeader.bottom; bottom: parent.bottom
                      topMargin: 24; leftMargin: 22; rightMargin: 22; bottomMargin: 22 }
            currentIndex: pane.section

            SettingsAppearance {}
            SettingsCalendar {}
            SettingsIntegrations {}
            SettingsLists {}
        }
    }
}
