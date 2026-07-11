import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

// One metric row: a label, and a number and/or a sparkline depending on
// displayMode (0 = numbers only, 1 = charts only, 2 = both).
RowLayout {
    id: row

    property string label: ""
    property string value: ""
    property var history: []
    property color chartColor: "white"
    property int displayMode: 0

    Layout.fillWidth: true
    spacing: Kirigami.Units.largeSpacing

    QQC2.Label {
        text: row.label
        opacity: 0.7
        Layout.preferredWidth: Kirigami.Units.gridUnit * 4
    }

    QQC2.Label {
        text: row.value
        visible: row.displayMode !== 1
        Layout.fillWidth: row.displayMode === 0
        horizontalAlignment: Text.AlignRight
    }

    Sparkline {
        values: row.history
        lineColor: row.chartColor
        visible: row.displayMode !== 0
        Layout.fillWidth: true
        Layout.minimumWidth: Kirigami.Units.gridUnit * 4
        Layout.preferredHeight: Kirigami.Units.gridUnit * 1.3
    }
}
