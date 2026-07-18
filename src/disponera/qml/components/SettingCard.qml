import QtQuick

// A grouped settings card — a rounded surface that holds a stack of rows
// (ToggleRow / SliderRow / SegmentedRow / …) separated by SettingDivider.
// Children are the default content, so a section reads like:
//     SettingCard { ToggleRow {…}; SettingDivider {}; SliderRow {…} }
Rectangle {
    id: card
    default property alias content: body.data
    width: parent ? parent.width : 0
    radius: 16
    color: Theme.bgPrimary
    border.width: 1
    border.color: Qt.alpha(Theme.boNormal, 0.30)
    implicitHeight: body.implicitHeight

    Column {
        id: body
        anchors { left: parent.left; right: parent.right; top: parent.top }
        topPadding: 4
        bottomPadding: 4
    }
}
