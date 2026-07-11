import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.plasma.plasmoid
import org.kde.plasma.plasma5support as P5Support
import org.kde.plasma.core as PlasmaCore
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    // aura-pulse.service (see systemd/) samples continuously and writes this
    // file ~5x/sec; we just cat it instead of forking python3+psutil on
    // every poll, which is what makes a sub-second refresh cheap.
    readonly property string pulseScript: "cat $HOME/.cache/aura/stats.json"

    property var cpuPct: 0
    property var cpuTemp: null
    property var cpuFreqCur: null
    property var cpuFreqMin: null
    property var cpuFreqMax: null
    property var ramPct: 0
    property var ramUsedGb: 0
    property var ramTotalGb: 0
    property var gpuPct: null
    property var gpuTemp: null
    property var gpuMemPct: null
    property var netRxKbps: 0
    property var netTxKbps: 0
    property var diskReadKbps: 0
    property var diskWriteKbps: 0
    property var procCount: 0

    // Rolling ~60s history for the sparkline charts, one sample/sec (decoupled
    // from the 200ms poll rate - that's plenty fine-grained for a minute-wide
    // trend line and keeps the arrays small).
    readonly property int historyLength: 60
    property var cpuHistory: []
    property var ramHistory: []
    property var gpuHistory: []
    property var procHistory: []
    property var netHistory: []
    property var diskHistory: []

    readonly property bool gpuPresent: root.gpuPct !== null && root.gpuPct !== undefined

    // CPU is the core: color from CPU heat, pulse speed from clock boost.
    readonly property real cpuHeat: computeCpuHeat()
    readonly property real cpuHue: Math.max(0, 0.68 - cpuHeat * 0.68)
    readonly property real freqRatio: computeFreqRatio()
    readonly property real breathHalf: 1300 - freqRatio * 920

    // GPU is the aura around the core: its own color and its own bloom,
    // independent of CPU state entirely.
    readonly property real gpuHeat: computeGpuHeat()
    readonly property real gpuHue: Math.max(0, 0.68 - gpuHeat * 0.68)

    readonly property real netActivity: activityFromKbps(netRxKbps + netTxKbps)
    readonly property real diskActivity: activityFromKbps(diskReadKbps + diskWriteKbps)

    // Process count becomes a drifting swarm of motes - more going on, more
    // fireflies. Scaled/capped so it stays a texture, not a literal counter.
    readonly property int swarmCount: Math.max(5, Math.min(20, Math.round(root.procCount / 30)))

    // How hard the CPU clock is currently racing (0 = park speed, 1 = full
    // boost) - independent of heat: a latency-bound single core can boost to
    // max while overall utilization/color stays calm, so this is a distinct
    // "how excited is it right now" signal from the color's "how hot/loaded".
    function computeFreqRatio() {
        if (root.cpuFreqCur === null || root.cpuFreqCur === undefined ||
            root.cpuFreqMin === null || root.cpuFreqMin === undefined ||
            root.cpuFreqMax === null || root.cpuFreqMax === undefined ||
            root.cpuFreqMax <= root.cpuFreqMin) {
            return root.cpuHeat
        }
        return Math.max(0, Math.min(1, (root.cpuFreqCur - root.cpuFreqMin) / (root.cpuFreqMax - root.cpuFreqMin)))
    }

    function computeCpuHeat() {
        var vals = [root.cpuPct / 100, root.ramPct / 100 * 0.5]
        if (root.cpuTemp !== null && root.cpuTemp !== undefined) {
            vals.push(Math.max(0, Math.min(1, (root.cpuTemp - 45) / 40)))
        }
        return Math.max.apply(null, vals)
    }

    function computeGpuHeat() {
        if (!root.gpuPresent) {
            return 0
        }
        var vals = [root.gpuPct / 100]
        if (root.gpuMemPct !== null && root.gpuMemPct !== undefined) {
            vals.push(root.gpuMemPct / 100 * 0.6)
        }
        if (root.gpuTemp !== null && root.gpuTemp !== undefined) {
            vals.push(Math.max(0, Math.min(1, (root.gpuTemp - 45) / 40)))
        }
        return Math.max.apply(null, vals)
    }

    function activityFromKbps(kbps) {
        return Math.max(0, Math.min(1, Math.log(kbps + 1) / Math.LN10 / 5))
    }

    function fmtRate(kbps) {
        if (kbps > 1024) {
            return (kbps / 1024).toFixed(1) + " MB/s"
        }
        return kbps.toFixed(0) + " KB/s"
    }

    // Raw samples land 5x/sec and are individually noisy (e.g. a 200ms CPU%
    // window), which reads as flicker in text and jagged charts. Smoothing
    // here means the same values feed the orb's color/pulse math too, so
    // everything calms down together rather than needing two parallel
    // "raw" vs. "display" copies of every metric.
    readonly property real smoothingAlpha: 0.25

    function ema(prevVal, newVal) {
        if (newVal === null || newVal === undefined) {
            return null
        }
        if (prevVal === null || prevVal === undefined) {
            return newVal
        }
        return prevVal + (newVal - prevVal) * root.smoothingAlpha
    }

    function applyStats(s) {
        root.cpuPct = root.ema(root.cpuPct, s.cpu_pct)
        root.cpuTemp = root.ema(root.cpuTemp, s.cpu_temp)
        root.cpuFreqCur = root.ema(root.cpuFreqCur, s.cpu_freq_cur)
        root.cpuFreqMin = s.cpu_freq_min
        root.cpuFreqMax = s.cpu_freq_max
        root.ramPct = root.ema(root.ramPct, s.ram_pct)
        root.ramUsedGb = s.ram_used_gb
        root.ramTotalGb = s.ram_total_gb
        root.gpuPct = root.ema(root.gpuPct, s.gpu_pct)
        root.gpuTemp = root.ema(root.gpuTemp, s.gpu_temp)
        root.gpuMemPct = root.ema(root.gpuMemPct, s.gpu_mem_pct)
        root.netRxKbps = root.ema(root.netRxKbps, s.net_rx_kbps)
        root.netTxKbps = root.ema(root.netTxKbps, s.net_tx_kbps)
        root.diskReadKbps = root.ema(root.diskReadKbps, s.disk_read_kbps)
        root.diskWriteKbps = root.ema(root.diskWriteKbps, s.disk_write_kbps)
        root.procCount = s.proc_count
    }

    function pushHistory(arr, val) {
        var next = arr.concat([val])
        if (next.length > root.historyLength) {
            next = next.slice(next.length - root.historyLength)
        }
        return next
    }

    Plasmoid.icon: "utilities-system-monitor"
    Plasmoid.status: PlasmaCore.Types.ActiveStatus
    Plasmoid.backgroundHints: Plasmoid.configuration.showBackground
        ? PlasmaCore.Types.StandardBackground
        : PlasmaCore.Types.NoBackground
    toolTipMainText: i18n("Aura")
    toolTipSubText: i18n("CPU %1%  ·  RAM %2%%3", root.cpuPct.toFixed(0), root.ramPct.toFixed(0),
        (root.gpuPct !== null && root.gpuPct !== undefined) ? i18n("  ·  GPU %1%", root.gpuPct.toFixed(0)) : "")

    P5Support.DataSource {
        id: dataSource
        engine: "executable"
        connectedSources: []
        onNewData: (sourceName, data) => {
            disconnectSource(sourceName)
            try {
                root.applyStats(JSON.parse(data["stdout"]))
            } catch (e) {
                console.log("aura: bad stats payload", e)
            }
        }
        function exec(cmd) {
            connectSource(cmd)
        }
    }

    Timer {
        interval: 200
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: dataSource.exec(root.pulseScript)
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: {
            root.cpuHistory = root.pushHistory(root.cpuHistory, root.cpuPct)
            root.ramHistory = root.pushHistory(root.ramHistory, root.ramPct)
            if (root.gpuPresent) {
                root.gpuHistory = root.pushHistory(root.gpuHistory, root.gpuPct)
            }
            root.procHistory = root.pushHistory(root.procHistory, root.procCount)
            root.netHistory = root.pushHistory(root.netHistory, root.netRxKbps + root.netTxKbps)
            root.diskHistory = root.pushHistory(root.diskHistory, root.diskReadKbps + root.diskWriteKbps)
        }
    }

    compactRepresentation: Item {
        PulseOrb {
            anchors.fill: parent
            cpuHue: root.cpuHue
            breathHalf: root.breathHalf
            gpuHue: root.gpuHue
            gpuActivity: root.gpuHeat
            gpuPresent: root.gpuPresent
            netActivity: root.netActivity
            diskActivity: root.diskActivity
            swarmCount: root.swarmCount
            fadeDurationMs: Plasmoid.configuration.fadeDurationMs
        }
    }

    fullRepresentation: ColumnLayout {
        Layout.preferredWidth: Kirigami.Units.gridUnit * 16
        Layout.margins: Kirigami.Units.largeSpacing
        spacing: Kirigami.Units.largeSpacing

        PulseOrb {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: Kirigami.Units.gridUnit * 8
            Layout.preferredHeight: Layout.preferredWidth
            cpuHue: root.cpuHue
            breathHalf: root.breathHalf
            gpuHue: root.gpuHue
            gpuActivity: root.gpuHeat
            gpuPresent: root.gpuPresent
            netActivity: root.netActivity
            diskActivity: root.diskActivity
            swarmCount: root.swarmCount
            fadeDurationMs: Plasmoid.configuration.fadeDurationMs
        }

        ColumnLayout {
            Layout.fillWidth: true
            visible: Plasmoid.configuration.showStats
            spacing: Kirigami.Units.smallSpacing

            StatRow {
                label: i18n("CPU")
                displayMode: Plasmoid.configuration.statsDisplay
                history: root.cpuHistory
                chartColor: Qt.hsva(root.cpuHue, 0.8, 1.0, 1.0)
                value: root.cpuPct.toFixed(0) + "%"
                    + ((root.cpuTemp !== null && root.cpuTemp !== undefined) ? "  ·  " + root.cpuTemp.toFixed(0) + "°C" : "")
                    + ((root.cpuFreqCur !== null && root.cpuFreqCur !== undefined) ? "  ·  " + (root.cpuFreqCur / 1000).toFixed(1) + " GHz" : "")
            }

            StatRow {
                label: i18n("RAM")
                displayMode: Plasmoid.configuration.statsDisplay
                history: root.ramHistory
                chartColor: "white"
                value: root.ramPct.toFixed(0) + "%  ·  " + root.ramUsedGb.toFixed(1) + "/" + root.ramTotalGb.toFixed(0) + " GB"
            }

            StatRow {
                visible: root.gpuPresent
                label: i18n("GPU")
                displayMode: Plasmoid.configuration.statsDisplay
                history: root.gpuHistory
                chartColor: Qt.hsva(root.gpuHue, 0.8, 1.0, 1.0)
                value: root.gpuPresent
                    ? root.gpuPct.toFixed(0) + "%  ·  " + root.gpuTemp.toFixed(0) + "°C  ·  " + root.gpuMemPct.toFixed(0) + "% mem"
                    : ""
            }

            StatRow {
                label: i18n("Processes")
                displayMode: Plasmoid.configuration.statsDisplay
                history: root.procHistory
                chartColor: "white"
                value: root.procCount.toString()
            }

            StatRow {
                label: i18n("Network")
                displayMode: Plasmoid.configuration.statsDisplay
                history: root.netHistory
                chartColor: "#57d6ff"
                value: "↓ " + root.fmtRate(root.netRxKbps) + "   ↑ " + root.fmtRate(root.netTxKbps)
            }

            StatRow {
                label: i18n("Disk")
                displayMode: Plasmoid.configuration.statsDisplay
                history: root.diskHistory
                chartColor: "#ffb454"
                value: "R " + root.fmtRate(root.diskReadKbps) + "   W " + root.fmtRate(root.diskWriteKbps)
            }
        }
    }
}
