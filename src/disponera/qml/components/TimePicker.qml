import QtQuick
import QtQuick.Controls

// Time field with a dropdown of half-hour slots in an overlay Popup (no manual
// typing, no card growth — blueprint #2/#3). `hm` holds "HH:MM" ("" = all-day /
// no time). Emits picked(hm).
Item {
    id: tpk
    property string hm: ""
    property string placeholder: "all day"
    signal picked(string hm)
    readonly property alias open: pop.opened
    implicitHeight: 38

    readonly property var slots: {
        var out = [""]                       // "" = no time
        for (var h = 0; h < 24; h++)
            for (var m = 0; m < 60; m += 30)
                out.push((h < 10 ? "0" : "") + h + ":" + (m < 10 ? "0" : "") + m)
        return out
    }

    Rectangle {
        id: disp
        anchors.fill: parent
        radius: 8
        color: Theme.bgPrimary
        border.width: pop.opened ? 1 : 0; border.color: Theme.accent
        Text { anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
               text: "󰥔"; color: Theme.fgMuted; font.pixelSize: 14; font.family: Theme.fontFamily }
        Text {
            anchors { left: parent.left; leftMargin: 34; right: tchev.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
            elide: Text.ElideRight
            text: tpk.hm !== "" ? tpk.hm : tpk.placeholder
            color: tpk.hm !== "" ? Theme.fgBright : Theme.fgMuted
            font.pixelSize: 14; font.family: Theme.fontFamily
        }
        Text { id: tchev; anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
               text: pop.opened ? "󰅃" : "󰅀"; color: Theme.fgMuted; font.pixelSize: 13; font.family: Theme.fontFamily }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                    onClicked: pop.opened ? pop.close() : pop.open() }
    }

    Popup {
        id: pop
        y: disp.height + 4
        width: disp.width
        padding: 4
        implicitHeight: 214
        modal: false
        closePolicy: Popup.CloseOnPressOutside | Popup.CloseOnEscape
        onOpened: slotList.positionViewAtIndex(Math.max(0, tpk.slots.indexOf(tpk.hm)), ListView.Center)
        background: Rectangle {
            radius: 8; color: Theme.surface
            border.width: 1; border.color: Qt.alpha(Theme.boNormal, 0.6)
        }
        contentItem: ListView {
            id: slotList
            clip: true
            model: tpk.slots
            boundsBehavior: Flickable.StopAtBounds
            delegate: Rectangle {
                required property var modelData
                width: ListView.view.width; height: 28; radius: 6
                color: slotHov.containsMouse ? Theme.bgSecondary
                     : modelData === tpk.hm ? Qt.alpha(Theme.accent, 0.3) : "transparent"
                Text { anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                       text: modelData === "" ? "󰥔  all day" : modelData
                       color: modelData === tpk.hm ? Theme.fgBright : Theme.fgPrimary
                       font.pixelSize: 13; font.family: Theme.fontFamily }
                MouseArea { id: slotHov; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    onClicked: { tpk.hm = modelData; tpk.picked(modelData); pop.close() } }
            }
        }
    }
}
