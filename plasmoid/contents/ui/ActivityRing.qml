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

    RotationAnimation on rotation {
        running: true
        loops: Animation.Infinite
        from: ring.direction >= 0 ? 0 : 360
        to: ring.direction >= 0 ? 360 : 0
        duration: Math.max(ring.busyDurationMs, ring.idleDurationMs - ring.activity * (ring.idleDurationMs - ring.busyDurationMs))
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
