import QtQuick

// Settings › Calendar: grid layout defaults, the visible day-hour range, and how
// events render in the Week/Day time grid and the event detail card.
Flickable {
    id: sec
    contentHeight: col.implicitHeight + 8
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    function _hour(h) { return (h < 10 ? "0" : "") + Math.round(h) + ":00" }

    Column {
        id: col
        width: parent.width
        spacing: 12

        SectionLabel { text: "LAYOUT" }
        SettingCard {
            SegmentedRow {
                title: "Week starts on"
                desc: "First column of the month and week grids."
                options: [{ v: 0, l: "Sunday" }, { v: 1, l: "Monday" }, { v: 6, l: "Saturday" }]
                value: Settings.firstDayOfWeek
                onPicked: v => Settings.setFirstDayOfWeek(v)
            }
            SettingDivider {}
            SegmentedRow {
                title: "Default view"
                desc: "The calendar view Disponera opens on."
                options: [{ v: "year", l: "Year" }, { v: "month", l: "Month" },
                          { v: "week", l: "Week" }, { v: "day", l: "Day" }, { v: "agenda", l: "Agenda" }]
                value: Settings.defaultView
                onPicked: v => Settings.setDefaultView(v)
            }
        }

        Item { width: 1; height: 8 }

        SectionLabel { text: "DAY GRID" }
        SettingCard {
            SliderRow {
                title: "Day starts at"
                desc: "Earliest hour shown in the Week and Day time grids."
                from: 0; to: 23; stepSize: 1
                value: Settings.dayStartHour
                valueText: sec._hour(Settings.dayStartHour)
                onMoved: v => Settings.setDayStartHour(v)
            }
            SettingDivider {}
            SliderRow {
                title: "Day ends at"
                desc: "Latest hour shown in the Week and Day time grids."
                from: 1; to: 24; stepSize: 1
                value: Settings.dayEndHour
                valueText: sec._hour(Settings.dayEndHour)
                onMoved: v => Settings.setDayEndHour(v)
            }
        }

        Item { width: 1; height: 8 }

        SectionLabel { text: "EVENTS" }
        SettingCard {
            ToggleRow {
                title: "Event images in Week / Day"
                desc: "Paint an event's picture behind its block in the Week and Day grids (events that have an image)."
                checked: Settings.showEventImages
                onToggled: Settings.setShowEventImages(!Settings.showEventImages)
            }
            SettingDivider {}
            SliderRow {
                title: "Past event opacity"
                desc: "Events that have already ended fade to this opacity; upcoming events stay fully opaque."
                from: 0.05; to: 1.0
                value: Settings.pastEventOpacity
                valueText: Math.round(Settings.pastEventOpacity * 100) + "%"
                onMoved: v => Settings.setPastEventOpacity(v)
            }
        }

        Item { width: 1; height: 8 }

        SectionLabel { text: "EVENT CARD BACKGROUND" }
        SettingCard {
            SliderRow {
                title: "Image blur"
                desc: "Blur applied to the picture behind the event detail card."
                from: 0.0; to: 1.0
                value: Settings.heroBlur
                onMoved: v => Settings.setHeroBlur(v)
            }
            SettingDivider {}
            SliderRow {
                title: "Image dim"
                desc: "Darkening applied over that picture so the text stays readable."
                from: 0.0; to: 1.0
                value: Settings.heroDim
                onMoved: v => Settings.setHeroDim(v)
            }
        }
    }
}
