import QtQuick.Controls as QQC2
import org.kde.kcmutils as KCM
import org.kde.kirigami as Kirigami

KCM.SimpleKCM {
    property alias cfg_fadeDurationMs: fadeDurationSpin.value

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
    }
}
