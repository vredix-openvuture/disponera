import QtQuick

// Free HH:MM time entry (minute-level, not fixed slots). `hm` holds "HH:MM".
// Emits edited(hm) on commit.
Rectangle {
    id: tf
    property string hm: "09:00"
    signal edited(string hm)
    width: 84; height: 38; radius: 8
    color: Theme.bgPrimary
    border.width: input.activeFocus ? 1 : 0
    border.color: Theme.accent

    function _clamp(s) {
        var m = /^(\d{1,2}):(\d{2})$/.exec(s || "")
        if (!m) return tf.hm
        var h = Math.max(0, Math.min(23, parseInt(m[1])))
        var mi = Math.max(0, Math.min(59, parseInt(m[2])))
        return (h < 10 ? "0" : "") + h + ":" + (mi < 10 ? "0" : "") + mi
    }

    TextInput {
        id: input
        anchors.fill: parent; anchors.margins: 8
        verticalAlignment: TextInput.AlignVCenter
        horizontalAlignment: TextInput.AlignHCenter
        text: tf.hm
        color: Theme.fgBright; font.pixelSize: 15; font.family: Theme.fontFamily
        inputMask: "99:99"
        selectByMouse: true
        onActiveFocusChanged: if (activeFocus) selectAll()
        onEditingFinished: { tf.hm = tf._clamp(text); text = tf.hm; tf.edited(tf.hm) }
    }
}
