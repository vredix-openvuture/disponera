import QtQuick

// Settings › General: launch behaviour + clock format. App-wide preferences that
// aren't specific to the calendar or its appearance.
Flickable {
    id: sec
    contentHeight: col.implicitHeight + 8
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    Column {
        id: col
        width: parent.width
        spacing: 12

        SectionLabel { text: "STARTUP" }
        SettingCard {
            SegmentedRow {
                title: "Open on launch"
                desc: "Which tab Disponera shows when it starts."
                options: [{ v: 0, l: "󰃭  Calendar" }, { v: 1, l: "󰄲  Todos" }]
                value: Settings.startupTab
                onPicked: v => Settings.setStartupTab(v)
            }
        }

        Item { width: 1; height: 8 }

        SectionLabel { text: "CLOCK" }
        SettingCard {
            ToggleRow {
                title: "24-hour time"
                desc: "Show times as 14:30 instead of 2:30 PM across the calendar, events and tasks."
                checked: Settings.time24h
                onToggled: Settings.setTime24h(!Settings.time24h)
            }
        }
    }
}
