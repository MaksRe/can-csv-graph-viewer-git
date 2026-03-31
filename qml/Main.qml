import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import QtQuick.Dialogs
import "components"

ApplicationWindow {
    id: root
    visible: true
    width: 1480
    height: 900
    minimumWidth: 1200
    minimumHeight: 760
    title: "CAN CSV Graph Viewer"
    color: "#eef3f8"

    property color accentColor: "#3b82f6"
    property color accentSoftColor: "#dbeafe"
    property color textMainColor: "#1f2937"
    property color textSoftColor: "#64748b"
    property color cardBg: "#f9fbff"
    property color cardBorder: "#d9e3f0"
    property bool showAdvancedControls: false
    property int rangeStartIndex: 0
    property int rangeEndIndex: -1
    property int xGridTicks: 8
    property int yGridTicks: 8
    property string rangeStartInputText: "0"
    property string rangeEndInputText: "-1"
    property string averageWindowInputText: "5"
    property string xGridTicksInputText: "8"
    property string yGridTicksInputText: "8"
    property bool averageEnabled: false
    property int averageWindow: 5
    property bool drawLineEnabled: true
    property bool drawMarkersEnabled: true
    property int graphUpdateToken: 0
    readonly property bool graphUpdateInProgress: backend.busy || (trendCanvas ? trendCanvas.repaintPending : false)

    component SoftButton: Button {
        id: btn
        property color tone: root.accentColor
        property color toneBorder: "#2d6fdd"
        property color textColor: "#ffffff"
        implicitHeight: 34
        Layout.preferredHeight: implicitHeight
        Layout.maximumHeight: implicitHeight
        font.pixelSize: 13
        font.family: "Segoe UI"
        font.weight: Font.DemiBold
        background: Rectangle {
            radius: 10
            color: btn.down ? Qt.darker(btn.tone, 1.08) : (btn.hovered ? Qt.lighter(btn.tone, 1.05) : btn.tone)
            border.color: btn.toneBorder
            border.width: 1
        }
        contentItem: Text {
            text: btn.text
            color: btn.textColor
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            font: btn.font
        }
    }

    component SoftGhostButton: SoftButton {
        tone: "#ffffff"
        toneBorder: "#cbd5e1"
        textColor: "#1f2937"
    }

    component SoftCheckBox: CheckBox {
        id: cb
        spacing: 8
        font.pixelSize: 13
        font.family: "Segoe UI"
        leftPadding: 0
        rightPadding: 0
        topPadding: 0
        bottomPadding: 0
        implicitHeight: 24
        Layout.preferredHeight: implicitHeight
        Layout.maximumHeight: implicitHeight
        indicator: Rectangle {
            implicitWidth: 18
            implicitHeight: 18
            radius: 6
            color: cb.checked ? root.accentColor : "#ffffff"
            border.color: cb.checked ? "#2d6fdd" : "#c5d2e3"
            border.width: 1
            anchors.verticalCenter: parent.verticalCenter
            Text {
                anchors.centerIn: parent
                text: cb.checked ? "✓" : ""
                color: "#ffffff"
                font.pixelSize: 12
                font.bold: true
            }
        }
        contentItem: Text {
            text: cb.text
            color: root.textMainColor
            verticalAlignment: Text.AlignVCenter
            leftPadding: cb.indicator.width + cb.spacing
            rightPadding: 2
            anchors.verticalCenter: parent.verticalCenter
            font: cb.font
        }
    }

    component SoftComboBox: ComboBox {
        id: combo
        implicitHeight: 34
        Layout.preferredHeight: implicitHeight
        Layout.maximumHeight: implicitHeight
        font.pixelSize: 13
        font.family: "Segoe UI"
        background: Rectangle {
            radius: 10
            color: "#ffffff"
            border.color: combo.activeFocus ? root.accentColor : "#c9d6e8"
            border.width: 1
        }
        contentItem: Text {
            text: combo.displayText
            color: root.textMainColor
            verticalAlignment: Text.AlignVCenter
            leftPadding: 10
            rightPadding: 26
            elide: Text.ElideRight
            font: combo.font
        }
        indicator: Text {
            text: "▾"
            color: root.textSoftColor
            anchors.verticalCenter: parent.verticalCenter
            anchors.right: parent.right
            anchors.rightMargin: 10
            font.pixelSize: 12
        }
        popup: Popup {
            y: combo.height + 4
            width: combo.width
            padding: 4
            contentItem: ListView {
                clip: true
                implicitHeight: contentHeight
                model: combo.popup.visible ? combo.delegateModel : null
                currentIndex: combo.highlightedIndex
            }
            background: Rectangle {
                radius: 10
                color: "#ffffff"
                border.color: "#c9d6e8"
            }
        }
    }

    component SoftSpinBox: SpinBox {
        id: sb
        implicitHeight: 34
        Layout.preferredHeight: implicitHeight
        Layout.maximumHeight: implicitHeight
        font.pixelSize: 13
        font.family: "Segoe UI"
        background: Rectangle {
            radius: 10
            color: "#ffffff"
            border.color: sb.activeFocus ? root.accentColor : "#c9d6e8"
            border.width: 1
        }
    }

    component SoftTextField: TextField {
        id: tf
        implicitHeight: 34
        Layout.preferredHeight: implicitHeight
        Layout.maximumHeight: implicitHeight
        font.pixelSize: 13
        font.family: "Segoe UI"
        color: root.textMainColor
        selectedTextColor: "#ffffff"
        selectionColor: root.accentColor
        background: Rectangle {
            radius: 10
            color: "#ffffff"
            border.color: tf.activeFocus ? root.accentColor : "#c9d6e8"
            border.width: 1
        }
        padding: 8
    }

    component AdvancedParamLabel: Label {
        color: root.textSoftColor
        font.family: "Segoe UI"
        Layout.preferredWidth: 148
        Layout.maximumWidth: 148
        Layout.alignment: Qt.AlignVCenter | Qt.AlignLeft
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }

    component MetricInfoBadge: Rectangle {
        id: badge
        property string tipText: ""
        implicitWidth: 18
        implicitHeight: 18
        radius: 9
        color: "#e0ecff"
        border.color: "#93c5fd"
        border.width: 1

        Label {
            anchors.centerIn: parent
            text: "i"
            color: "#1d4ed8"
            font.pixelSize: 12
            font.bold: true
            font.family: "Segoe UI"
        }

        MouseArea {
            id: badgeMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
        }

        ToolTip.visible: badgeMouse.containsMouse
        ToolTip.delay: 120
        ToolTip.timeout: 6000
        ToolTip.text: badge.tipText
    }

    function _dialogPaths() {
        var files = []
        if (csvDialog.selectedFiles && csvDialog.selectedFiles.length > 0) {
            for (var i = 0; i < csvDialog.selectedFiles.length; i += 1)
                files.push(csvDialog.selectedFiles[i])
        } else if (csvDialog.selectedFile) {
            files.push(csvDialog.selectedFile)
        }
        return files
    }

    function maxPointCountForCurrentMode() {
        var series = backend.visibleSeries
        if (!series || series.length === 0)
            return 0
        var maxCount = 0
        for (var i = 0; i < series.length; i += 1) {
            var c = Number(series[i].count ? series[i].count : (series[i].points ? series[i].points.length : 0))
            if (c > maxCount)
                maxCount = c
        }
        return maxCount
    }

    function nodeSelectorModel() {
        var model = ["— Не показывать узлы —"]
        var options = backend.nodeOptions
        for (var i = 0; i < options.length; i += 1)
            model.push(options[i])
        return model
    }

    function clampRangeToData() {
        var total = maxPointCountForCurrentMode()
        if (total <= 0) {
            rangeStartIndex = 0
            rangeEndIndex = -1
            return
        }
        rangeStartIndex = Math.max(0, Math.min(total - 1, rangeStartIndex))
        if (rangeEndIndex >= 0) {
            rangeEndIndex = Math.max(0, Math.min(total - 1, rangeEndIndex))
            if (rangeEndIndex < rangeStartIndex) {
                var t = rangeStartIndex
                rangeStartIndex = rangeEndIndex
                rangeEndIndex = t
            }
        }
    }

    function resetRange() {
        rangeStartIndex = 0
        rangeEndIndex = -1
    }

    function rangeInfoText() {
        var total = maxPointCountForCurrentMode()
        if (total <= 0)
            return "Диапазон: нет данных"
        var endValue = rangeEndIndex >= 0 ? rangeEndIndex : (total - 1)
        return "Диапазон: " + rangeStartIndex + "..." + endValue + " из " + total
    }

    function markGraphUpdating() {
        graphUpdateToken += 1
    }

    function parseIntOrFallback(textValue, fallbackValue) {
        var parsed = parseInt(String(textValue).trim())
        if (isNaN(parsed))
            return fallbackValue
        return parsed
    }

    function applyRangeStartInput() {
        var total = maxPointCountForCurrentMode()
        var startValue = parseIntOrFallback(rangeStartInputText, 0)
        if (total > 0)
            startValue = Math.max(0, Math.min(total - 1, startValue))
        else
            startValue = 0
        rangeStartIndex = startValue
        clampRangeToData()
        syncAdvancedInputTexts()
        markGraphUpdating()
    }

    function applyRangeEndInput() {
        var total = maxPointCountForCurrentMode()
        var endValue = parseIntOrFallback(rangeEndInputText, -1)
        if (endValue < 0) {
            rangeEndIndex = -1
        } else if (total > 0) {
            rangeEndIndex = Math.max(0, Math.min(total - 1, endValue))
        } else {
            rangeEndIndex = -1
        }
        clampRangeToData()
        syncAdvancedInputTexts()
        markGraphUpdating()
    }

    function applyAverageWindowInput() {
        var value = parseIntOrFallback(averageWindowInputText, averageWindow)
        value = Math.max(1, Math.min(101, value))
        averageWindow = value
        syncAdvancedInputTexts()
        markGraphUpdating()
    }

    function applyXGridTicksInput() {
        var parsed = Number(String(xGridTicksInputText).trim())
        var value = isNaN(parsed) ? xGridTicks : Math.round(parsed)
        value = Math.max(2, Math.min(1000, value))
        xGridTicks = value
        syncAdvancedInputTexts()
        markGraphUpdating()
    }

    function applyYGridTicksInput() {
        var parsed = Number(String(yGridTicksInputText).trim())
        var value = isNaN(parsed) ? yGridTicks : Math.round(parsed)
        value = Math.max(2, Math.min(1000, value))
        yGridTicks = value
        syncAdvancedInputTexts()
        markGraphUpdating()
    }

    function syncAdvancedInputTexts() {
        rangeStartInputText = String(rangeStartIndex)
        rangeEndInputText = String(rangeEndIndex)
        averageWindowInputText = String(averageWindow)
        xGridTicksInputText = String(xGridTicks)
        yGridTicksInputText = String(yGridTicks)
    }

    header: Rectangle {
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#1e3a8a" }
            GradientStop { position: 1.0; color: "#1d4ed8" }
        }
        implicitHeight: 62
        RowLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10

            Label {
                text: "Просмотр графиков CAN из CSV"
                color: "#f8fbff"
                font.pixelSize: 20
                font.bold: true
                font.family: "Segoe UI"
                Layout.fillWidth: true
            }

            SoftButton {
                text: "Загрузить CSV"
                implicitWidth: 140
                tone: "#f8fafc"
                toneBorder: "#dbeafe"
                textColor: "#1e3a8a"
                onClicked: csvDialog.open()
            }

            SoftGhostButton {
                text: "Очистить"
                implicitHeight: 36
                implicitWidth: 110
                tone: "#eff6ff"
                toneBorder: "#bfdbfe"
                textColor: "#1e40af"
                onClicked: backend.clearData()
            }
        }
    }

    FileDialog {
        id: csvDialog
        title: "Выберите CSV/XLSX файлы Коллектора"
        fileMode: FileDialog.OpenFiles
        nameFilters: ["Табличные файлы (*.csv *.xlsx)", "CSV файлы (*.csv)", "XLSX файлы (*.xlsx)", "Все файлы (*)"]
        onAccepted: backend.loadCsvFiles(_dialogPaths())
    }

    ColorDialog {
        id: nodeColorDialog
        title: "Выберите цвет узла"
        property string targetNode: ""
        onAccepted: {
            if (targetNode !== "") {
                root.markGraphUpdating()
                backend.setNodeColor(targetNode, String(selectedColor))
            }
        }
    }

    footer: Rectangle {
        implicitHeight: 40
        color: "#f7fbff"
        border.color: "#d8e4f2"
        border.width: 1

        RowLayout {
            anchors.fill: parent
            anchors.margins: 8
            spacing: 10

            Rectangle {
                implicitWidth: 10
                implicitHeight: 10
                radius: 5
                color: backend.busy ? "#f59e0b" : "#22c55e"
            }

            Label {
                text: backend.busy ? "Загрузка данных..." : "Готово"
                color: root.textMainColor
                font.pixelSize: 12
                font.family: "Segoe UI"
            }

            Label {
                text: root.graphUpdateInProgress ? "Обновление графика..." : "График готов"
                color: root.graphUpdateInProgress ? "#2563eb" : root.textSoftColor
                font.pixelSize: 12
                font.family: "Segoe UI"
            }

            Label {
                text: root.rangeInfoText()
                color: root.textSoftColor
                font.pixelSize: 12
                font.family: "Segoe UI"
            }

            Item { Layout.fillWidth: true }

            Label {
                text: backend.statusText
                color: root.textMainColor
                font.pixelSize: 12
                font.family: "Segoe UI"
                elide: Text.ElideRight
                Layout.preferredWidth: 520
                horizontalAlignment: Text.AlignRight
            }

            Rectangle {
                visible: !backend.xlsxSupported
                radius: 8
                color: "#fff7ed"
                border.color: "#fdba74"
                implicitHeight: 24
                implicitWidth: xlsxFooterWarn.implicitWidth + 14
                Label {
                    id: xlsxFooterWarn
                    anchors.centerIn: parent
                    text: "XLSX недоступен: установите openpyxl"
                    color: "#9a3412"
                    font.pixelSize: 11
                    font.family: "Segoe UI"
                }
            }
        }
    }

    RowLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 10

        Rectangle {
            Layout.preferredWidth: 360
            Layout.fillHeight: true
            radius: 10
            color: root.cardBg
            border.color: root.cardBorder

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 10

                Label {
                    text: "Управление"
                    font.bold: true
                    font.pixelSize: 16
                    font.family: "Segoe UI"
                    color: root.textMainColor
                }

                GridLayout {
                    columns: 2
                    rowSpacing: 8
                    columnSpacing: 8
                    Layout.fillWidth: true

                    Label { text: "Режим"; color: root.textSoftColor; font.family: "Segoe UI" }
                    SoftComboBox {
                        model: ["Выбранный узел", "Все узлы"]
                        currentIndex: backend.viewMode
                        onActivated: {
                            backend.setViewMode(currentIndex)
                            root.resetRange()
                            root.clampRangeToData()
                            root.syncAdvancedInputTexts()
                            root.markGraphUpdating()
                        }
                        Layout.fillWidth: true
                    }

                    Label { text: "Узел"; color: root.textSoftColor; font.family: "Segoe UI" }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        SoftComboBox {
                            Layout.fillWidth: true
                            model: root.nodeSelectorModel()
                            currentIndex: backend.selectedNodeIndex >= 0 ? (backend.selectedNodeIndex + 1) : 0
                            enabled: backend.viewMode === 0
                            onActivated: {
                                if (currentIndex === 0)
                                    backend.setSelectedNodeIndex(-1)
                                else
                                    backend.setSelectedNodeIndex(currentIndex - 1)
                                root.resetRange()
                                root.clampRangeToData()
                                root.syncAdvancedInputTexts()
                                root.markGraphUpdating()
                            }
                        }
                    }
                }

                SoftCheckBox {
                    text: "Показывать метки времени"
                    checked: backend.showLabels
                    onToggled: {
                        root.markGraphUpdating()
                        backend.setShowLabels(checked)
                    }
                }

                SoftCheckBox {
                    text: "Плавное усреднение"
                    checked: root.averageEnabled
                    onToggled: {
                        root.markGraphUpdating()
                        root.averageEnabled = checked
                        if (checked) {
                            // Цель блока в включении режима максимального сглаживания.
                            // Он оставляет только плавную кривую без маркеров.
                            root.averageWindow = 101
                            root.drawLineEnabled = true
                            root.drawMarkersEnabled = false
                            backend.setShowLabels(false)
                        }
                    }
                }

                SoftGhostButton {
                    text: showAdvancedControls ? "Свернуть расширенные" : "Расширенные настройки"
                    onClicked: showAdvancedControls = !showAdvancedControls
                }

                GridLayout {
                    columns: 3
                    rowSpacing: 8
                    columnSpacing: 8
                    visible: showAdvancedControls
                    Layout.fillWidth: true

                    AdvancedParamLabel { text: "Начало диапазона" }
                    SoftTextField {
                        text: root.rangeStartInputText
                        onTextChanged: root.rangeStartInputText = text
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                    }
                    SoftGhostButton {
                        text: "Применить"
                        implicitWidth: 110
                        Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
                        onClicked: root.applyRangeStartInput()
                    }

                    AdvancedParamLabel { text: "Конец диапазона" }
                    SoftTextField {
                        text: root.rangeEndInputText
                        onTextChanged: root.rangeEndInputText = text
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                    }
                    SoftGhostButton {
                        text: "Применить"
                        implicitWidth: 110
                        Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
                        onClicked: root.applyRangeEndInput()
                    }
                }

                GridLayout {
                    columns: 3
                    rowSpacing: 8
                    columnSpacing: 8
                    visible: showAdvancedControls
                    Layout.fillWidth: true

                    AdvancedParamLabel { text: "Окно усреднения" }
                    SoftTextField {
                        text: root.averageWindowInputText
                        onTextChanged: root.averageWindowInputText = text
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                    }
                    SoftGhostButton {
                        text: "Применить"
                        implicitWidth: 110
                        Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
                        onClicked: root.applyAverageWindowInput()
                    }

                    AdvancedParamLabel { text: "Сетка X (цель)" }
                    SoftTextField {
                        text: root.xGridTicksInputText
                        onTextChanged: root.xGridTicksInputText = text
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                    }
                    SoftGhostButton {
                        text: "Применить"
                        implicitWidth: 110
                        Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
                        onClicked: root.applyXGridTicksInput()
                    }

                    AdvancedParamLabel { text: "Сетка Y (цель)" }
                    SoftTextField {
                        text: root.yGridTicksInputText
                        onTextChanged: root.yGridTicksInputText = text
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                    }
                    SoftGhostButton {
                        text: "Применить"
                        implicitWidth: 110
                        Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
                        onClicked: root.applyYGridTicksInput()
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    SoftCheckBox {
                        text: "Линия"
                        checked: root.drawLineEnabled
                        onToggled: {
                            root.markGraphUpdating()
                            root.drawLineEnabled = checked
                        }
                    }
                    SoftCheckBox {
                        text: "Точки"
                        checked: root.drawMarkersEnabled
                        onToggled: {
                            root.markGraphUpdating()
                            root.drawMarkersEnabled = checked
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    SoftGhostButton {
                        text: "Сбросить период"
                        onClicked: {
                            root.markGraphUpdating()
                            root.resetRange()
                        }
                    }
                    SoftGhostButton {
                        text: "Сбросить масштаб"
                        onClicked: {
                            root.markGraphUpdating()
                            trendCanvas.resetView()
                        }
                    }
                }

                Label {
                    text: "Серии"
                    font.bold: true
                    font.pixelSize: 15
                    font.family: "Segoe UI"
                    color: root.textMainColor
                    visible: backend.viewMode === 1
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    visible: backend.viewMode === 1

                    SoftGhostButton {
                        text: "Отключить все узлы"
                        implicitWidth: 180
                        onClicked: {
                            root.markGraphUpdating()
                            backend.setSelectedNodeIndex(-1)
                            backend.setAllNodesVisible(false)
                        }
                    }
                }

                ScrollView {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 220
                    clip: true
                    visible: backend.viewMode === 1

                    ColumnLayout {
                        width: parent.width
                        spacing: 6

                        Repeater {
                            model: backend.nodeVisibilityRows
                            delegate: Rectangle {
                                Layout.fillWidth: true
                                radius: 8
                                color: "#f8fafc"
                                border.color: "#e2e8f0"
                                implicitHeight: line.implicitHeight + 10

                                RowLayout {
                                    id: line
                                    anchors.fill: parent
                                    anchors.margins: 6
                                    spacing: 8

                                    Rectangle {
                                        width: 12
                                        height: 12
                                        radius: 6
                                        color: modelData.color
                                        border.color: "#475569"

                                        MouseArea {
                                            id: colorPickerMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                nodeColorDialog.targetNode = String(modelData.node)
                                                nodeColorDialog.selectedColor = modelData.color
                                                nodeColorDialog.open()
                                            }
                                        }

                                        ToolTip.visible: colorPickerMouse.containsMouse
                                        ToolTip.delay: 120
                                        ToolTip.timeout: 3000
                                        ToolTip.text: "Нажмите, чтобы выбрать цвет узла."
                                    }

                                    CheckBox {
                                        id: rowVisibleCheckbox
                                        spacing: 0
                                        leftPadding: 0
                                        rightPadding: 0
                                        topPadding: 0
                                        bottomPadding: 0
                                        implicitWidth: 18
                                        implicitHeight: 18
                                        checked: modelData.visible
                                        onToggled: {
                                            root.markGraphUpdating()
                                            backend.setNodeVisible(modelData.node, checked)
                                        }
                                        indicator: Rectangle {
                                            implicitWidth: 16
                                            implicitHeight: 16
                                            radius: 5
                                            color: rowVisibleCheckbox.checked ? root.accentColor : "#ffffff"
                                            border.color: rowVisibleCheckbox.checked ? "#2d6fdd" : "#c5d2e3"
                                            border.width: 1
                                            anchors.centerIn: parent
                                        }
                                        contentItem: Item { implicitWidth: 0; implicitHeight: 0 }
                                    }

                                    Label {
                                        text: modelData.node
                                        font.bold: true
                                        font.family: "Segoe UI"
                                        color: root.textMainColor
                                    }

                                    Item { Layout.fillWidth: true }
                                }
                            }
                        }
                    }
                }

                Label {
                    text: "Математика по узлам"
                    font.bold: true
                    font.pixelSize: 15
                    font.family: "Segoe UI"
                    color: root.textMainColor
                    visible: backend.nodeMetricsRows.length > 0
                }

                ScrollView {
                    Layout.fillWidth: true
                    Layout.fillHeight: backend.nodeMetricsRows.length > 0
                    clip: true
                    visible: backend.nodeMetricsRows.length > 0

                    ColumnLayout {
                        width: parent.width
                        spacing: 8

                        Repeater {
                            model: backend.nodeMetricsRows
                            delegate: Rectangle {
                                id: metricCard
                                Layout.fillWidth: true
                                radius: 10
                                color: "#ffffff"
                                border.color: "#dbe5f1"
                                property bool expanded: false
                                implicitHeight: metricCardLayout.implicitHeight + 16

                                ColumnLayout {
                                    id: metricCardLayout
                                    anchors.fill: parent
                                    anchors.margins: 8
                                    spacing: 6

                                    RowLayout {
                                        id: headerRow
                                        Layout.fillWidth: true
                                        spacing: 8

                                        Label {
                                            text: modelData.node
                                            font.bold: true
                                            color: root.textMainColor
                                            font.family: "Segoe UI"
                                        }

                                        Label {
                                            text: "точек: " + modelData.count
                                            color: root.textSoftColor
                                            font.family: "Segoe UI"
                                        }

                                        Item { Layout.fillWidth: true }

                                        SoftGhostButton {
                                            text: metricCard.expanded ? "Скрыть" : "Показать"
                                            implicitWidth: 88
                                            implicitHeight: 28
                                            onClicked: metricCard.expanded = !metricCard.expanded
                                        }
                                    }

                                    ColumnLayout {
                                        id: metricsBody
                                        visible: metricCard.expanded
                                        Layout.fillWidth: true
                                        spacing: 8

                                        Rectangle {
                                            Layout.fillWidth: true
                                            radius: 8
                                            color: "#f8fafc"
                                            border.color: "#e2e8f0"
                                            implicitHeight: extremaColumn.implicitHeight + 14

                                            ColumnLayout {
                                                id: extremaColumn
                                                anchors.fill: parent
                                                anchors.margins: 7
                                                spacing: 4
                                                Label {
                                                    text: "Экстремумы"
                                                    color: "#334155"
                                                    font.pixelSize: 12
                                                    font.bold: true
                                                    font.family: "Segoe UI"
                                                }
                                                Label {
                                                    id: extremaText
                                                    text: modelData.minPointText + "\n" + modelData.maxPointText
                                                    color: root.textMainColor
                                                    font.pixelSize: 12
                                                    font.family: "Segoe UI"
                                                    wrapMode: Text.WordWrap
                                                    Layout.fillWidth: true
                                                }
                                            }
                                        }

                                        Rectangle {
                                            Layout.fillWidth: true
                                            radius: 8
                                            color: "#ffffff"
                                            border.color: "#e2e8f0"
                                            implicitHeight: metricsGrid.implicitHeight + 14

                                            GridLayout {
                                                id: metricsGrid
                                                anchors.fill: parent
                                                anchors.margins: 7
                                                columns: 2
                                                rowSpacing: 6
                                                columnSpacing: 10

                                                Label { text: "Параметр"; color: "#334155"; font.bold: true; font.family: "Segoe UI" }
                                                Label { text: "Значение"; color: "#334155"; font.bold: true; font.family: "Segoe UI" }

                                                Label { text: "Количество точек"; color: root.textSoftColor; font.family: "Segoe UI" }
                                                RowLayout {
                                                    Layout.fillWidth: true
                                                    spacing: 6
                                                    Label { text: String(modelData.count); color: root.textMainColor; font.family: "Segoe UI" }
                                                    MetricInfoBadge { tipText: "Сколько измерений участвует в анализе узла." }
                                                    Item { Layout.fillWidth: true }
                                                }

                                                Label { text: "T диапазон"; color: root.textSoftColor; font.family: "Segoe UI" }
                                                RowLayout {
                                                    Layout.fillWidth: true
                                                    spacing: 6
                                                    Label { text: Number(modelData.tempRange).toFixed(2) + " °C"; color: root.textMainColor; font.family: "Segoe UI" }
                                                    MetricInfoBadge { tipText: "Разница между Tmin и Tmax." }
                                                    Item { Layout.fillWidth: true }
                                                }

                                                Label { text: "Диапазон топлива"; color: root.textSoftColor; font.family: "Segoe UI" }
                                                RowLayout {
                                                    Layout.fillWidth: true
                                                    spacing: 6
                                                    Label { text: Number(modelData.fuelRange).toFixed(2) + " %"; color: root.textMainColor; font.family: "Segoe UI" }
                                                    MetricInfoBadge { tipText: "Размах уровня топлива по графику." }
                                                    Item { Layout.fillWidth: true }
                                                }

                                                Label { text: "Дрейф по температуре"; color: root.textSoftColor; font.family: "Segoe UI" }
                                                RowLayout {
                                                    Layout.fillWidth: true
                                                    spacing: 6
                                                    Label { text: Number(modelData.driftFuel).toFixed(2) + " %"; color: root.textMainColor; font.family: "Segoe UI" }
                                                    MetricInfoBadge { tipText: "Изменение уровня топлива от Tmin до Tmax." }
                                                    Item { Layout.fillWidth: true }
                                                }

                                                Label { text: "Наклон дрейфа"; color: root.textSoftColor; font.family: "Segoe UI" }
                                                RowLayout {
                                                    Layout.fillWidth: true
                                                    spacing: 6
                                                    Label { text: Number(modelData.driftSlope).toFixed(3) + " %/°C"; color: root.textMainColor; font.family: "Segoe UI" }
                                                    MetricInfoBadge { tipText: "Изменение уровня на 1°C." }
                                                    Item { Layout.fillWidth: true }
                                                }

                                                Label { text: "Средний уровень"; color: root.textSoftColor; font.family: "Segoe UI" }
                                                RowLayout {
                                                    Layout.fillWidth: true
                                                    spacing: 6
                                                    Label { text: Number(modelData.fuelMean).toFixed(2) + " %"; color: root.textMainColor; font.family: "Segoe UI" }
                                                    MetricInfoBadge { tipText: "Среднее значение уровня топлива." }
                                                    Item { Layout.fillWidth: true }
                                                }

                                                Label { text: "Станд. отклонение"; color: root.textSoftColor; font.family: "Segoe UI" }
                                                RowLayout {
                                                    Layout.fillWidth: true
                                                    spacing: 6
                                                    Label { text: Number(modelData.fuelStd).toFixed(2) + " %"; color: root.textMainColor; font.family: "Segoe UI" }
                                                    MetricInfoBadge { tipText: "Разброс уровня топлива относительно среднего." }
                                                    Item { Layout.fillWidth: true }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                Item { Layout.fillHeight: true; visible: backend.nodeMetricsRows.length <= 0 }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: 10
            color: root.cardBg
            border.color: root.cardBorder

            TrendCanvas {
                id: trendCanvas
                anchors.fill: parent
                anchors.margins: 10
                panelBg: "#ffffff"
                panelBorder: "#d6e2ef"
                overlayMode: backend.viewMode === 1
                points: {
                    var series = backend.visibleSeries
                    if (!series || series.length === 0)
                        return []
                    return series[0].points
                }
                series: backend.visibleSeries
                showPointLabels: backend.showLabels
                swapAxes: backend.swapAxes
                smoothSeriesEnabled: false
                averageEnabled: root.averageEnabled
                averageWindow: root.averageWindow
                drawLineEnabled: root.drawLineEnabled
                drawMarkersEnabled: root.drawMarkersEnabled
                maxRenderPoints: 5000
                maxMarkerPoints: 1800
                xMajorTicks: root.xGridTicks
                yMajorTicks: root.yGridTicks
                rangeStart: root.rangeStartIndex
                rangeEnd: root.rangeEndIndex
                updateToken: root.graphUpdateToken
            }

            Rectangle {
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.topMargin: 14
                anchors.rightMargin: 14
                radius: 12
                color: "#ffffff"
                border.color: "#bfdbfe"
                border.width: 1
                visible: root.graphUpdateInProgress
                implicitHeight: 58
                implicitWidth: Math.max(300, updateRow.implicitWidth + 24)
                z: 20

                RowLayout {
                    id: updateRow
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 12

                    Item {
                        implicitWidth: 32
                        implicitHeight: 32
                        BusyIndicator {
                            anchors.centerIn: parent
                            width: 30
                            height: 30
                            running: root.graphUpdateInProgress
                            visible: root.graphUpdateInProgress
                        }
                    }

                    Label {
                        text: "Обновление графика..."
                        color: "#1d4ed8"
                        font.pixelSize: 14
                        font.bold: true
                        font.family: "Segoe UI"
                    }
                }
            }

            BusyIndicator {
                anchors.centerIn: parent
                running: backend.busy
                visible: backend.busy
                width: 60
                height: 60
            }
        }
    }

    Connections {
        target: backend
        function onDataChanged() {
            root.resetRange()
            root.markGraphUpdating()
            root.clampRangeToData()
            root.syncAdvancedInputTexts()
        }
    }

    Component.onCompleted: root.syncAdvancedInputTexts()
}
