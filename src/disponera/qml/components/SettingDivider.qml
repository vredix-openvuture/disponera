import QtQuick

// Hairline between two rows inside a SettingCard. Inset from the card edges so
// it aligns under the row text rather than butting the rounded corners.
Item {
    width: parent ? parent.width : 0
    height: 1
    Rectangle {
        anchors { left: parent.left; right: parent.right; leftMargin: 18; rightMargin: 18
                  verticalCenter: parent.verticalCenter }
        height: 1
        color: Qt.alpha(Theme.boNormal, 0.22)
    }
}
