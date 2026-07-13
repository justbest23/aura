import QtQuick

// An abstract "vibe" glyph, back to front:
//   - GPU aura:    outermost soft bloom, its own color, swells with GPU load
//   - CPU glow:    a steadier halo around the core, CPU's own color
//   - swarm:       drifting motes, count from running process count
//   - net ring:    fixed cyan dashes, spin speed/brightness = network throughput
//   - disk ring:   fixed amber dashes, spins the other way = disk throughput
//   - CPU core:    brightest, topmost; color = CPU heat, pulse speed = clock
//                  boost, and the density of the swirl inside it = RAM usage
Item {
    id: orb

    property real cpuHue: 0.6         // 0 (hot/red) .. 0.68 (cool/blue)
    property real breathHalf: 1300    // ms per half-breath; lower = faster clock boost
    property real ramLevel: 0.5       // 0..1 RAM fullness -> density of the core's swirl
    Behavior on ramLevel { NumberAnimation { duration: orb.fadeDurationMs; easing.type: Easing.InOutQuad } }

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
    property real swarmBoost: 0.0     // 0..1, process surge above baseline
    Behavior on swarmBoost { NumberAnimation { duration: orb.fadeDurationMs; easing.type: Easing.InOutQuad } }

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
    // Wisps are a washed-out (low saturation) version of the core color so
    // they stay visibly lighter than the shell at every hue - same-color
    // wisps disappear whenever the hue lands somewhere perceptually dark.
    readonly property color swirlWispColor: Qt.hsva(cpuHue, 0.4, 1.0, 1.0)
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
                // Position from index alone (not index/count): when the count
                // changes, existing motes stay put and new ones appear in
                // their own spots, instead of the whole swarm reshuffling.
                readonly property real angle: orb.prand(index) * 2 * Math.PI
                readonly property real orbitR: swarm.width / 2 * (0.95 + orb.prand(index + 50) * 0.28)
                readonly property real twinklePhase: orb.prand(index + 200) * Math.PI * 2
                // Newly spawned motes fade in rather than popping
                property real appear: 0.0
                NumberAnimation on appear { to: 1.0; duration: 900; easing.type: Easing.OutQuad }
                width: swarm.width * (0.018 + orb.prand(index + 100) * 0.02) * (1.0 + 0.35 * orb.swarmBoost)
                height: width
                radius: width / 2
                color: "white"
                opacity: appear * (0.75 + 0.45 * orb.swarmBoost)
                    * (0.25 + orb.prand(index + 300) * 0.35)
                    * (0.6 + 0.4 * Math.sin(orb.beat * Math.PI * 2 + twinklePhase))
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

    // CPU core - brightest, topmost. Color/pulse are CPU; RAM is the density
    // of the swirl inside it: two counter-rotating layers of soft wisps, and
    // more memory in use = more (and brighter) wisps, so a filling machine
    // reads as the core churning toward solid, an idle one as a dim shell
    // with a few embers drifting around inside.
    component SwirlLayer: Item {
        id: swirlLayer
        property int seedBase: 0
        property int spinMs: 9000
        property int spinDirection: 1
        anchors.fill: parent
        RotationAnimation on rotation {
            running: true
            loops: Animation.Infinite
            from: swirlLayer.spinDirection > 0 ? 0 : 360
            to: swirlLayer.spinDirection > 0 ? 360 : 0
            duration: swirlLayer.spinMs
        }
        Repeater {
            model: orb.swirlCount
            // A streak, not a dot: a thin rounded bar lying tangent to its
            // orbit, so the layer's rotation drags it around like a current.
            delegate: Rectangle {
                readonly property real lenFrac: 0.35 + orb.prand(index + swirlLayer.seedBase) * 0.25
                readonly property real thickFrac: 0.07 + orb.prand(index + swirlLayer.seedBase + 40) * 0.06
                readonly property real ang: orb.prand(index + swirlLayer.seedBase + 80) * 2 * Math.PI
                // orbit capped so the streak's far corners stay inside the
                // core circle: need sqrt(d^2 + (len/2)^2) + thick/2 <= 0.5
                readonly property real maxOrbitFrac: Math.sqrt(Math.max(0, Math.pow(0.5 - thickFrac / 2, 2) - Math.pow(lenFrac / 2, 2)))
                readonly property real orbitFrac: orb.prand(index + swirlLayer.seedBase + 120) * maxOrbitFrac
                property real appear: 0.0
                NumberAnimation on appear { to: 1.0; duration: 900; easing.type: Easing.OutQuad }
                width: swirlLayer.width * lenFrac
                height: swirlLayer.width * thickFrac
                radius: height / 2
                color: orb.swirlWispColor
                opacity: appear * (0.2 + 0.25 * orb.ramLevel + orb.prand(index + swirlLayer.seedBase + 160) * 0.15)
                x: swirlLayer.width / 2 + Math.cos(ang) * swirlLayer.width * orbitFrac - width / 2
                y: swirlLayer.height / 2 + Math.sin(ang) * swirlLayer.width * orbitFrac - height / 2
                rotation: ang * 180 / Math.PI + 90
            }
        }
    }
    // Streaks per layer: a couple of lazy currents when memory is free, a
    // churning crowd when full. Deadband instead of a live binding: the
    // smoothed ramLevel wobbles a fraction of a percent every sample, and a
    // count binding sitting on a rounding boundary adds-and-removes the same
    // streak over and over - each re-add replays its fade-in, which reads
    // as the core flashing.
    property int swirlCount: 3
    onRamLevelChanged: {
        var target = 2 + ramLevel * 10
        if (Math.abs(target - swirlCount) > 0.75) {
            swirlCount = Math.round(target)
        }
    }

    Item {
        id: core
        anchors.centerIn: parent
        width: orb.width * (0.34 + 0.03 * orb.beat * orb.pulseAmount)
        height: width

        // vessel shell - dim, so the swirl density has something to fill
        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: orb.cpuCoreColor
            opacity: 0.3
        }
        SwirlLayer { seedBase: 400; spinMs: 9000; spinDirection: 1 }
        SwirlLayer { seedBase: 700; spinMs: 14000; spinDirection: -1 }
    }
}
