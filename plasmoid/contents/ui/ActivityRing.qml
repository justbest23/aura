import QtQuick

// A ring of dashes that spins faster/brighter with `activity`. At zero
// activity it still creeps around very slowly (idleDurationMs) rather than
// sitting dead-still, so it reads as "quiet" rather than "broken".
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

    // Spin speed interpolates geometrically, not linearly: idle-to-busy spans
    // a ~120x speed range, and blending the duration (or speed) linearly
    // crams every visibly-fast speed into the last few percent of activity -
    // a ring at 0.8 would still take 12s/turn. In log space each step up in
    // activity multiplies the speed, so the whole range reads.
    readonly property real idleDegPerMs: 360 / idleDurationMs
    readonly property real busyDegPerMs: 360 / busyDurationMs
    readonly property real degPerMs: idleDegPerMs * Math.pow(busyDegPerMs / idleDegPerMs, activity)

    // Integrate the rotation per-frame instead of a looping RotationAnimation
    // with a bound duration: a running animation loop only picks a duration
    // change up when the loop restarts, and the idle loop is 60 SECONDS long
    // - a traffic burst could take a minute to visibly speed the ring up
    // (and be over before it did).
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
