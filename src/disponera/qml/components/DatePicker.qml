import QtQuick
import QtQuick.Controls

// Date field with a real calendar in an overlay Popup (no manual typing, no card
// growth — blueprint #2/#3). `ymd` holds the selected "YYYY-MM-DD" ("" = none).
// Emits picked(ymd) on choose/clear.
Item {
    id: dpk
    property string ymd: ""
    property bool allowEmpty: true
    property string placeholder: "pick a date"
    signal picked(string ymd)
    readonly property alias open: pop.opened
    implicitHeight: 38

    readonly property int firstDow: Settings.firstDayOfWeek
    property int vy: (new Date()).getFullYear()
    property int vm: (new Date()).getMonth()

    function _parse(s) {
        var m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(s || "")
        return m ? new Date(+m[1], +m[2] - 1, +m[3]) : new Date()
    }
    function _fmt(d) { function p(n){return (n<10?"0":"")+n} return d.getFullYear()+"-"+p(d.getMonth()+1)+"-"+p(d.getDate()) }
    function _key(d) { return d.getFullYear()*10000 + (d.getMonth()+1)*100 + d.getDate() }
    function _openPop() {
        var d = dpk._parse(dpk.ymd); dpk.vy = d.getFullYear(); dpk.vm = d.getMonth(); pop.open()
    }
    function _shift(dir) {
        var m = dpk.vm + dir; dpk.vy += Math.floor(m/12); dpk.vm = ((m%12)+12)%12
    }
    readonly property var gridDays: {
        var first = new Date(dpk.vy, dpk.vm, 1)
        var off = (first.getDay() - dpk.firstDow + 7) % 7
        var dim = new Date(dpk.vy, dpk.vm+1, 0).getDate()
        var cells = Math.ceil((off+dim)/7)*7, out = []
        for (var i=0;i<cells;i++) out.push(new Date(dpk.vy, dpk.vm, 1-off+i))
        return out
    }

    Rectangle {
        id: disp
        anchors.fill: parent
        radius: 8
        color: Theme.bgPrimary
        border.width: pop.opened ? 1 : 0; border.color: Theme.accent
        Text { anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
               text: "󰃭"; color: Theme.fgMuted; font.pixelSize: 14; font.family: Theme.fontFamily }
        Text {
            anchors { left: parent.left; leftMargin: 34; right: dchev.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
            elide: Text.ElideRight
            text: dpk.ymd !== "" ? Qt.formatDate(dpk._parse(dpk.ymd), "ddd, MMM d yyyy") : dpk.placeholder
            color: dpk.ymd !== "" ? Theme.fgBright : Theme.fgMuted
            font.pixelSize: 14; font.family: Theme.fontFamily
        }
        Text { id: dchev; anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
               text: pop.opened ? "󰅃" : "󰅀"; color: Theme.fgMuted; font.pixelSize: 13; font.family: Theme.fontFamily }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                    onClicked: pop.opened ? pop.close() : dpk._openPop() }
    }

    Popup {
        id: pop
        y: disp.height + 4
        width: 262
        padding: 8
        implicitHeight: popCol.implicitHeight + 16
        modal: false
        closePolicy: Popup.CloseOnPressOutside | Popup.CloseOnEscape
        background: Rectangle {
            radius: 10; color: Theme.surface
            border.width: 1; border.color: Qt.alpha(Theme.boNormal, 0.6)
        }
        contentItem: Column {
            id: popCol
            spacing: 6
            Item {
                width: parent.width; height: 26
                Text { anchors.centerIn: parent
                       text: Qt.formatDate(new Date(dpk.vy, dpk.vm, 1), "MMMM yyyy")
                       color: Theme.fgBright; font.pixelSize: 14; font.bold: true; font.family: Theme.fontFamily }
                Text { anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                       text: "󰅁"; color: navL.containsMouse ? Theme.fgBright : Theme.fgMuted
                       font.pixelSize: 16; font.family: Theme.fontFamily
                       MouseArea { id: navL; anchors.fill: parent; anchors.margins: -6; hoverEnabled: true
                                   cursorShape: Qt.PointingHandCursor; onClicked: dpk._shift(-1) } }
                Text { anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                       text: "󰅂"; color: navR.containsMouse ? Theme.fgBright : Theme.fgMuted
                       font.pixelSize: 16; font.family: Theme.fontFamily
                       MouseArea { id: navR; anchors.fill: parent; anchors.margins: -6; hoverEnabled: true
                                   cursorShape: Qt.PointingHandCursor; onClicked: dpk._shift(1) } }
            }
            Row {
                spacing: 2
                Repeater { model: 7
                    delegate: Text { required property int index
                        width: 34; horizontalAlignment: Text.AlignHCenter
                        text: Qt.formatDate(new Date(2026, 6, 5 + dpk.firstDow + index), "ddd").charAt(0)
                        color: Theme.fgMuted; font.pixelSize: 11; font.family: Theme.fontFamily } }
            }
            Grid {
                columns: 7; columnSpacing: 2; rowSpacing: 2
                Repeater {
                    model: dpk.gridDays
                    delegate: Rectangle {
                        required property var modelData
                        readonly property bool inM: modelData.getMonth() === dpk.vm
                        readonly property bool sel: dpk.ymd !== "" && dpk._key(modelData) === dpk._key(dpk._parse(dpk.ymd))
                        readonly property bool today: dpk._key(modelData) === dpk._key(new Date())
                        width: 34; height: 30; radius: 6
                        color: sel ? Theme.accent : dHov.containsMouse ? Theme.bgSecondary : "transparent"
                        border.width: today && !sel ? 1 : 0; border.color: Theme.accent
                        Text { anchors.centerIn: parent; text: modelData.getDate()
                               color: sel ? Theme.fgBright : inM ? Theme.fgPrimary : Theme.fgMuted
                               opacity: inM ? 1 : 0.4; font.pixelSize: 12; font.family: Theme.fontFamily }
                        MouseArea { id: dHov; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: { dpk.ymd = dpk._fmt(modelData); dpk.picked(dpk.ymd); pop.close() } }
                    }
                }
            }
            Rectangle {
                visible: dpk.allowEmpty && dpk.ymd !== ""
                width: parent.width; height: 26; radius: 6
                color: clrHov.containsMouse ? Theme.bgSecondary : "transparent"
                Text { anchors.centerIn: parent; text: "󰜺  No date"; color: Theme.fgMuted
                       font.pixelSize: 12; font.family: Theme.fontFamily }
                MouseArea { id: clrHov; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    onClicked: { dpk.ymd = ""; dpk.picked(""); pop.close() } }
            }
        }
    }
}
