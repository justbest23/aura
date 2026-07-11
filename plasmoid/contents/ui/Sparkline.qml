import QtQuick

// Minimal auto-scaled line chart over the last N samples.
Item {
    id: spark

    property var values: []
    property color lineColor: "white"

    Canvas {
        id: canvas
        anchors.fill: parent

        onPaint: {
            var ctx = getContext("2d")
            ctx.reset()

            var vals = spark.values
            if (!vals || vals.length < 2) {
                return
            }

            var minV = Math.min.apply(null, vals)
            var maxV = Math.max.apply(null, vals)
            var range = maxV - minV
            if (range < 1e-6) {
                range = Math.max(1, maxV * 0.1)
            }

            var pad = 2
            var w = width - pad * 2
            var h = height - pad * 2

            ctx.strokeStyle = spark.lineColor
            ctx.lineWidth = 1.5
            ctx.lineJoin = "round"
            ctx.beginPath()
            for (var i = 0; i < vals.length; i++) {
                var x = pad + (i / (vals.length - 1)) * w
                var y = pad + h - ((vals[i] - minV) / range) * h
                if (i === 0) {
                    ctx.moveTo(x, y)
                } else {
                    ctx.lineTo(x, y)
                }
            }
            ctx.stroke()
        }
    }

    onValuesChanged: canvas.requestPaint()
    onWidthChanged: canvas.requestPaint()
    onHeightChanged: canvas.requestPaint()
    Component.onCompleted: canvas.requestPaint()
}
