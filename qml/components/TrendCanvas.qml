import QtQuick 2.15
import QtQuick.Controls 2.15

Rectangle {
    id: root
    signal paintRendered(int token)
    property int updateToken: 0
    property int _lastPaintToken: 0
    property bool repaintPending: false

    property bool overlayMode: false
    property var points: []
    property var series: []
    property string emptyText: "Нет данных для построения графика"
    property color panelBg: "#f7fbff"
    property color panelBorder: "#d6e2ef"
    property color fuelColor: "#10b981"
    property color temperatureColor: "#f97316"
    property int rangeStart: 0
    property int rangeEnd: -1
    property var temperatureBands: []
    // 0: температура, 1: время.
    property int xAxisMode: 0
    property bool sortLineByX: true
    property bool showPointLabels: false
    property int maxRenderPoints: 1200
    property int maxPointLabels: 60
    property bool swapAxes: false
    property bool smoothSeriesEnabled: true
    property real smoothSeriesAlpha: 0.22
    property bool averageEnabled: false
    property int averageWindow: 5
    property bool drawLineEnabled: true
    property bool drawMarkersEnabled: true
    property int adaptiveRenderFactor: 3
    property int maxMarkerPoints: 1600
    property string customXAxisTitle: ""
    property string customYAxisTitle: ""
    property int xMajorTicks: 5
    property int yMajorTicks: 5
    property bool resetViewportOnDataChange: false
    property bool secondaryYAxisEnabled: false
    property string secondaryYAxisTitle: ""
    property real secondaryYAxisEmptyPeriod: NaN
    property real secondaryYAxisFullPeriod: NaN

    // Compatibility properties.
    property real zoomX: 1.0
    property bool wheelZoomEnabled: true
    property int panOffset: 0

    // Interaction toggles.
    property bool dragZoomEnabled: true
    property bool dragPanEnabled: true

    // Manual viewport (data space).
    property bool manualViewport: false
    property real viewportXMin: NaN
    property real viewportXMax: NaN
    property real viewportYMin: NaN
    property real viewportYMax: NaN

    // Last drawn chart geometry/bounds (canvas local coordinates).
    property real _chartLeft: 0
    property real _chartTop: 0
    property real _chartWidth: 0
    property real _chartHeight: 0
    property real _drawXMin: 0
    property real _drawXMax: 1
    property real _drawYMin: 0
    property real _drawYMax: 1
    property real _baseXMin: 0
    property real _baseXMax: 1
    property real _baseYMin: 0
    property real _baseYMax: 1
    property bool _repaintQueued: false

    radius: 12
    color: root.panelBg
    border.color: root.panelBorder
    border.width: 1
    implicitHeight: 300

    function normalizeRange(totalCount) {
        if (totalCount <= 0)
            return { "start": 0, "end": -1 }

        var start = Number(root.rangeStart)
        if (isNaN(start))
            start = 0
        start = Math.max(0, Math.min(totalCount - 1, Math.floor(start)))

        var end = Number(root.rangeEnd)
        if (root.rangeEnd < 0 || isNaN(end))
            end = totalCount - 1
        end = Math.max(0, Math.min(totalCount - 1, Math.floor(end)))

        if (end < start) {
            var tmp = start
            start = end
            end = tmp
        }
        return { "start": start, "end": end }
    }

    function decimatePoints(sourcePoints, maxCount) {
        if (!sourcePoints || sourcePoints.length <= 0)
            return []
        var limit = Math.floor(Number(maxCount))
        if (!isFinite(limit) || limit <= 0 || sourcePoints.length <= limit)
            return sourcePoints

        var step = Math.max(1, Math.floor(sourcePoints.length / limit))
        var result = []
        for (var i = 0; i < sourcePoints.length; i += step)
            result.push(sourcePoints[i])
        if (result.length <= 0 || result[result.length - 1] !== sourcePoints[sourcePoints.length - 1])
            result.push(sourcePoints[sourcePoints.length - 1])
        return result
    }

    function smoothPoints(sourcePoints) {
        if (!sourcePoints || sourcePoints.length <= 2 || !root.smoothSeriesEnabled)
            return sourcePoints

        var alpha = Number(root.smoothSeriesAlpha)
        if (!isFinite(alpha))
            alpha = 0.22
        alpha = Math.max(0.02, Math.min(1.0, alpha))
        if (alpha >= 0.999)
            return sourcePoints

        var first = sourcePoints[0]
        var smoothFuel = Number(first.fuel)
        var smoothTemperature = Number(first.temperature)
        var result = [{
            "_idx": first._idx,
            "fuel": smoothFuel,
            "temperature": smoothTemperature,
            "time": first.time,
            "isHighlight": !!first.isHighlight,
            "highlightLabel": first.highlightLabel ? String(first.highlightLabel) : ""
        }]

        for (var i = 1; i < sourcePoints.length; i++) {
            var point = sourcePoints[i]
            var fuel = Number(point.fuel)
            var temperature = Number(point.temperature)
            if (!isFinite(fuel))
                fuel = smoothFuel
            if (!isFinite(temperature))
                temperature = smoothTemperature

            smoothFuel += (fuel - smoothFuel) * alpha
            smoothTemperature += (temperature - smoothTemperature) * alpha
            result.push({
                "_idx": point._idx,
                "fuel": smoothFuel,
                "temperature": smoothTemperature,
                "time": point.time,
                "isHighlight": !!point.isHighlight,
                "highlightLabel": point.highlightLabel ? String(point.highlightLabel) : ""
            })
        }
        return result
    }

    function averagePoints(sourcePoints) {
        if (!sourcePoints || sourcePoints.length <= 2 || !root.averageEnabled)
            return sourcePoints

        var windowSize = Math.max(1, Math.floor(Number(root.averageWindow)))
        if (windowSize <= 1)
            return sourcePoints

        var result = []
        for (var i = 0; i < sourcePoints.length; i++) {
            var start = Math.max(0, i - windowSize + 1)
            var sumFuel = 0.0
            var sumTemp = 0.0
            var count = 0
            for (var j = start; j <= i; j++) {
                sumFuel += Number(sourcePoints[j].fuel)
                sumTemp += Number(sourcePoints[j].temperature)
                count += 1
            }

            var src = sourcePoints[i]
            result.push({
                "_idx": src._idx,
                "fuel": count > 0 ? (sumFuel / count) : Number(src.fuel),
                "temperature": count > 0 ? (sumTemp / count) : Number(src.temperature),
                "time": src.time,
                "timeSec": src.timeSec,
                "isHighlight": !!src.isHighlight,
                "highlightLabel": src.highlightLabel ? String(src.highlightLabel) : ""
            })
        }
        return result
    }

    function parseTimeToSeconds(timeText, fallbackSeconds) {
        var raw = String(timeText || "").trim()
        if (raw.length <= 0)
            return fallbackSeconds
        var t = raw
        var spaceIdx = t.indexOf(" ")
        if (spaceIdx >= 0)
            t = t.slice(spaceIdx + 1)
        var parts = t.split(":")
        if (parts.length < 3)
            return fallbackSeconds
        var hh = Number(parts[0])
        var mm = Number(parts[1])
        var ss = Number(parts[2].replace(",", "."))
        if (!isFinite(hh) || !isFinite(mm) || !isFinite(ss))
            return fallbackSeconds
        return hh * 3600.0 + mm * 60.0 + ss
    }

    function formatSecondsAsTime(secondsValue) {
        var total = Number(secondsValue)
        if (!isFinite(total))
            return "--:--:--"
        if (total < 0)
            total = 0
        var hours = Math.floor(total / 3600.0)
        var minutes = Math.floor((total - hours * 3600.0) / 60.0)
        var seconds = total - hours * 3600.0 - minutes * 60.0
        var secInt = Math.floor(seconds)

        function p2(v) { return (v < 10 ? "0" : "") + String(v) }
        return p2(hours) + ":" + p2(minutes) + ":" + p2(secInt)
    }

    function selectRange(sourcePoints) {
        if (!sourcePoints || sourcePoints.length <= 0)
            return []

        var normalized = normalizeRange(sourcePoints.length)
        if (normalized.end < normalized.start)
            return []

        var selected = []
        var dayOffsetSec = 0.0
        var prevAbsSec = NaN
        for (var i = normalized.start; i <= normalized.end; i++) {
            var p = sourcePoints[i]
            var rawSec = parseTimeToSeconds(p.time, i)
            var absSec = rawSec + dayOffsetSec

            // Цель блока в корректной склейке временной оси между сутками.
            // Он добавляет смещение 24 часа при переходе времени через полночь.
            if (isFinite(prevAbsSec) && isFinite(absSec) && absSec < prevAbsSec - 1.0) {
                dayOffsetSec += 24.0 * 3600.0
                absSec = rawSec + dayOffsetSec
            }

            // Цель блока в подавлении мелких обратных скачков меток времени.
            // Он удерживает монотонность оси, чтобы линия не строила ложные перемычки.
            if (isFinite(prevAbsSec) && isFinite(absSec) && absSec < prevAbsSec)
                absSec = prevAbsSec

            selected.push({
                "_idx": i,
                "fuel": Number(p.fuel),
                "temperature": Number(p.temperature),
                "time": p.time,
                "timeSec": absSec,
                "isHighlight": !!p.isHighlight,
                "highlightLabel": p.highlightLabel ? String(p.highlightLabel) : ""
            })
            prevAbsSec = absSec
        }
        return averagePoints(smoothPoints(decimatePoints(selected, root.maxRenderPoints)))
    }

    function xValue(point) {
        if (root.xAxisMode === 1)
            return isFinite(Number(point.timeSec)) ? Number(point.timeSec) : Number(point._idx)
        return root.swapAxes ? Number(point.fuel) : Number(point.temperature)
    }

    function yValue(point) {
        return root.swapAxes ? Number(point.temperature) : Number(point.fuel)
    }

    function buildSeriesForRender() {
        var renderSeries = []
        if (root.overlayMode) {
            if (!root.series)
                return renderSeries
            for (var i = 0; i < root.series.length; i++) {
                var item = root.series[i]
                if (!item || !item.points)
                    continue
                var selected = selectRange(item.points)
                if (selected.length <= 0)
                    continue
                renderSeries.push({
                    "node": item.node ? String(item.node) : "",
                    "color": item.color ? item.color : "#2563eb",
                    "points": selected
                })
            }
            return renderSeries
        }

        var selectedSingle = selectRange(root.points)
        if (selectedSingle.length > 0) {
            renderSeries.push({
                "node": "",
                "color": root.fuelColor,
                "points": selectedSingle
            })
        }
        return renderSeries
    }

    function xAxisTitle() {
        if (root.customXAxisTitle && root.customXAxisTitle.length > 0)
            return root.customXAxisTitle
        if (root.xAxisMode === 1)
            return "Время"
        return root.swapAxes ? "Уровень топлива, %" : "Температура, C"
    }

    function yAxisTitle() {
        if (root.customYAxisTitle && root.customYAxisTitle.length > 0)
            return root.customYAxisTitle
        return root.swapAxes ? "Температура, C" : "Уровень топлива, %"
    }

    function requestRepaint() {
        if (root._repaintQueued)
            return
        root.repaintPending = true
        root._repaintQueued = true
        repaintTimer.start()
    }

    function handleDataSourceChanged() {
        if (root.resetViewportOnDataChange) {
            root.manualViewport = false
            root.viewportXMin = NaN
            root.viewportXMax = NaN
            root.viewportYMin = NaN
            root.viewportYMax = NaN
        }
        root.requestRepaint()
    }

    function safeTickCount(value) {
        var parsed = Math.floor(Number(value))
        if (!isFinite(parsed) || parsed < 2)
            return 2
        return parsed
    }

    function secondaryLevelFromPeriod(periodValue) {
        var emptyPeriod = Number(root.secondaryYAxisEmptyPeriod)
        var fullPeriod = Number(root.secondaryYAxisFullPeriod)
        var denominator = fullPeriod - emptyPeriod
        if (!isFinite(emptyPeriod) || !isFinite(fullPeriod) || Math.abs(denominator) < 1e-12)
            return NaN
        return ((Number(periodValue) - emptyPeriod) * 100.0) / denominator
    }

    function hasDrawableViewport() {
        return root._chartWidth > 2
            && root._chartHeight > 2
            && isFinite(root._drawXMin)
            && isFinite(root._drawXMax)
            && isFinite(root._drawYMin)
            && isFinite(root._drawYMax)
            && Math.abs(root._drawXMax - root._drawXMin) > 1e-12
            && Math.abs(root._drawYMax - root._drawYMin) > 1e-12
    }

    function resetView() {
        root.manualViewport = false
        root.viewportXMin = NaN
        root.viewportXMax = NaN
        root.viewportYMin = NaN
        root.viewportYMax = NaN
        root.requestRepaint()
    }

    function _ensureManualViewportFromCurrent() {
        if (!root.hasDrawableViewport())
            return false

        if (!root.manualViewport
                || !isFinite(root.viewportXMin) || !isFinite(root.viewportXMax)
                || !isFinite(root.viewportYMin) || !isFinite(root.viewportYMax)) {
            root.viewportXMin = root._drawXMin
            root.viewportXMax = root._drawXMax
            root.viewportYMin = root._drawYMin
            root.viewportYMax = root._drawYMax
        }
        root.manualViewport = true
        return true
    }

    function zoomAtPixel(px, py, factor) {
        if (!root.wheelZoomEnabled || !root.hasDrawableViewport())
            return
        if (!root._ensureManualViewportFromCurrent())
            return

        var zoomFactor = Number(factor)
        if (!isFinite(zoomFactor) || zoomFactor <= 0.0)
            return

        var chartX0 = root._chartLeft
        var chartY0 = root._chartTop
        var chartX1 = chartX0 + root._chartWidth
        var chartY1 = chartY0 + root._chartHeight
        var cx = Math.max(chartX0, Math.min(chartX1, Number(px)))
        var cy = Math.max(chartY0, Math.min(chartY1, Number(py)))

        var ratioX = (cx - chartX0) / root._chartWidth
        var ratioY = (cy - chartY0) / root._chartHeight

        var spanX = root.viewportXMax - root.viewportXMin
        var spanY = root.viewportYMax - root.viewportYMin
        if (!isFinite(spanX) || !isFinite(spanY) || spanX <= 1e-12 || spanY <= 1e-12)
            return

        var baseSpanX = Math.max(1e-9, Math.abs(root._baseXMax - root._baseXMin))
        var baseSpanY = Math.max(1e-9, Math.abs(root._baseYMax - root._baseYMin))
        var minSpanX = Math.max(1e-6, baseSpanX * 0.001)
        var minSpanY = Math.max(1e-6, baseSpanY * 0.001)
        var maxSpanX = Math.max(minSpanX, baseSpanX * 200.0)
        var maxSpanY = Math.max(minSpanY, baseSpanY * 200.0)

        var newSpanX = Math.max(minSpanX, Math.min(maxSpanX, spanX * zoomFactor))
        var newSpanY = Math.max(minSpanY, Math.min(maxSpanY, spanY * zoomFactor))

        var anchorX = root.viewportXMin + ratioX * spanX
        var anchorY = root.viewportYMin + (1.0 - ratioY) * spanY

        root.viewportXMin = anchorX - ratioX * newSpanX
        root.viewportXMax = root.viewportXMin + newSpanX
        root.viewportYMin = anchorY - (1.0 - ratioY) * newSpanY
        root.viewportYMax = root.viewportYMin + newSpanY
        root.requestRepaint()
    }

    function panByPixels(dx, dy) {
        if (!root.dragPanEnabled || !root.hasDrawableViewport())
            return
        if (!root._ensureManualViewportFromCurrent())
            return

        var spanX = root.viewportXMax - root.viewportXMin
        var spanY = root.viewportYMax - root.viewportYMin
        if (!isFinite(spanX) || !isFinite(spanY) || spanX <= 1e-12 || spanY <= 1e-12)
            return

        var shiftX = -Number(dx) / root._chartWidth * spanX
        var shiftY = Number(dy) / root._chartHeight * spanY
        root.viewportXMin += shiftX
        root.viewportXMax += shiftX
        root.viewportYMin += shiftY
        root.viewportYMax += shiftY
        root.requestRepaint()
    }

    onPointsChanged: handleDataSourceChanged()
    onSeriesChanged: handleDataSourceChanged()
    onOverlayModeChanged: handleDataSourceChanged()
    onRangeStartChanged: requestRepaint()
    onRangeEndChanged: requestRepaint()
    onTemperatureBandsChanged: requestRepaint()
    onShowPointLabelsChanged: requestRepaint()
    onSwapAxesChanged: requestRepaint()
    onXAxisModeChanged: requestRepaint()
    onSortLineByXChanged: requestRepaint()
    onSmoothSeriesEnabledChanged: requestRepaint()
    onSmoothSeriesAlphaChanged: requestRepaint()
    onAverageEnabledChanged: requestRepaint()
    onAverageWindowChanged: requestRepaint()
    onDrawLineEnabledChanged: requestRepaint()
    onDrawMarkersEnabledChanged: requestRepaint()
    onXMajorTicksChanged: requestRepaint()
    onYMajorTicksChanged: requestRepaint()
    onSecondaryYAxisEnabledChanged: requestRepaint()
    onSecondaryYAxisTitleChanged: requestRepaint()
    onSecondaryYAxisEmptyPeriodChanged: requestRepaint()
    onSecondaryYAxisFullPeriodChanged: requestRepaint()
    onUpdateTokenChanged: requestRepaint()

    Canvas {
        id: canvas
        anchors.fill: parent
        anchors.leftMargin: 18
        anchors.rightMargin: 14
        anchors.topMargin: 16
        anchors.bottomMargin: 40
        antialiasing: true
        renderTarget: Canvas.FramebufferObject
        renderStrategy: Canvas.Threaded
        z: 1

        Component.onCompleted: root.requestRepaint()
        onWidthChanged: root.requestRepaint()
        onHeightChanged: root.requestRepaint()

        function drawBackground(ctx, l, t, pw, ph) {
            ctx.fillStyle = "#ffffff"
            ctx.fillRect(0, 0, width, height)
        }

        function tickDecimals(stepValue) {
            var s = Math.abs(Number(stepValue))
            if (!isFinite(s) || s <= 0.0)
                return 1
            if (s >= 10.0)
                return 0
            if (s >= 1.0)
                return 1
            if (s >= 0.1)
                return 2
            if (s >= 0.01)
                return 3
            return 4
        }

        function buildAdaptiveTicks(minValue, maxValue, targetTickCount) {
            var minV = Number(minValue)
            var maxV = Number(maxValue)
            var span = Math.abs(maxV - minV)
            if (!isFinite(minV) || !isFinite(maxV) || span <= 1e-12)
                return { "values": [minV, maxV], "step": 1.0 }

            function niceNumber(value, roundResult) {
                var exponent = Math.floor(Math.log(value) / Math.LN10)
                var fraction = value / Math.pow(10, exponent)
                var niceFraction = 1.0
                if (roundResult) {
                    if (fraction < 1.5)
                        niceFraction = 1.0
                    else if (fraction < 3.0)
                        niceFraction = 2.0
                    else if (fraction < 7.0)
                        niceFraction = 5.0
                    else
                        niceFraction = 10.0
                } else {
                    if (fraction <= 1.0)
                        niceFraction = 1.0
                    else if (fraction <= 2.0)
                        niceFraction = 2.0
                    else if (fraction <= 5.0)
                        niceFraction = 5.0
                    else
                        niceFraction = 10.0
                }
                return niceFraction * Math.pow(10, exponent)
            }

            // Цель блока в подборе «красивого» фиксированного шага по диапазону.
            // Он учитывает введенную пользователем цель плотности сетки.
            var target = Math.max(2, Math.floor(Number(targetTickCount)))
            var rawStep = span / Math.max(1, (target - 1))
            if (!isFinite(rawStep) || rawStep <= 0.0)
                rawStep = 1.0
            var step = niceNumber(rawStep, true)
            if (!isFinite(step) || step <= 0.0)
                step = rawStep

            var start = Math.floor(minV / step) * step
            var end = Math.ceil(maxV / step) * step
            var values = []
            var maxIterations = Math.min(5000, Math.max(50, target * 6))
            var idx = 0
            for (var v = start; v <= end + step * 0.5 && idx < maxIterations; v += step) {
                values.push(v)
                idx += 1
            }
            if (values.length < 2)
                values = [minV, maxV]

            return { "values": values, "step": step }
        }

        function drawLabel(ctx, x, y, text, color) {
            ctx.save()
            ctx.font = "10px Bahnschrift"
            var textWidth = ctx.measureText(text).width
            var rectW = Math.ceil(textWidth + 8)
            var rectH = 14
            var px = Math.round(x - rectW / 2)
            var py = Math.round(y - rectH)

            if (px < 2)
                px = 2
            if (px + rectW > width - 2)
                px = width - rectW - 2
            if (py < 2)
                py = 2
            if (py + rectH > height - 2)
                py = height - rectH - 2

            ctx.fillStyle = "rgba(255,255,255,0.92)"
            ctx.strokeStyle = color
            ctx.lineWidth = 1
            ctx.fillRect(px, py, rectW, rectH)
            ctx.strokeRect(px, py, rectW, rectH)
            ctx.fillStyle = "#1f2d3d"
            ctx.fillText(text, px + 4, py + 10)
            ctx.restore()
        }

        onPaint: {
            root._lastPaintToken = root.updateToken
            var ctx = getContext("2d")
            ctx.reset()

            var w = width
            var h = height
            if (w < 60 || h < 60)
                return

            var l = 52
            var r = root.secondaryYAxisEnabled ? 64 : 14
            var t = 8
            var b = root.xAxisMode === 1 ? 84 : 26
            var pw = w - l - r
            var ph = h - t - b
            if (pw <= 2 || ph <= 2)
                return

            root._chartLeft = l
            root._chartTop = t
            root._chartWidth = pw
            root._chartHeight = ph

            drawBackground(ctx, l, t, pw, ph)

            var dataSeries = root.buildSeriesForRender()
            if (!dataSeries || dataSeries.length <= 0) {
                ctx.fillStyle = "#8aa0b6"
                ctx.font = "12px Bahnschrift"
                ctx.fillText(root.emptyText, l + 10, t + ph / 2)
                return
            }

            var found = false
            var xMin = 0
            var xMax = 0
            var yMin = 0
            var yMax = 0

            for (var si = 0; si < dataSeries.length; si++) {
                var pts = dataSeries[si].points
                for (var pi = 0; pi < pts.length; pi++) {
                    var xv = root.xValue(pts[pi])
                    var yv = root.yValue(pts[pi])
                    if (isNaN(xv) || isNaN(yv))
                        continue
                    if (!found) {
                        xMin = xv
                        xMax = xv
                        yMin = yv
                        yMax = yv
                        found = true
                    } else {
                        if (xv < xMin) xMin = xv
                        if (xv > xMax) xMax = xv
                        if (yv < yMin) yMin = yv
                        if (yv > yMax) yMax = yv
                    }
                }
            }

            if (!found)
                return

            var xSpan = Math.abs(xMax - xMin)
            var ySpan = Math.abs(yMax - yMin)
            if (xSpan < 1e-6) {
                xMin -= 0.5
                xMax += 0.5
                xSpan = 1.0
            }
            if (ySpan < 1e-6) {
                yMin -= 0.5
                yMax += 0.5
                ySpan = 1.0
            }

            var xPad = Math.max(0.2, xSpan * 0.06)
            var yPad = Math.max(0.2, ySpan * 0.06)
            var baseXMin = xMin - xPad
            var baseXMax = xMax + xPad
            var baseYMin = yMin - yPad
            var baseYMax = yMax + yPad

            root._baseXMin = baseXMin
            root._baseXMax = baseXMax
            root._baseYMin = baseYMin
            root._baseYMax = baseYMax

            var viewXMin = baseXMin
            var viewXMax = baseXMax
            var viewYMin = baseYMin
            var viewYMax = baseYMax

            if (root.manualViewport) {
                var vx0 = Number(root.viewportXMin)
                var vx1 = Number(root.viewportXMax)
                var vy0 = Number(root.viewportYMin)
                var vy1 = Number(root.viewportYMax)
                if (isFinite(vx0) && isFinite(vx1) && Math.abs(vx1 - vx0) > 1e-12) {
                    viewXMin = Math.min(vx0, vx1)
                    viewXMax = Math.max(vx0, vx1)
                }
                if (isFinite(vy0) && isFinite(vy1) && Math.abs(vy1 - vy0) > 1e-12) {
                    viewYMin = Math.min(vy0, vy1)
                    viewYMax = Math.max(vy0, vy1)
                }
            }

            var baseSpanX = Math.max(1e-9, baseXMax - baseXMin)
            var baseSpanY = Math.max(1e-9, baseYMax - baseYMin)
            var minSpanX = Math.max(1e-6, baseSpanX * 0.001)
            var minSpanY = Math.max(1e-6, baseSpanY * 0.001)

            if ((viewXMax - viewXMin) < minSpanX) {
                var cx = (viewXMin + viewXMax) * 0.5
                viewXMin = cx - minSpanX * 0.5
                viewXMax = cx + minSpanX * 0.5
            }
            if ((viewYMax - viewYMin) < minSpanY) {
                var cy = (viewYMin + viewYMax) * 0.5
                viewYMin = cy - minSpanY * 0.5
                viewYMax = cy + minSpanY * 0.5
            }

            root._drawXMin = viewXMin
            root._drawXMax = viewXMax
            root._drawYMin = viewYMin
            root._drawYMax = viewYMax
            root.zoomX = baseSpanX / Math.max(minSpanX, viewXMax - viewXMin)
            root.panOffset = Math.round(((viewXMin - baseXMin) / baseSpanX) * 1000.0)

            function mapX(v) {
                var ratio = (Number(v) - viewXMin) / (viewXMax - viewXMin)
                return l + ratio * pw
            }
            function mapY(v) {
                var ratio = (Number(v) - viewYMin) / (viewYMax - viewYMin)
                return t + (1.0 - ratio) * ph
            }

            var xTickData = buildAdaptiveTicks(viewXMin, viewXMax, root.xMajorTicks)
            var yTickData = buildAdaptiveTicks(viewYMin, viewYMax, root.yMajorTicks)
            var xTickValues = xTickData.values
            var yTickValues = yTickData.values
            var xDecimals = tickDecimals(xTickData.step)
            var yDecimals = tickDecimals(yTickData.step)
            var timeRefPoints = null
            if (root.xAxisMode === 1 && dataSeries.length > 0)
                timeRefPoints = dataSeries[0].points

            function nearestTemperatureAtTime(referencePoints, targetX) {
                if (!referencePoints || referencePoints.length <= 0)
                    return NaN
                var nearestTemp = NaN
                var nearestDx = Number.POSITIVE_INFINITY
                for (var ni = 0; ni < referencePoints.length; ni++) {
                    var p = referencePoints[ni]
                    var px = root.xValue(p)
                    var pt = Number(p.temperature)
                    if (!isFinite(px) || !isFinite(pt))
                        continue
                    var dx = Math.abs(px - targetX)
                    if (dx < nearestDx) {
                        nearestDx = dx
                        nearestTemp = pt
                    }
                }
                return nearestTemp
            }

            ctx.save()
            ctx.strokeStyle = "#e2ebf5"
            ctx.lineWidth = 1
            for (var xgi = 0; xgi < xTickValues.length; xgi++) {
                var gx = mapX(xTickValues[xgi])
                ctx.beginPath()
                ctx.moveTo(gx, t)
                ctx.lineTo(gx, t + ph)
                ctx.stroke()
            }
            for (var ygi = 0; ygi < yTickValues.length; ygi++) {
                var gy = mapY(yTickValues[ygi])
                ctx.beginPath()
                ctx.moveTo(l, gy)
                ctx.lineTo(l + pw, gy)
                ctx.stroke()
            }
            ctx.strokeStyle = "#b9ccdf"
            ctx.strokeRect(l, t, pw, ph)
            ctx.restore()

            if (!root.swapAxes && root.temperatureBands && root.temperatureBands.length > 0) {
                for (var bi = 0; bi < root.temperatureBands.length; bi++) {
                    var band = root.temperatureBands[bi]
                    if (!band)
                        continue

                    var bandStart = Number(band.startTemp)
                    var bandEnd = Number(band.endTemp)
                    if (!isFinite(bandStart) || !isFinite(bandEnd))
                        continue
                    if (bandEnd < bandStart) {
                        var tmpBand = bandStart
                        bandStart = bandEnd
                        bandEnd = tmpBand
                    }
                    if (bandEnd < viewXMin || bandStart > viewXMax)
                        continue

                    var rx0 = Math.max(viewXMin, bandStart)
                    var rx1 = Math.min(viewXMax, bandEnd)
                    var px0 = mapX(rx0)
                    var px1 = mapX(rx1)
                    var rectX = Math.min(px0, px1)
                    var rectW = Math.max(2, Math.abs(px1 - px0))

                    ctx.save()
                    ctx.fillStyle = "rgba(239, 68, 68, 0.12)"
                    ctx.strokeStyle = "rgba(220, 38, 38, 0.40)"
                    ctx.lineWidth = 1
                    ctx.fillRect(rectX, t, rectW, ph)
                    ctx.strokeRect(rectX, t, rectW, ph)
                    ctx.restore()

                    if (band.label) {
                        var bandLabelX = rectX + rectW * 0.5
                        drawLabel(ctx, bandLabelX, t + 16, String(band.label), "#dc2626")
                    }
                }
            }

            function pushUnique(target, entry) {
                if (!entry)
                    return
                if (target.length > 0 && target[target.length - 1].idx === entry.idx)
                    return
                target.push(entry)
            }

            function buildRenderablePoints(sourcePoints) {
                if (!sourcePoints || sourcePoints.length <= 0)
                    return []

                var total = sourcePoints.length
                var denseLimit = Math.max(64, Math.floor(pw * 1.2))
                var result = []

                function addRawPoint(point, idx) {
                    var xv = root.xValue(point)
                    var yv = root.yValue(point)
                    if (!isFinite(xv) || !isFinite(yv))
                        return null
                    var rawTemp = Number(point.temperature)
                    if (!isFinite(rawTemp))
                        rawTemp = NaN
                    var highlightEnabled = !!(point && point.isHighlight)
                    var highlightLabel = ""
                    if (highlightEnabled && point.highlightLabel !== undefined && point.highlightLabel !== null)
                        highlightLabel = String(point.highlightLabel)
                    var entry = {
                        "idx": idx,
                        "x": mapX(xv),
                        "y": mapY(yv),
                        "rawX": xv,
                        "rawY": yv,
                        "rawTemp": rawTemp,
                        "isHighlight": highlightEnabled,
                        "highlightLabel": highlightLabel
                    }
                    if (!isFinite(entry.x) || !isFinite(entry.y))
                        return null
                    return entry
                }

                // Цель ветки в сохранении честной формы временного графика.
                // Она оставляет только последовательные точки во времени и исключает min/max бакетов.
                if (root.xAxisMode === 1) {
                    var timeLimit = Math.max(800, Math.floor(Number(root.maxRenderPoints)))
                    var stepT = Math.max(1, Math.ceil(total / timeLimit))

                    for (var jt = 0; jt < total; jt += stepT) {
                        var eT = addRawPoint(sourcePoints[jt], jt)
                        if (eT)
                            pushUnique(result, eT)
                    }

                    var tailT = addRawPoint(sourcePoints[total - 1], total - 1)
                    if (tailT)
                        pushUnique(result, tailT)
                    return result
                }

                if (total <= denseLimit) {
                    for (var i = 0; i < total; i++) {
                        var rawEntry = addRawPoint(sourcePoints[i], i)
                        if (rawEntry)
                            result.push(rawEntry)
                    }
                    return result
                }

                var renderFactor = Math.max(1, Math.floor(Number(root.adaptiveRenderFactor)))
                var targetBuckets = Math.max(64, Math.floor(pw * renderFactor))
                var bucketSize = Math.max(1, Math.ceil(total / targetBuckets))

                for (var start = 0; start < total; start += bucketSize) {
                    var end = Math.min(total, start + bucketSize)
                    var first = null
                    var last = null
                    var minEntry = null
                    var maxEntry = null
                    var highlightEntries = []

                    for (var j = start; j < end; j++) {
                        var entry = addRawPoint(sourcePoints[j], j)
                        if (!entry)
                            continue

                        if (!first) {
                            first = entry
                            minEntry = entry
                            maxEntry = entry
                        }
                        last = entry
                        if (entry.y < minEntry.y)
                            minEntry = entry
                        if (entry.y > maxEntry.y)
                            maxEntry = entry
                        if (entry.isHighlight)
                            highlightEntries.push(entry)
                    }

                    if (!first)
                        continue

                    pushUnique(result, first)

                    var mids = []
                    if (minEntry && minEntry.idx !== first.idx && minEntry.idx !== last.idx)
                        mids.push(minEntry)
                    if (maxEntry && maxEntry.idx !== first.idx && maxEntry.idx !== last.idx && maxEntry.idx !== minEntry.idx)
                        mids.push(maxEntry)
                    mids.sort(function(a, b) { return a.idx - b.idx })
                    for (var m = 0; m < mids.length; m++)
                        pushUnique(result, mids[m])

                    highlightEntries.sort(function(a, b) { return a.idx - b.idx })
                    for (var hidx = 0; hidx < highlightEntries.length; hidx++)
                        pushUnique(result, highlightEntries[hidx])

                    pushUnique(result, last)
                }

                return result
            }

            ctx.save()
            ctx.font = "10px Bahnschrift"
            ctx.fillStyle = "#51667d"
            ctx.textBaseline = "middle"

            for (var xt = 0; xt < xTickValues.length; xt++) {
                var xx = mapX(xTickValues[xt])
                if (root.xAxisMode === 1) {
                    var timeLine = root.formatSecondsAsTime(xTickValues[xt])
                    var tempLine = ""
                    var tempAtTick = nearestTemperatureAtTime(timeRefPoints, xTickValues[xt])
                    if (isFinite(tempAtTick))
                        tempLine = tempAtTick.toFixed(1) + "°C"
                    ctx.save()
                    ctx.translate(xx - 2, t + ph + 42)
                    ctx.rotate(-Math.PI / 3.2)
                    ctx.textAlign = "right"
                    ctx.textBaseline = "alphabetic"
                    if (tempLine.length > 0) {
                        ctx.fillText(timeLine, 0, -4)
                        ctx.fillText(tempLine, 0, 10)
                    } else {
                        ctx.fillText(timeLine, 0, 2)
                    }
                    ctx.restore()
                } else {
                    ctx.textAlign = "center"
                    ctx.fillText(Number(xTickValues[xt]).toFixed(xDecimals), xx, t + ph + 14)
                }
            }

            for (var yt = 0; yt < yTickValues.length; yt++) {
                var yy = mapY(yTickValues[yt])
                ctx.textAlign = "right"
                ctx.fillText(Number(yTickValues[yt]).toFixed(yDecimals), l - 6, yy)
            }

            if (root.secondaryYAxisEnabled) {
                ctx.textAlign = "left"
                for (var yrt = 0; yrt < yTickValues.length; yrt++) {
                    var yvRight = yTickValues[yrt]
                    var yyRight = mapY(yvRight)
                    var levelTick = root.secondaryLevelFromPeriod(yvRight)
                    if (isFinite(levelTick))
                        ctx.fillText(levelTick.toFixed(1), l + pw + 6, yyRight)
                    else
                        ctx.fillText("-", l + pw + 6, yyRight)
                }
                if (root.secondaryYAxisTitle && root.secondaryYAxisTitle.length > 0) {
                    ctx.textBaseline = "alphabetic"
                    ctx.fillText(root.secondaryYAxisTitle, l + pw + 6, t - 2)
                    ctx.textBaseline = "middle"
                }
            }
            ctx.restore()

            ctx.save()
            ctx.beginPath()
            ctx.rect(l, t, pw, ph)
            ctx.clip()

            for (var di = 0; di < dataSeries.length; di++) {
                var seriesItem = dataSeries[di]
                var color = seriesItem.color
                var points = seriesItem.points
                if (!points || points.length <= 0)
                    continue
                var renderPoints = buildRenderablePoints(points)
                if (!renderPoints || renderPoints.length <= 0)
                    continue

                if (root.drawLineEnabled) {
                    var linePoints = renderPoints.slice(0)
                    if (root.sortLineByX)
                        linePoints.sort(function(a, b) { return a.rawX - b.rawX })
                    ctx.strokeStyle = color
                    ctx.lineWidth = 1.8
                    ctx.globalAlpha = 0.85
                    ctx.beginPath()
                    if (linePoints.length <= 2 || root.xAxisMode === 1) {
                        var timeGapThreshold = Number.POSITIVE_INFINITY
                        if (root.xAxisMode === 1 && linePoints.length > 3) {
                            var dxList = []
                            for (var dxi = 1; dxi < linePoints.length; dxi++) {
                                var dxVal = linePoints[dxi].rawX - linePoints[dxi - 1].rawX
                                if (isFinite(dxVal) && dxVal > 0.0)
                                    dxList.push(dxVal)
                            }
                            if (dxList.length > 0) {
                                dxList.sort(function(a, b) { return a - b })
                                var medianDx = dxList[Math.floor(dxList.length / 2)]
                                var fullSpan = Math.max(1.0, root._drawXMax - root._drawXMin)
                                timeGapThreshold = Math.max(medianDx * 8.0, fullSpan / 14.0)
                            }
                        }
                        for (var li = 0; li < linePoints.length; li++) {
                            var px = linePoints[li].x
                            var py = linePoints[li].y
                            if (li === 0) {
                                ctx.moveTo(px, py)
                            } else {
                                var prevPx = linePoints[li - 1].x
                                var prevPy = linePoints[li - 1].y
                                var currDx = linePoints[li].rawX - linePoints[li - 1].rawX
                                if (root.xAxisMode === 1 && isFinite(currDx) && currDx > timeGapThreshold) {
                                    ctx.moveTo(px, py)
                                } else if (Math.abs(px - prevPx) < 0.5 && Math.abs(py - prevPy) < 0.5) {
                                    // Цель проверки в пропуске почти дублирующих точек.
                                    // Она снижает ложные «плашки» при плотных данных.
                                    continue
                                } else {
                                    ctx.lineTo(px, py)
                                }
                            }
                        }
                    } else {
                        ctx.moveTo(linePoints[0].x, linePoints[0].y)
                        for (var li2 = 1; li2 < linePoints.length - 1; li2++) {
                            var xc = (linePoints[li2].x + linePoints[li2 + 1].x) * 0.5
                            var yc = (linePoints[li2].y + linePoints[li2 + 1].y) * 0.5
                            ctx.quadraticCurveTo(linePoints[li2].x, linePoints[li2].y, xc, yc)
                        }
                        var last = linePoints[linePoints.length - 1]
                        var prev = linePoints[linePoints.length - 2]
                        ctx.quadraticCurveTo(prev.x, prev.y, last.x, last.y)
                    }
                    ctx.stroke()
                }

                ctx.globalAlpha = 1.0
                if (root.drawMarkersEnabled) {
                    var markerLimit = Math.max(100, Number(root.maxMarkerPoints))
                    var markerStep = Math.max(1, Math.ceil(renderPoints.length / markerLimit))
                    ctx.fillStyle = color
                    for (var pi2 = 0; pi2 < renderPoints.length; pi2 += markerStep) {
                        var pxx = renderPoints[pi2].x
                        var pyy = renderPoints[pi2].y
                        ctx.beginPath()
                        ctx.arc(pxx, pyy, 2.2, 0, Math.PI * 2)
                        ctx.fill()
                    }
                }

                if (root.showPointLabels) {
                    var maxLabels = Math.max(1, Number(root.maxPointLabels))
                    if (root.xAxisMode === 1)
                        maxLabels = Math.max(120, Math.floor(maxLabels * 2.4))
                    var labelStep = Math.max(1, Math.ceil(renderPoints.length / maxLabels))
                    for (var lb = 0; lb < renderPoints.length; lb += labelStep) {
                        var lx = renderPoints[lb].x
                        var ly = renderPoints[lb].y
                        if (lx < l || lx > (l + pw) || ly < t || ly > (t + ph))
                            continue
                        var valueText = ""
                        if (root.xAxisMode === 1 && isFinite(renderPoints[lb].rawTemp))
                            valueText = renderPoints[lb].rawTemp.toFixed(1) + "°C"
                        else
                            valueText = renderPoints[lb].rawX.toFixed(1) + ", " + renderPoints[lb].rawY.toFixed(1)
                        drawLabel(ctx, lx, ly - 6, valueText, color)
                    }
                }

                for (var hi = 0; hi < renderPoints.length; hi++) {
                    var highlighted = renderPoints[hi]
                    if (!highlighted.isHighlight)
                        continue
                    if (highlighted.x < l || highlighted.x > (l + pw) || highlighted.y < t || highlighted.y > (t + ph))
                        continue

                    ctx.save()
                    ctx.globalAlpha = 1.0
                    ctx.fillStyle = "#ffffff"
                    ctx.strokeStyle = color
                    ctx.lineWidth = 2
                    ctx.beginPath()
                    ctx.arc(highlighted.x, highlighted.y, 5.0, 0, Math.PI * 2)
                    ctx.fill()
                    ctx.stroke()
                    ctx.beginPath()
                    ctx.moveTo(highlighted.x - 6, highlighted.y)
                    ctx.lineTo(highlighted.x + 6, highlighted.y)
                    ctx.moveTo(highlighted.x, highlighted.y - 6)
                    ctx.lineTo(highlighted.x, highlighted.y + 6)
                    ctx.stroke()
                    ctx.restore()

                    if (highlighted.highlightLabel && highlighted.highlightLabel.length > 0)
                        drawLabel(ctx, highlighted.x, highlighted.y - 8, highlighted.highlightLabel, color)
                }
            }
            ctx.restore()
            ctx.globalAlpha = 1.0
        }

        onPainted: {
            root.repaintPending = false
            root.paintRendered(root._lastPaintToken)
        }
    }

    Timer {
        id: repaintTimer
        interval: 0
        repeat: false
        onTriggered: {
            root._repaintQueued = false
            canvas.requestPaint()
        }
    }

    MouseArea {
        id: interactionLayer
        anchors.fill: canvas
        z: 2
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        hoverEnabled: true
        preventStealing: true
        cursorShape: dragMode === "pan" ? Qt.ClosedHandCursor : Qt.CrossCursor

        property bool dragging: false
        property string dragMode: ""
        property real startX: 0
        property real startY: 0
        property real lastX: 0
        property real lastY: 0

        onPressed: {
            if (!root.hasDrawableViewport())
                return

            dragging = true
            startX = mouse.x
            startY = mouse.y
            lastX = mouse.x
            lastY = mouse.y

            if (mouse.button === Qt.RightButton && root.dragPanEnabled)
                dragMode = "pan"
            else if (mouse.button === Qt.LeftButton && root.dragZoomEnabled)
                dragMode = "zoom"
            else
                dragMode = ""
        }

        onPositionChanged: {
            if (!dragging)
                return

            if (dragMode === "pan") {
                root.panByPixels(mouse.x - lastX, mouse.y - lastY)
            }
            lastX = mouse.x
            lastY = mouse.y
        }

        onReleased: {
            if (!dragging)
                return

            if (dragMode === "zoom" && root.dragZoomEnabled) {
                var dx = Math.abs(lastX - startX)
                var dy = Math.abs(lastY - startY)
                if (dx >= 8 && dy >= 8 && root.hasDrawableViewport()) {
                    var chartX0 = root._chartLeft
                    var chartY0 = root._chartTop
                    var chartX1 = chartX0 + root._chartWidth
                    var chartY1 = chartY0 + root._chartHeight

                    var sx0 = Math.max(chartX0, Math.min(chartX1, Math.min(startX, lastX)))
                    var sx1 = Math.max(chartX0, Math.min(chartX1, Math.max(startX, lastX)))
                    var sy0 = Math.max(chartY0, Math.min(chartY1, Math.min(startY, lastY)))
                    var sy1 = Math.max(chartY0, Math.min(chartY1, Math.max(startY, lastY)))

                    if ((sx1 - sx0) >= 4 && (sy1 - sy0) >= 4) {
                        var rx0 = (sx0 - chartX0) / root._chartWidth
                        var rx1 = (sx1 - chartX0) / root._chartWidth
                        var ry0 = (sy0 - chartY0) / root._chartHeight
                        var ry1 = (sy1 - chartY0) / root._chartHeight

                        var dataX0 = root._drawXMin + rx0 * (root._drawXMax - root._drawXMin)
                        var dataX1 = root._drawXMin + rx1 * (root._drawXMax - root._drawXMin)
                        var dataY0 = root._drawYMin + (1.0 - ry0) * (root._drawYMax - root._drawYMin)
                        var dataY1 = root._drawYMin + (1.0 - ry1) * (root._drawYMax - root._drawYMin)

                        root.viewportXMin = Math.min(dataX0, dataX1)
                        root.viewportXMax = Math.max(dataX0, dataX1)
                        root.viewportYMin = Math.min(dataY0, dataY1)
                        root.viewportYMax = Math.max(dataY0, dataY1)
                        root.manualViewport = true
                        root.requestRepaint()
                    }
                }
            }

            dragging = false
            dragMode = ""
        }

        onCanceled: {
            dragging = false
            dragMode = ""
        }

        onWheel: {
            if (!root.wheelZoomEnabled || !root.hasDrawableViewport())
                return
            wheel.accepted = true
            var dy = wheel.angleDelta.y
            if (dy === 0)
                return
            var factor = dy > 0 ? 0.88 : 1.14
            root.zoomAtPixel(wheel.x, wheel.y, factor)
        }

        onDoubleClicked: root.resetView()

        Rectangle {
            visible: interactionLayer.dragging
                     && interactionLayer.dragMode === "zoom"
                     && Math.abs(interactionLayer.lastX - interactionLayer.startX) >= 4
                     && Math.abs(interactionLayer.lastY - interactionLayer.startY) >= 4
            x: Math.min(interactionLayer.startX, interactionLayer.lastX)
            y: Math.min(interactionLayer.startY, interactionLayer.lastY)
            width: Math.abs(interactionLayer.lastX - interactionLayer.startX)
            height: Math.abs(interactionLayer.lastY - interactionLayer.startY)
            color: "#2563eb22"
            border.color: "#1d4ed8"
            border.width: 1
            radius: 2
        }
    }

    Text {
        text: root.xAxisTitle()
        color: "#4f6379"
        font.pixelSize: 11
        font.family: "Bahnschrift"
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 7
        z: 3
    }

    Text {
        text: root.yAxisTitle()
        color: "#4f6379"
        font.pixelSize: 11
        font.family: "Bahnschrift"
        rotation: -90
        transformOrigin: Item.TopLeft
        x: 6
        y: parent.height - 16
        z: 3
    }
}
