import QtQuick

// Settings › Appearance: theme + week start. (Extracted from the old flat
// SettingsPane into a section shown inside the settings card — blueprint #5.)
Flickable {
    id: sec
    contentHeight: col.implicitHeight + 8
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    readonly property var dows: [
        { v: 0, l: "Sunday" }, { v: 1, l: "Monday" }, { v: 6, l: "Saturday" }]
    readonly property var themeList: [
        { id: "auto",       label: "Auto (wallust)", accent: "", bg: "" },
        { id: "gruvbox",    label: "Gruvbox",    accent: "#fe8019", bg: "#1d2021" },
        { id: "dracula",    label: "Dracula",    accent: "#bd93f9", bg: "#282a36" },
        { id: "nord",       label: "Nord",       accent: "#88c0d0", bg: "#2e3440" },
        { id: "catppuccin", label: "Catppuccin", accent: "#cba6f7", bg: "#1e1e2e" },
        { id: "tokyonight", label: "Tokyo Night", accent: "#7aa2f7", bg: "#1a1b26" }]

    Column {
        id: col
        width: parent.width
        spacing: 22

        Text { text: "Theme"; color: Theme.fgBright; font.pixelSize: 17; font.bold: true; font.family: Theme.fontFamily }
        Flow {
            width: parent.width; spacing: 10
            Repeater {
                model: sec.themeList
                delegate: Rectangle {
                    required property var modelData
                    readonly property bool on: Settings.theme === modelData.id
                    readonly property bool isAuto: modelData.id === "auto"
                    width: 156; height: 52; radius: 10
                    color: isAuto ? Theme.surface : modelData.bg
                    border.width: on ? 2 : 1
                    border.color: on ? Theme.accent : Qt.alpha(Theme.boNormal, 0.5)
                    Rectangle {
                        anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                        width: 16; height: 16; radius: 8
                        color: isAuto ? Theme.accent : modelData.accent
                    }
                    Text {
                        anchors { left: parent.left; leftMargin: 38; right: parent.right; rightMargin: 10
                                  verticalCenter: parent.verticalCenter }
                        elide: Text.ElideRight; text: modelData.label
                        color: isAuto ? Theme.fgBright : "#f0f0f0"
                        font.pixelSize: 14; font.bold: parent.on; font.family: Theme.fontFamily
                    }
                    MouseArea { anchors.fill: parent; hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor; onClicked: Settings.setTheme(modelData.id) }
                }
            }
        }

        Text { text: "Week starts on"; color: Theme.fgBright; font.pixelSize: 17; font.bold: true; font.family: Theme.fontFamily }
        Row {
            spacing: 8
            Repeater {
                model: sec.dows
                delegate: Rectangle {
                    required property var modelData
                    readonly property bool on: Settings.firstDayOfWeek === modelData.v
                    width: dowLbl.implicitWidth + 30; height: 36; radius: 8
                    color: on ? Qt.alpha(Theme.accent, 0.35)
                         : dowHov.containsMouse ? Theme.bgSecondary : Theme.bgElement
                    Behavior on color { ColorAnimation { duration: 90 } }
                    Text { id: dowLbl; anchors.centerIn: parent; text: modelData.l
                           color: parent.on ? Theme.fgBright : Theme.fgPrimary
                           font.pixelSize: 14; font.bold: parent.on; font.family: Theme.fontFamily }
                    MouseArea { id: dowHov; anchors.fill: parent; hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor; onClicked: Settings.setFirstDayOfWeek(modelData.v) }
                }
            }
        }
    }
}
