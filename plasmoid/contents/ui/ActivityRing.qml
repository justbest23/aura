import QtQuick

// A ring of dashes that spins faster/brighter with `activity`. Still creeps
// slowly at zero so it looks quiet rather than broken.
Item {
    id: ring

    property real activity: 0.0       // 0..1
    property color dashColor: "white"
    property int dashCount: 8
    property real sizeFraction: 0.92  // relative to parent (orb) width
    property int direction: 1         // >=0 clockwise, <0 counter-clockwise
    property real idleDurationMs: 60000
    property real busyDurationMs: 500
    property int fadeDurationMs: 1500

    Behavior on activity { NumberAnimation { duration: ring.fadeDurationMs; easing.type: Easing.InOutQuad } }

    anchors.centerIn: parent
    width: parent.width * sizeFraction
    height: width
    opacity: 0.1 + ring.activity * 0.75

    // Geometric speed interpolation - idle-to-busy is a ~120x range, and a
    // linear blend crams all the visibly-fast speeds into the top few percent.
    readonly property real idleDegPerMs: 360 / idleDurationMs
    readonly property real busyDegPerMs: 360 / busyDurationMs
    readonly property real degPerMs: idleDegPerMs * Math.pow(busyDegPerMs / idleDegPerMs, activity)

    // Integrate per-frame: a looping RotationAnimation only picks up duration
    // changes on loop restart, and the idle loop is 60s long.
    FrameAnimation {
        running: true
        onTriggered: {
            var step = ring.degPerMs * frameTime * 1000
            ring.rotation = (ring.rotation + (ring.direction >= 0 ? step : -step)) % 360
        }
    }

    Repeater {
        model: ring.dashCount
        delegate: Rectangle {
            readonly property real angle: index * (2 * Math.PI / ring.dashCount)
            width: ring.width * 0.05
            height: width
            radius: width / 2
            color: ring.dashColor
            x: ring.width / 2 + Math.cos(angle) * ring.width / 2 - width / 2
            y: ring.height / 2 + Math.sin(angle) * ring.height / 2 - height / 2
        }
    }
}
