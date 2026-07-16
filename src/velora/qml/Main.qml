import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// velora — focused working over the same data the shell's quick-view flyout
// shows: the unified todo model (Vikunja project tree + CalDAV lists), CalDAV
// events, and local markdown notes. Colors + font follow the live velumeron
// theme (ThemeBridge watches wallust's colors.json).
ApplicationWindow {
    id: win
    visible: true
    width: 1280; height: 800
    title: "velora"
    // Opaque, matching velumeron's own panels exactly: quickshell/Style.qml's
    // panelColor() returns a fully opaque Colors.bgPrimary (raw color0) for
    // every ui_style — an earlier version of this window made itself
    // translucent to mimic the BAR specifically, which was the wrong reference
    // (the bar's optional transparency is its own separate, user-toggled
    // setting, not how the shell's panels render).
    color: Theme.windowBg

    property int tab: 0   // land on Calendar
    // Immersive mode: the sidebar toggle hides BOTH the calendar sidebar and this
    // top bar. The top bar isn't gone — it peeks back when the cursor touches the
    // top edge (hover-to-show).
    property bool immersive: false
    readonly property bool headerPeek: hdrHover.hovered || peekHover.hovered

    // The bridges load their on-disk caches in-process at construction, so the
    // model is already populated here — the first paint shows real data. All we
    // kick off is the network refresh (one Vikunja sync + one CalDAV sync).
    Component.onCompleted: { Todo.sync(); CalDav.sync(); win.latchTab() }

    // Latch tabs 1 & 2 loaded on first visit and keep them (see the Loaders
    // below). Called on every tab change AND once at startup, so it's correct
    // even if the initial tab is ever something other than 0.
    function latchTab() {
        if (tab === 1) todoLoader.active = true
        else if (tab === 2) settingsLoader.active = true
    }
    onTabChanged: win.latchTab()

    // ── Header: tabs + sync state (collapsible / hover-to-show) ──────────────
    header: Rectangle {
        height: win.immersive ? (win.headerPeek ? 46 : 0) : 46
        clip: true
        // Matches CalendarPane's sidebar fill (also Theme.surface) so the two
        // panels read as one continuous opaque surface instead of a seam where
        // the translucent window base shows through only behind the header.
        color: Theme.surface
        Behavior on height { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
        HoverHandler { id: hdrHover }

        // Segmented tab control — one container, equal-width tabs, so they read as
        // one clean control instead of three differently-sized buttons.
        Rectangle {
            anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
            height: 34; radius: 9
            color: Theme.bgElement
            width: tabInner.width + 12
            Row {
                id: tabInner
                anchors.centerIn: parent
                spacing: 12
                Repeater {
                    model: [{ icon: "󰃭", label: "Calendar" },
                            { icon: "󰄲", label: "Todos" },
                            { icon: "󰒓", label: "Settings" }]
                    delegate: Rectangle {
                        id: tabBtn
                        required property var modelData
                        required property int index
                        readonly property bool on: win.tab === index
                        width: 112; height: 28; radius: 7
                        color: on ? Qt.alpha(Theme.accent, 0.35)
                             : tabHov.containsMouse ? Theme.bgSecondary : "transparent"
                        Behavior on color { ColorAnimation { duration: 120 } }
                        Text {
                            anchors.centerIn: parent
                            text: tabBtn.modelData.icon + "  " + tabBtn.modelData.label
                            color: tabBtn.on ? Theme.fgBright : Theme.fgPrimary
                            font.pixelSize: 14; font.family: Theme.fontFamily; font.bold: tabBtn.on
                        }
                        MouseArea { id: tabHov; anchors.fill: parent; hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: win.tab = tabBtn.index }
                    }
                }
            }
        }

        Row {
            anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
            spacing: 10
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: Todo.lastError !== "" ? "󰀦 " + Todo.lastError
                    : Todo.syncing || CalDav.syncing ? "syncing…"
                    : Todo.syncedAt > 0
                      ? "synced " + Qt.formatTime(new Date(Todo.syncedAt), "hh:mm") : ""
                color: Todo.lastError !== "" ? Theme.fgUrgent : Theme.fgMuted
                font.pixelSize: 12; font.family: Theme.fontFamily
            }
            Text {
                id: syncBtn
                anchors.verticalCenter: parent.verticalCenter
                text: "󰑐"; color: syncHov.containsMouse ? Theme.fgBright : Theme.fgMuted
                font.pixelSize: 17; font.family: Theme.fontFamily
                RotationAnimation on rotation {
                    running: Todo.syncing || CalDav.syncing; from: 0; to: 360
                    duration: 900; loops: Animation.Infinite
                    onRunningChanged: if (!running) syncBtn.rotation = 0
                }
                MouseArea { id: syncHov; anchors.fill: parent; anchors.margins: -6
                            hoverEnabled: true
                            onClicked: { Todo.sync(); CalDav.sync() } }
            }
        }

        Rectangle {   // hairline under the header
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            height: 1; color: Qt.alpha(Theme.boNormal, 0.5)
        }
    }

    StackLayout {
        anchors.fill: parent
        // In immersive mode the top bar is gone, so content would sit under the
        // top peek zone — a small inset keeps interactive rows (back button,
        // toolbar) clear of it, so aiming for them doesn't peek the bar.
        anchors.topMargin: win.immersive ? 30 : 0
        currentIndex: win.tab

        CalendarPane { immersive: win.immersive }
        // Tabs 1 & 2 build lazily on first visit and stay loaded afterwards, so
        // startup never constructs the task board or the whole settings tree (nor
        // pays their RAM) unless you actually open them.
        Loader { id: todoLoader; active: false; sourceComponent: todoComp }
        Loader { id: settingsLoader; active: false; sourceComponent: settingsComp }
    }

    Component { id: todoComp; TodoPane {} }
    Component { id: settingsComp; SettingsPane {} }   // Notes tab removed for now

    // Hover-to-show zone: while the top bar is hidden, moving near the top edge
    // peeks it back in (headerPeek). Generous height so it's easy to hit; it only
    // reacts to hover (no click capture), so it never steals clicks from content.
    Item {
        anchors { top: parent.top; left: parent.left; right: parent.right }
        height: 28; visible: win.immersive; z: 100
        HoverHandler { id: peekHover }
    }

    // Single show/hide toggle for BOTH the top bar and the sidebar — bottom-left,
    // "<" while open, ">" while collapsed.
    Rectangle {
        anchors { left: parent.left; bottom: parent.bottom; margins: 12 }
        width: 32; height: 32; radius: 8
        color: immHov.containsMouse ? Theme.bgSecondary : Theme.bgElement
        opacity: immHov.containsMouse ? 1.0 : 0.85
        z: 200
        Text { anchors.centerIn: parent; text: win.immersive ? "󰅂" : "󰅁"
               color: Theme.fgPrimary; font.pixelSize: 17; font.family: Theme.fontFamily }
        MouseArea { id: immHov; anchors.fill: parent; hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: win.immersive = !win.immersive }
    }
}
