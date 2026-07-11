import QtQuick.Controls as QQC2
import org.kde.kcmutils as KCM
import org.kde.kirigami as Kirigami

KCM.SimpleKCM {
    property alias cfg_fadeDurationMs: fadeDurationSpin.value
    property alias cfg_showStats: showStatsCheck.checked
    property alias cfg_statsDisplay: statsDisplayCombo.currentIndex
    property alias cfg_showBackground: showBackgroundCheck.checked

    Kirigami.FormLayout {
        QQC2.SpinBox {
            id: fadeDurationSpin
            Kirigami.FormData.label: i18n("Fade duration:")
            from: 100
            to: 5000
            stepSize: 100
            textFromValue: (value) => i18n("%1 ms", value)
            valueFromText: (text) => parseInt(text)
        }

        QQC2.CheckBox {
            id: showStatsCheck
            Kirigami.FormData.label: i18n("Details:")
            text: i18n("Show exact sensor readings")
        }

        QQC2.ComboBox {
            id: statsDisplayCombo
            Kirigami.FormData.label: i18n("Show as:")
            enabled: showStatsCheck.checked
            model: [i18n("Numbers"), i18n("Charts"), i18n("Both")]
        }

        QQC2.CheckBox {
            id: showBackgroundCheck
            text: i18n("Show panel background")
        }
    }
}
