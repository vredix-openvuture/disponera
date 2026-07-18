import QtQuick

// Collapsible project tree (port of velumeron's quickshell/calendar/ProjectRail.qml,
// Colors/Style → Theme, TodoService singleton → Todo context property).
Item {
    id: rail
    property string selectedId: ""          // "" = all tasks
    signal pick(string id)

    clip: true

    property var _collapsed: ({})
    function _toggle(id) {
        var m = {}
        for (var k in rail._collapsed) m[k] = rail._collapsed[k]
        if (m[id]) delete m[id]
        else       m[id] = true
        rail._collapsed = m
    }

    function kidsOf(pid) { return (Todo.projects ?? []).filter(p => p.parentId === pid) }
    function colorFor(pid) {
        var ps = Todo.projects ?? []
        for (var i = 0; i < ps.length; i++)
            if (ps[i].id === pid) return ps[i].color !== "" ? ps[i].color : Theme.accent
        return Theme.accent
    }
    function _rollup(p) {
        var n = p.openCount
        var kids = rail.kidsOf(p.id)
        for (var i = 0; i < kids.length; i++) n += rail._rollup(kids[i])
        return n
    }
    readonly property int openTotal: {
        var n = 0, ts = Todo.tasks ?? []
        for (var i = 0; i < ts.length; i++) if (!ts[i].done) n++
        return n
    }

    readonly property var rows: {
        var out = []
        function walk(parentId, level) {
            var kids = rail.kidsOf(parentId)
            for (var i = 0; i < kids.length; i++) {
                var p = kids[i]
                var sub = rail.kidsOf(p.id).length > 0
                var col = rail._collapsed[p.id] === true
                out.push({ p: p, level: level, hasKids: sub, collapsed: col,
                           count: col ? rail._rollup(p) : p.openCount })
                if (sub && !col) walk(p.id, level + 1)
            }
        }
        walk("", 0)
        return out
    }

    Flickable {
        anchors.fill: parent
        contentHeight: col.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: col
            width: parent.width
            spacing: 3

            Rectangle {   // "All tasks"
                width: parent.width; height: 30; radius: 8
                color: rail.selectedId === "" ? Qt.alpha(Theme.accent, 0.35)
                     : allHov.containsMouse ? Theme.bgSecondary : "transparent"
                Behavior on color { ColorAnimation { duration: 90 } }
                Text {
                    anchors { left: parent.left; leftMargin: 8; verticalCenter: parent.verticalCenter }
                    text: "󰒺"; color: rail.selectedId === "" ? Theme.fgBright : Theme.fgMuted
                    font.pixelSize: 15; font.family: Theme.fontFamily
                }
                Text {
                    anchors { left: parent.left; leftMargin: 28; right: allCnt.left; rightMargin: 4
                              verticalCenter: parent.verticalCenter }
                    elide: Text.ElideRight
                    text: "All tasks"
                    color: rail.selectedId === "" ? Theme.fgBright : Theme.fgPrimary
                    font.pixelSize: 13; font.family: Theme.fontFamily; font.bold: rail.selectedId === ""
                }
                Text {
                    id: allCnt
                    anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
                    visible: rail.openTotal > 0
                    text: rail.openTotal
                    color: rail.selectedId === "" ? Theme.fgBright : Theme.fgMuted
                    font.pixelSize: 11; font.family: Theme.fontFamily
                }
                MouseArea { id: allHov; anchors.fill: parent; hoverEnabled: true
                            onClicked: rail.pick("") }
            }

            Repeater {
                model: rail.rows
                delegate: Rectangle {
                    id: row
                    required property var modelData
                    readonly property var  p:  modelData.p
                    readonly property bool on: rail.selectedId === p.id
                    width: col.width; height: 30; radius: 8
                    color: on ? Qt.alpha(Theme.accent, 0.35)
                         : rowHov.containsMouse ? Theme.bgSecondary : "transparent"
                    Behavior on color { ColorAnimation { duration: 90 } }

                    Text {
                        anchors { left: parent.left; leftMargin: 6 + row.modelData.level * 14
                                  verticalCenter: parent.verticalCenter }
                        visible: row.modelData.hasKids
                        text: row.modelData.collapsed ? "▸" : "▾"
                        color: Theme.fgMuted; font.pixelSize: 11; font.family: Theme.fontFamily
                        MouseArea { anchors.fill: parent; anchors.margins: -6
                                    onClicked: rail._toggle(row.p.id) }
                    }
                    Rectangle {
                        anchors { left: parent.left; verticalCenter: parent.verticalCenter
                                  leftMargin: 6 + row.modelData.level * 14 + (row.modelData.hasKids ? 15 : 2) }
                        width: 8; height: 8; radius: 4
                        color: rail.colorFor(row.p.id)
                    }
                    Text {
                        anchors { left: parent.left; right: cnt.left; rightMargin: 4
                                  verticalCenter: parent.verticalCenter
                                  leftMargin: 6 + row.modelData.level * 14 + (row.modelData.hasKids ? 29 : 16) }
                        elide: Text.ElideRight
                        text:  row.p.title
                        color: row.on ? Theme.fgBright : Theme.fgPrimary
                        font.pixelSize: 13; font.family: Theme.fontFamily; font.bold: row.on
                    }
                    Text {
                        id: cnt
                        anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
                        visible: row.modelData.count > 0
                        text:  row.modelData.count
                        color: row.on ? Theme.fgBright : Theme.fgMuted
                        font.pixelSize: 11; font.family: Theme.fontFamily
                    }
                    MouseArea { id: rowHov; anchors.fill: parent; hoverEnabled: true
                                onClicked: rail.pick(row.p.id) }
                }
            }
        }
    }
}
