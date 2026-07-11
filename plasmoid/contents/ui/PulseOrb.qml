import QtQuick

// An abstract "vibe" glyph, back to front:
//   - GPU aura:    outermost soft bloom, its own color, swells with GPU load
//   - CPU glow:    a steadier halo around the core, CPU's own color
//   - swarm:       drifting motes, count from running process count
//   - net ring:    fixed cyan dashes, spin speed/brightness = network throughput
//   - disk ring:   fixed amber dashes, spins the other way = disk throughput
//   - CPU core:    brightest, topmost; color = CPU heat, pulse speed = clock boost
Item {
    id: orb

    property real cpuHue: 0.6         // 0 (hot/red) .. 0.68 (cool/blue)
    property real breathHalf: 1300    // ms per half-breath; lower = faster clock boost

    property real gpuHue: 0.6
    property real gpuActivity: 0.0    // 0..1
    property bool gpuPresent: false

    property real netActivity: 0.0    // 0..1, combined rx+tx
    property real diskActivity: 0.0   // 0..1, combined read+write
    property real netRxActivity: 0.0
    property real netTxActivity: 0.0
    property real diskReadActivity: 0.0
    property real diskWriteActivity: 0.0
    property bool splitNetwork: false
    property bool splitDisk: false
    property int swarmCount: 8

    // How long (ms) a driven value takes to ease toward a new reading,
    // instead of snapping - configurable via the widget's settings (General
    // > Fade duration). Matters most for the demo script, where a stage's
    // whole point is watching a signal visibly change rather than jump.
    property int fadeDurationMs: 1500

    // Pulsing can be turned off entirely (Configure Aura > General). The
    // rings and swarm don't depend on beat/gpuBeat at all, so they stay
    // fully animated either way - disabling this only holds the core/aura
    // at a steady size instead of breathing.
    property bool pulseEnabled: true
    property real pulseAmount: pulseEnabled ? 1.0 : 0.0
    Behavior on pulseAmount { NumberAnimation { duration: 600; easing.type: Easing.InOutQuad } }

    Behavior on cpuHue { NumberAnimation { duration: orb.fadeDurationMs; easing.type: Easing.InOutQuad } }
    Behavior on gpuHue { NumberAnimation { duration: orb.fadeDurationMs; easing.type: Easing.InOutQuad } }
    Behavior on breathHalf { NumberAnimation { duration: orb.fadeDurationMs; easing.type: Easing.InOutQuad } }
    Behavior on gpuActivity { NumberAnimation { duration: orb.fadeDurationMs; easing.type: Easing.InOutQuad } }
    // Ring activity fades live inside ActivityRing itself (below), since it
    // applies equally whether a ring is showing a combined or split value.

    property real beat: 0.0
    SequentialAnimation on beat {
        loops: Animation.Infinite
        NumberAnimation { to: 1.0; duration: orb.breathHalf; easing.type: Easing.InOutSine }
        NumberAnimation { to: 0.0; duration: orb.breathHalf; easing.type: Easing.InOutSine }
    }

    property real gpuBeat: 0.0
    SequentialAnimation on gpuBeat {
        loops: Animation.Infinite
        NumberAnimation { to: 1.0; duration: Math.max(700, 2600 - orb.gpuActivity * 1900); easing.type: Easing.InOutSine }
        NumberAnimation { to: 0.0; duration: Math.max(700, 2600 - orb.gpuActivity * 1900); easing.type: Easing.InOutSine }
    }

    function prand(seed) {
        var x = Math.sin(seed * 12.9898) * 43758.5453
        return x - Math.floor(x)
    }

    readonly property color cpuGlowColor: Qt.hsva(cpuHue, 0.65, 1.0, 1.0)
    readonly property color cpuCoreColor: Qt.hsva(cpuHue, 0.8, 1.0, 1.0)
    readonly property color gpuGlowColor: Qt.hsva(gpuHue, 0.7, 1.0, 1.0)

    // GPU aura - furthest back, nearly invisible idle, blooms with load
    Repeater {
        model: orb.gpuPresent ? 3 : 0
        delegate: Rectangle {
            anchors.centerIn: parent
            readonly property real layerScale: 1.0 + index * 0.3
            width: orb.width * (0.5 + 0.5 * orb.gpuActivity + 0.06 * orb.gpuBeat * orb.pulseAmount) * layerScale
            height: width
            radius: width / 2
            color: orb.gpuGlowColor
            opacity: Math.max(0, (0.04 + orb.gpuActivity * 0.28) - index * 0.05)
        }
    }

    // CPU glow - steadier halo directly around the core
    Repeater {
        model: 3
        delegate: Rectangle {
            anchors.centerIn: parent
            readonly property real layerScale: 1.0 + index * 0.22
            width: orb.width * (0.62 + 0.04 * orb.beat * orb.pulseAmount) * layerScale
            height: width
            radius: width / 2
            color: orb.cpuGlowColor
            opacity: 0.22 - index * 0.06
        }
    }

    // Process swarm - drifting motes, one ambient slow rotation for the group
    Item {
        id: swarm
        anchors.centerIn: parent
        width: orb.width
        height: width
        RotationAnimation on rotation {
            running: true
            loops: Animation.Infinite
            from: 0; to: 360
            duration: 42000
        }
        Repeater {
            model: orb.swarmCount
            delegate: Rectangle {
                readonly property real angle: (index / orb.swarmCount) * 2 * Math.PI + orb.prand(index) * 1.4
                readonly property real orbitR: swarm.width / 2 * (0.95 + orb.prand(index + 50) * 0.28)
                readonly property real twinklePhase: orb.prand(index + 200) * Math.PI * 2
                width: swarm.width * (0.018 + orb.prand(index + 100) * 0.02)
                height: width
                radius: width / 2
                color: "white"
                opacity: (0.25 + orb.prand(index + 300) * 0.35) * (0.6 + 0.4 * Math.sin(orb.beat * Math.PI * 2 + twinklePhase))
                x: swarm.width / 2 + Math.cos(angle) * orbitR - width / 2
                y: swarm.height / 2 + Math.sin(angle) * orbitR - height / 2
            }
        }
    }

    // Network - one combined cyan ring by default; splits into two
    // counter-rotating rings (download/upload) when splitNetwork is on.
    ActivityRing {
        visible: !orb.splitNetwork
        activity: orb.netActivity
        dashColor: "#57d6ff"
        dashCount: 8
        sizeFraction: 0.92
        direction: 1
        fadeDurationMs: orb.fadeDurationMs
    }
    ActivityRing {
        visible: orb.splitNetwork
        activity: orb.netRxActivity
        dashColor: "#57d6ff"
        dashCount: 6
        sizeFraction: 0.92
        direction: 1
        fadeDurationMs: orb.fadeDurationMs
    }
    ActivityRing {
        visible: orb.splitNetwork
        activity: orb.netTxActivity
        dashColor: "#2f7fae"
        dashCount: 6
        sizeFraction: 0.92
        direction: -1
        fadeDurationMs: orb.fadeDurationMs
    }

    // Disk - one combined amber ring by default; splits into two
    // counter-rotating rings (read/write) when splitDisk is on.
    ActivityRing {
        visible: !orb.splitDisk
        activity: orb.diskActivity
        dashColor: "#ffb454"
        dashCount: 5
        sizeFraction: 0.78
        direction: -1
        fadeDurationMs: orb.fadeDurationMs
    }
    ActivityRing {
        visible: orb.splitDisk
        activity: orb.diskReadActivity
        dashColor: "#ffb454"
        dashCount: 4
        sizeFraction: 0.78
        direction: -1
        fadeDurationMs: orb.fadeDurationMs
    }
    ActivityRing {
        visible: orb.splitDisk
        activity: orb.diskWriteActivity
        dashColor: "#ff7a54"
        dashCount: 4
        sizeFraction: 0.78
        direction: 1
        fadeDurationMs: orb.fadeDurationMs
    }

    // CPU core - brightest, topmost
    Rectangle {
        anchors.centerIn: parent
        width: orb.width * (0.34 + 0.03 * orb.beat * orb.pulseAmount)
        height: width
        radius: width / 2
        color: orb.cpuCoreColor
    }
}
