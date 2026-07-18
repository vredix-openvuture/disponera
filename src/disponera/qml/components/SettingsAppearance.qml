import QtQuick

// Settings › Appearance: theme selection. "Auto" follows the live wallust
// palette; the named presets pin a fixed palette (theme.py THEMES).
Flickable {
    id: sec
    contentHeight: col.implicitHeight + 8
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    readonly property var themeList: [
        { id: "auto",       label: "Auto",       accent: "",        bg: "",        alt: "" },
        { id: "gruvbox",    label: "Gruvbox",    accent: "#fe8019", bg: "#1d2021", alt: "#3c3836" },
        { id: "dracula",    label: "Dracula",    accent: "#bd93f9", bg: "#282a36", alt: "#44475a" },
        { id: "nord",       label: "Nord",       accent: "#88c0d0", bg: "#2e3440", alt: "#434c5e" },
        { id: "catppuccin", label: "Catppuccin", accent: "#cba6f7", bg: "#1e1e2e", alt: "#45475a" },
        { id: "tokyonight", label: "Tokyo Night",accent: "#7aa2f7", bg: "#1a1b26", alt: "#3b4261" }]

    Column {
        id: col
        width: parent.width
        spacing: 12

        SectionLabel { text: "THEME" }
        Text {
            width: parent.width; wrapMode: Text.WordWrap; leftPadding: 4
            text: "Auto tracks your live wallust colours; a preset pins a fixed palette."
            color: Theme.fgMuted; font.pixelSize: 13; font.family: Theme.fontFamily
        }

        Flow {
            width: parent.width; spacing: 12
            Repeater {
                model: sec.themeList
                delegate: Rectangle {
                    id: card
                    required property var modelData
                    readonly property bool on: Settings.theme === modelData.id
                    readonly property bool isAuto: modelData.id === "auto"
                    width: 172; height: 86; radius: 14
                    color: isAuto ? Theme.bgPrimary : modelData.bg
                    border.width: on ? 2 : 1
                    border.color: on ? Theme.accent : Qt.alpha(Theme.boNormal, 0.5)
                    Behavior on border.color { ColorAnimation { duration: 120 } }

                    // mini palette preview: accent dot + two surface bars
                    Rectangle {
                        id: dot
                        anchors { left: parent.left; leftMargin: 14; top: parent.top; topMargin: 14 }
                        width: 20; height: 20; radius: 10
                        color: card.isAuto ? Theme.accent : card.modelData.accent
                    }
                    Column {
                        anchors { left: dot.right; leftMargin: 10; verticalCenter: dot.verticalCenter }
                        spacing: 4
                        Rectangle { width: 84; height: 7; radius: 3.5
                                    color: card.isAuto ? Theme.bgElement : card.modelData.alt }
                        Rectangle { width: 56; height: 7; radius: 3.5
                                    color: card.isAuto ? Theme.bgSecondary : Qt.lighter(card.modelData.alt, 1.25) }
                    }
                    // check badge when active
                    Rectangle {
                        visible: card.on
                        anchors { right: parent.right; top: parent.top; rightMargin: 12; topMargin: 12 }
                        width: 20; height: 20; radius: 10; color: Theme.accent
                        Text { anchors.centerIn: parent; text: "󰄬"; color: Theme.fgBright
                               font.pixelSize: 12; font.family: Theme.fontFamily }
                    }
                    Text {
                        anchors { left: parent.left; leftMargin: 16; bottom: parent.bottom; bottomMargin: 12
                                  right: parent.right; rightMargin: 12 }
                        elide: Text.ElideRight; text: card.modelData.label
                        color: card.isAuto ? Theme.fgBright : "#f2f2f2"
                        font.pixelSize: 14; font.weight: Font.Medium; font.bold: card.on; font.family: Theme.fontFamily
                    }
                    MouseArea { anchors.fill: parent; hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor; onClicked: Settings.setTheme(card.modelData.id) }
                }
            }
        }
    }
}
