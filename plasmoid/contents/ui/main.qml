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

    function applyStats(s) {
        root.cpuPct = s.cpu_pct
        root.cpuTemp = s.cpu_temp
        root.cpuFreqCur = s.cpu_freq_cur
        root.cpuFreqMin = s.cpu_freq_min
        root.cpuFreqMax = s.cpu_freq_max
        root.ramPct = s.ram_pct
        root.ramUsedGb = s.ram_used_gb
        root.ramTotalGb = s.ram_total_gb
        root.gpuPct = s.gpu_pct
        root.gpuTemp = s.gpu_temp
        root.gpuMemPct = s.gpu_mem_pct
        root.netRxKbps = s.net_rx_kbps
        root.netTxKbps = s.net_tx_kbps
        root.diskReadKbps = s.disk_read_kbps
        root.diskWriteKbps = s.disk_write_kbps
        root.procCount = s.proc_count
    }

    Plasmoid.icon: "utilities-system-monitor"
    Plasmoid.status: PlasmaCore.Types.ActiveStatus
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

        GridLayout {
            Layout.fillWidth: true
            columns: 2
            columnSpacing: Kirigami.Units.largeSpacing
            rowSpacing: Kirigami.Units.smallSpacing

            QQC2.Label { text: i18n("CPU"); opacity: 0.7 }
            QQC2.Label {
                text: root.cpuPct.toFixed(0) + "%"
                    + ((root.cpuTemp !== null && root.cpuTemp !== undefined) ? "  ·  " + root.cpuTemp.toFixed(0) + "°C" : "")
                    + ((root.cpuFreqCur !== null && root.cpuFreqCur !== undefined) ? "  ·  " + (root.cpuFreqCur / 1000).toFixed(1) + " GHz" : "")
                Layout.alignment: Qt.AlignRight
            }

            QQC2.Label { text: i18n("RAM"); opacity: 0.7 }
            QQC2.Label {
                text: root.ramPct.toFixed(0) + "%  ·  " + root.ramUsedGb.toFixed(1) + "/" + root.ramTotalGb.toFixed(0) + " GB"
                Layout.alignment: Qt.AlignRight
            }

            QQC2.Label {
                text: i18n("GPU")
                opacity: 0.7
                visible: root.gpuPct !== null && root.gpuPct !== undefined
            }
            QQC2.Label {
                visible: root.gpuPresent
                text: root.gpuPresent
                      ? root.gpuPct.toFixed(0) + "%  ·  " + root.gpuTemp.toFixed(0) + "°C  ·  " + root.gpuMemPct.toFixed(0) + "% mem"
                      : ""
                Layout.alignment: Qt.AlignRight
            }

            QQC2.Label { text: i18n("Processes"); opacity: 0.7 }
            QQC2.Label {
                text: root.procCount.toString()
                Layout.alignment: Qt.AlignRight
            }

            QQC2.Label { text: i18n("Network"); opacity: 0.7 }
            QQC2.Label {
                text: "↓ " + root.fmtRate(root.netRxKbps) + "   ↑ " + root.fmtRate(root.netTxKbps)
                Layout.alignment: Qt.AlignRight
            }

            QQC2.Label { text: i18n("Disk"); opacity: 0.7 }
            QQC2.Label {
                text: "R " + root.fmtRate(root.diskReadKbps) + "   W " + root.fmtRate(root.diskWriteKbps)
                Layout.alignment: Qt.AlignRight
            }
        }
    }
}
