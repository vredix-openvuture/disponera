import QtQuick
import QtQuick.Effects

// Project card grid (Disponera M2 #181/#182/#185). Lists the child projects of
// `parentId` ("" = root) as cards — Vikunja background image (bgPath, cached
// JPEG) with a legibility scrim, or a tint of the project colour when there's no
// image. Each card shows the project title, a rolled-up open-task count (own +
// all descendants) and a subproject count. Reused for the root overview and for
// the subproject strip inside a project. Emits pick(id) on click.
Item {
    id: grid
    property string parentId: ""       // "" = root projects
    property int    cardMinW: 300
    property int    cardH:    184
    property int    gap:      16
    signal pick(string id)
    signal edit(string id)

    function kidsOf(pid) { return (Todo.projects ?? []).filter(p => p.parentId === pid) }
    function _rollup(p) {
        var n = p.openCount, ks = grid.kidsOf(p.id)
        for (var i = 0; i < ks.length; i++) n += grid._rollup(ks[i])
        return n
    }
    function colorFor(p) { return (p && p.color && p.color !== "") ? p.color : Theme.accent }

    readonly property var cards: grid.kidsOf(grid.parentId)
    readonly property int cols: Math.max(1, Math.floor((width + gap) / (cardMinW + gap)))
    readonly property int cardW: cols > 0 ? Math.floor((width - (cols - 1) * gap) / cols) : cardMinW
    implicitHeight: gridInner.implicitHeight

    Grid {
        id: gridInner
        width: parent.width
        columns: grid.cols
        columnSpacing: grid.gap
        rowSpacing: grid.gap

        Repeater {
            model: grid.cards
            delegate: Rectangle {
                id: card
                required property var modelData
                readonly property var  p:     card.modelData
                readonly property int  open:  grid._rollup(card.p)
                readonly property int  subs:  grid.kidsOf(card.p.id).length
                readonly property string bg:  card.p.bgPath || ""
                readonly property color accent: grid.colorFor(card.p)
                width: grid.cardW; height: grid.cardH
                radius: 12
                clip: true
                // No-image cards: a calm tint of the project colour over the base.
                color: card.bg !== "" ? Theme.bgPrimary
                                      : Qt.rgba(card.accent.r, card.accent.g, card.accent.b, 0.16)
                border.width: 1
                border.color: cardHov.containsMouse ? Qt.alpha(card.accent, 0.9)
                                                    : Qt.alpha(Theme.boNormal, 0.4)
                Behavior on border.color { ColorAnimation { duration: 120 } }

                // Background image, masked to the card's rounded corners (plain
                // clip is rectangular in QML, so image cards would otherwise show
                // sharp corners — mask them to match the imageless cards).
                Image {
                    id: bgImg
                    anchors.fill: parent
                    visible: false
                    source: card.bg !== "" ? "file://" + card.bg : ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: true
                    layer.enabled: true
                }
                MultiEffect {
                    anchors.fill: parent
                    visible: card.bg !== ""
                    source: bgImg
                    maskEnabled: true
                    maskSource: cardMask
                }
                Item {
                    id: cardMask
                    anchors.fill: parent
                    visible: false
                    layer.enabled: true
                    Rectangle { anchors.fill: parent; radius: 12; color: "black" }
                }
                // Legibility scrim (bottom → dark) under the title. Rounded so its
                // corners match the card (a plain rect would square them off).
                Rectangle {
                    anchors.fill: parent
                    radius: 12
                    gradient: Gradient {
                        GradientStop { position: 0.0;  color: card.bg !== "" ? Qt.rgba(0,0,0,0.15) : "transparent" }
                        GradientStop { position: 0.5;  color: "transparent" }
                        GradientStop { position: 1.0;  color: Qt.rgba(0,0,0, card.bg !== "" ? 0.72 : 0.30) }
                    }
                }
                // Rounded colour stripe — on EVERY card (image ones too), inset from
                // the edge so it floats as a pill rather than being glued on (#9).
                Rectangle {
                    anchors { left: parent.left; leftMargin: 12
                              top: parent.top; topMargin: 14; bottom: parent.bottom; bottomMargin: 14 }
                    width: 6; radius: 3
                    color: card.accent
                    // Faint dark edge so a bright stripe still reads on a busy image.
                    border.width: card.bg !== "" ? 1 : 0
                    border.color: Qt.rgba(0, 0, 0, 0.25)
                }

                // Top-right controls: edit pencil (on hover) + open-count pill.
                Row {
                    anchors { top: parent.top; right: parent.right; margins: 12 }
                    spacing: 6
                    Rectangle {
                        visible: cardHov.containsMouse && card.p.source === "vikunja"
                        width: 24; height: 24; radius: 12
                        color: editHov.containsMouse ? Qt.rgba(0, 0, 0, 0.65) : Qt.rgba(0, 0, 0, 0.45)
                        Text { anchors.centerIn: parent; text: "󰏫"; color: "#ffffff"
                               font.pixelSize: 12; font.family: Theme.fontFamily }
                        MouseArea { id: editHov; anchors.fill: parent; hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: grid.edit(card.p.id) }
                    }
                    Rectangle {
                        visible: card.open > 0
                        width: Math.max(24, cntLbl.implicitWidth + 16); height: 24; radius: 12
                        color: Qt.rgba(0, 0, 0, 0.45)
                        Text {
                            id: cntLbl
                            anchors.centerIn: parent
                            text: card.open
                            color: "#ffffff"; font.pixelSize: 13; font.bold: true; font.family: Theme.fontFamily
                        }
                    }
                }

                Column {
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom
                              leftMargin: 26; rightMargin: 14; bottomMargin: 14 }
                    spacing: 3
                    Text {
                        width: parent.width; elide: Text.ElideRight; maximumLineCount: 2
                        wrapMode: Text.WordWrap
                        text: card.p.title
                        color: card.bg !== "" ? "#ffffff" : Theme.fgBright
                        font.pixelSize: 18; font.bold: true; font.family: Theme.fontFamily
                    }
                    Text {
                        visible: card.subs > 0
                        text: "󰉋 " + card.subs + (card.subs === 1 ? " subproject" : " subprojects")
                        color: card.bg !== "" ? Qt.rgba(1,1,1,0.8) : Theme.fgMuted
                        font.pixelSize: 12; font.family: Theme.fontFamily
                    }
                }

                MouseArea {
                    id: cardHov
                    anchors.fill: parent; hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: grid.pick(card.p.id)
                }
            }
        }
    }
}
