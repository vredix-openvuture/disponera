import QtQuick
import QtQuick.Controls

// Dropdown select: a fixed-height display field that opens a list in a REAL
// overlay Popup (rendered in the window's overlay layer, so it NEVER grows the
// card or pushes siblings — blueprint #2). Options are [{ key, label, color }]
// (color optional → a colour dot). Emits picked(key). CloseOnPressOutside means
// opening any other picker/popup closes this one, so only one is ever open (#3).
Item {
    id: pk
    property var options: []
    property string current: ""
    property string placeholder: "select…"
    signal picked(string key)
    readonly property alias open: pop.opened
    implicitHeight: 38

    function labelOf(k) {
        for (var i = 0; i < pk.options.length; i++) if (pk.options[i].key === k) return pk.options[i].label
        return ""
    }
    function colorOf(k) {
        for (var i = 0; i < pk.options.length; i++) if (pk.options[i].key === k) return pk.options[i].color || ""
        return ""
    }

    Rectangle {
        id: disp
        anchors.fill: parent
        radius: 8
        color: Theme.bgPrimary
        border.width: pop.opened ? 1 : 0; border.color: Theme.accent
        Rectangle {
            id: cdot
            visible: pk.colorOf(pk.current) !== ""
            anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
            width: 12; height: 12; radius: 6; color: visible ? pk.colorOf(pk.current) : "transparent"
        }
        Text {
            anchors { left: parent.left; leftMargin: cdot.visible ? 30 : 12; right: chev.left; rightMargin: 8
                      verticalCenter: parent.verticalCenter }
            elide: Text.ElideRight
            text: pk.current !== "" ? pk.labelOf(pk.current) : pk.placeholder
            color: pk.current !== "" ? Theme.fgBright : Theme.fgMuted
            font.pixelSize: 14; font.family: Theme.fontFamily
        }
        Text {
            id: chev
            anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
            text: pop.opened ? "󰅃" : "󰅀"; color: Theme.fgMuted; font.pixelSize: 13; font.family: Theme.fontFamily
        }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                    onClicked: pop.opened ? pop.close() : pop.open() }
    }

    Popup {
        id: pop
        y: disp.height + 4
        width: disp.width
        padding: 4
        implicitHeight: Math.min(214, listCol.implicitHeight + 8)
        modal: false
        closePolicy: Popup.CloseOnPressOutside | Popup.CloseOnEscape
        background: Rectangle {
            radius: 8; color: Theme.surface
            border.width: 1; border.color: Qt.alpha(Theme.boNormal, 0.6)
        }
        contentItem: Flickable {
            contentHeight: listCol.implicitHeight; clip: true
            boundsBehavior: Flickable.StopAtBounds
            Column {
                id: listCol
                width: parent.width
                Repeater {
                    model: pk.options
                    delegate: Rectangle {
                        required property var modelData
                        width: listCol.width; height: 32; radius: 6
                        color: optHov.containsMouse ? Theme.bgSecondary
                             : modelData.key === pk.current ? Qt.alpha(Theme.accent, 0.28) : "transparent"
                        Rectangle {
                            id: odot
                            visible: (modelData.color || "") !== ""
                            anchors { left: parent.left; leftMargin: 8; verticalCenter: parent.verticalCenter }
                            width: 10; height: 10; radius: 5; color: visible ? modelData.color : "transparent"
                        }
                        Text {
                            anchors { left: parent.left; leftMargin: odot.visible ? 26 : 10; right: parent.right
                                      rightMargin: 8; verticalCenter: parent.verticalCenter }
                            elide: Text.ElideRight; text: modelData.label
                            color: modelData.key === pk.current ? Theme.fgBright : Theme.fgPrimary
                            font.pixelSize: 14; font.family: Theme.fontFamily
                        }
                        MouseArea {
                            id: optHov
                            anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: { pk.current = modelData.key; pk.picked(modelData.key); pop.close() }
                        }
                    }
                }
            }
        }
    }
}
