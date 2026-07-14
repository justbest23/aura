import QtQuick

// The orb, back to front: GPU bloom, CPU halo, process swarm, net/disk
// rings, CPU core (color = heat, pulse = clock boost, inner swirl = RAM).
Item {
    id: orb

    property real cpuHue: 0.6         // 0 (hot/red) .. 0.68 (cool/blue)
    property real breathHalf: 1300    // ms per half-breath
    property real ramLevel: 0.5       // 0..1
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
    property real swarmCount: 8       // how many motes should be visible
    Behavior on swarmCount { NumberAnimation { duration: orb.fadeDurationMs; easing.type: Easing.InOutQuad } }
    property real swarmBoost: 0.0     // 0..1, process surge above baseline
    Behavior on swarmBoost { NumberAnimation { duration: orb.fadeDurationMs; easing.type: Easing.InOutQuad } }

    // Ease time for new readings (General > Fade duration).
    property int fadeDurationMs: 1500

    // Only stills the core/aura breathing; rings and swarm animate regardless.
    property bool pulseEnabled: true
    property real pulseAmount: pulseEnabled ? 1.0 : 0.0
    Behavior on pulseAmount { NumberAnimation { duration: 600; easing.type: Easing.InOutQuad } }

    Behavior on cpuHue { NumberAnimation { duration: orb.fadeDurationMs; easing.type: Easing.InOutQuad } }
    Behavior on gpuHue { NumberAnimation { duration: orb.fadeDurationMs; easing.type: Easing.InOutQuad } }
    Behavior on breathHalf { NumberAnimation { duration: orb.fadeDurationMs; easing.type: Easing.InOutQuad } }
    Behavior on gpuActivity { NumberAnimation { duration: orb.fadeDurationMs; easing.type: Easing.InOutQuad } }
    // Ring activity eases inside ActivityRing itself.

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
    // Low saturation so the wisps stay lighter than the shell at every hue.
    readonly property color swirlWispColor: Qt.hsva(cpuHue, 0.4, 1.0, 1.0)
    readonly property color gpuGlowColor: Qt.hsva(gpuHue, 0.7, 1.0, 1.0)

    // GPU aura - nearly invisible idle, blooms with load
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

    // CPU glow - steady halo around the core
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

    // Process swarm - drifting motes
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
        // All motes exist up front; swarmCount just fades them in/out. A
        // number model would recreate every delegate on each count change,
        // flashing the whole swarm.
        Repeater {
            model: 48
            delegate: Rectangle {
                readonly property real angle: orb.prand(index) * 2 * Math.PI
                readonly property real orbitR: swarm.width / 2 * (0.95 + orb.prand(index + 50) * 0.28)
                readonly property real twinklePhase: orb.prand(index + 200) * Math.PI * 2
                width: swarm.width * (0.018 + orb.prand(index + 100) * 0.02) * (1.0 + 0.35 * orb.swarmBoost)
                height: width
                radius: width / 2
                color: "white"
                opacity: Math.max(0, Math.min(1, orb.swarmCount - index))
                    * (0.75 + 0.45 * orb.swarmBoost)
                    * (0.25 + orb.prand(index + 300) * 0.35)
                    * (0.6 + 0.4 * Math.sin(orb.beat * Math.PI * 2 + twinklePhase))
                x: swarm.width / 2 + Math.cos(angle) * orbitR - width / 2
                y: swarm.height / 2 + Math.sin(angle) * orbitR - height / 2
            }
        }
    }

    // Network - cyan ring; splits into rx/tx counter-rotating rings if enabled
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

    // Disk - amber ring, spins opposite; splits into read/write if enabled
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

    // CPU core. RAM shows as the swirl inside it: two counter-rotating
    // layers of tiny rods, count driven hard by ramLevel - a few drifting
    // specks when memory is free, a dense churning cloud when it's full.
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
        // All rods exist up front; each fades in as swirlTarget passes its
        // index. A number model would recreate every delegate on each count
        // change, flashing the whole swirl on every RAM sample.
        Repeater {
            model: 110
            // Tiny rod lying tangent to its orbit; individually near-invisible,
            // the signal is how many there are.
            delegate: Rectangle {
                readonly property real lenFrac: 0.08 + orb.prand(index + swirlLayer.seedBase) * 0.08
                readonly property real thickFrac: 0.02 + orb.prand(index + swirlLayer.seedBase + 40) * 0.02
                readonly property real ang: orb.prand(index + swirlLayer.seedBase + 80) * 2 * Math.PI
                // orbit capped so the rod's far corners stay inside the core:
                // sqrt(d^2 + (len/2)^2) + thick/2 <= 0.5
                readonly property real maxOrbitFrac: Math.sqrt(Math.max(0, Math.pow(0.5 - thickFrac / 2, 2) - Math.pow(lenFrac / 2, 2)))
                readonly property real orbitFrac: orb.prand(index + swirlLayer.seedBase + 120) * maxOrbitFrac
                width: swirlLayer.width * lenFrac
                height: swirlLayer.width * thickFrac
                radius: height / 2
                color: orb.swirlWispColor
                opacity: Math.max(0, Math.min(1, orb.swirlTarget - index))
                    * (0.2 + 0.65 * orb.ramLevel + orb.prand(index + swirlLayer.seedBase + 160) * 0.1)
                x: swirlLayer.width / 2 + Math.cos(ang) * swirlLayer.width * orbitFrac - width / 2
                y: swirlLayer.height / 2 + Math.sin(ang) * swirlLayer.width * orbitFrac - height / 2
                rotation: ang * 180 / Math.PI + 90
            }
        }
    }
    // 4..110 rods per layer, superlinear so the top end packs solid. ramLevel
    // is already eased by its Behavior, so the fill animates smoothly.
    readonly property real swirlTarget: 4 + Math.pow(ramLevel, 1.4) * 106

    Item {
        id: core
        anchors.centerIn: parent
        width: orb.width * (0.34 + 0.03 * orb.beat * orb.pulseAmount)
        height: width

        // dim shell for the swirl to fill
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
