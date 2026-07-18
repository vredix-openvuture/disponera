import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs

// Colour field: shows the current swatch + hex, opens an overlay Popup with a
// preset palette, a full visual colour picker (native ColorDialog) and a
// custom-hex entry. `color` is "#rrggbb" or "" (none).
// Emits picked(color). Overlay popup, never grows the card (blueprint #2/#3).
Item {
    id: cf
    property string color: ""
    property bool allowEmpty: true
    signal picked(string color)
    readonly property alias open: pop.opened
    implicitHeight: 38

    // A calm, legible palette (mirrors common project-accent choices).
    readonly property var swatches: [
        "#e06c75", "#e5875a", "#e5c07b", "#98c379", "#56b6c2", "#61afef",
        "#c678dd", "#d17bb0", "#a3785a", "#8a92a6", "#5c6370", "#d1495b"]

    function _norm(c) { return (c || "").trim().toLowerCase() }
    function _hex(c) {   // QColor → "#rrggbb"
        return "#" + [c.r, c.g, c.b].map(function (x) {
            var s = Math.round(x * 255).toString(16); return s.length === 1 ? "0" + s : s
        }).join("")
    }

    ColorDialog {
        id: colorDlg
        selectedColor: cf.color !== "" ? cf.color : "#e5c07b"
        onAccepted: { var h = cf._hex(selectedColor); cf.color = h; cf.picked(h); pop.close() }
    }

    Rectangle {
        id: disp
        anchors.fill: parent; radius: 8; color: Theme.bgPrimary
        border.width: pop.opened ? 1 : 0; border.color: Theme.accent
        Rectangle {
            id: sw
            anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
            width: 16; height: 16; radius: 8
            color: cf.color !== "" ? cf.color : "transparent"
            border.width: cf.color === "" ? 1 : 0; border.color: Theme.fgMuted
        }
        Text {
            anchors { left: sw.right; leftMargin: 10; right: chev.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
            elide: Text.ElideRight
            text: cf.color !== "" ? cf.color : "no colour"
            color: cf.color !== "" ? Theme.fgBright : Theme.fgMuted
            font.pixelSize: 14; font.family: Theme.fontFamily
        }
        Text { id: chev; anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
               text: pop.opened ? "󰅃" : "󰅀"; color: Theme.fgMuted; font.pixelSize: 13; font.family: Theme.fontFamily }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                    onClicked: pop.opened ? pop.close() : pop.open() }
    }

    Popup {
        id: pop
        y: disp.height + 4; width: Math.max(disp.width, 232); padding: 12
        implicitHeight: popCol.implicitHeight + 24
        modal: false
        closePolicy: Popup.CloseOnPressOutside | Popup.CloseOnEscape
        onOpened: hexIn.text = cf.color
        background: Rectangle { radius: 10; color: Theme.surface
                                border.width: 1; border.color: Qt.alpha(Theme.boNormal, 0.6) }
        contentItem: Column {
            id: popCol
            spacing: 12
            Grid {
                columns: 6; columnSpacing: 8; rowSpacing: 8
                Repeater {
                    model: cf.swatches
                    delegate: Rectangle {
                        required property var modelData
                        width: 28; height: 28; radius: 14; color: modelData
                        border.width: cf._norm(cf.color) === cf._norm(modelData) ? 2 : 0
                        border.color: Theme.fgBright
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                            onClicked: { cf.color = modelData; cf.picked(modelData); pop.close() } }
                    }
                }
            }
            Row {
                spacing: 8
                Rectangle {
                    width: 130; height: 32; radius: 8; color: Theme.bgPrimary
                    border.width: hexIn.activeFocus ? 1 : 0; border.color: Theme.accent
                    Text { anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                           text: "#"; color: Theme.fgMuted; font.pixelSize: 14; font.family: Theme.fontFamily }
                    TextInput {
                        id: hexIn
                        anchors { left: parent.left; leftMargin: 22; right: parent.right; rightMargin: 8
                                  verticalCenter: parent.verticalCenter }
                        color: Theme.fgBright; font.pixelSize: 14; font.family: Theme.fontFamily
                        clip: true; selectByMouse: true
                        onTextChanged: text = text.replace(/[^0-9a-fA-F]/g, "").slice(0, 6)
                        onAccepted: if (text.length === 6) { cf.color = "#" + text; cf.picked(cf.color); pop.close() }
                    }
                }
                Rectangle {
                    width: 56; height: 32; radius: 8
                    color: applyHov.containsMouse ? Theme.bgHover : Theme.accent
                    opacity: hexIn.text.length === 6 ? 1 : 0.5
                    Text { anchors.centerIn: parent; text: "Set"; color: Theme.fgBright
                           font.pixelSize: 13; font.family: Theme.fontFamily }
                    MouseArea { id: applyHov; anchors.fill: parent; hoverEnabled: true
                        cursorShape: hexIn.text.length === 6 ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: if (hexIn.text.length === 6) { cf.color = "#" + hexIn.text; cf.picked(cf.color); pop.close() } }
                }
            }
            // Full visual picker (colour wheel / gradient) for any colour beyond
            // the presets — the "vollen Colorpicker" the swatches alone can't give.
            Rectangle {
                width: parent.width; height: 30; radius: 6
                color: fullHov.containsMouse ? Theme.bgHover : Theme.bgElement
                Row {
                    anchors.centerIn: parent; spacing: 8
                    Rectangle { anchors.verticalCenter: parent.verticalCenter
                                width: 16; height: 16; radius: 4
                                gradient: Gradient { orientation: Gradient.Horizontal
                                    GradientStop { position: 0.0; color: "#e06c75" }
                                    GradientStop { position: 0.5; color: "#98c379" }
                                    GradientStop { position: 1.0; color: "#61afef" } } }
                    Text { anchors.verticalCenter: parent.verticalCenter; text: "Full colour picker…"
                           color: Theme.fgPrimary; font.pixelSize: 13; font.family: Theme.fontFamily }
                }
                MouseArea { id: fullHov; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    onClicked: colorDlg.open() }
            }
            Rectangle {
                visible: cf.allowEmpty; width: parent.width; height: 28; radius: 6
                color: noneHov.containsMouse ? Theme.bgSecondary : "transparent"
                Text { anchors.centerIn: parent; text: "󰜺  No colour"; color: Theme.fgMuted
                       font.pixelSize: 12; font.family: Theme.fontFamily }
                MouseArea { id: noneHov; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    onClicked: { cf.color = ""; cf.picked(""); pop.close() } }
            }
        }
    }
}
