import QtQuick
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root
    pluginId: "opencodeUsage"

    property bool showTokens: pluginData.showTokens !== false
    property bool showSessions: pluginData.showSessions !== false
    property int costAlertUsd: pluginData.costAlertUsd || 0
    property string pluginDir: {
        var url = Qt.resolvedUrl(".")
        var path = url.toString()
        if (path.indexOf("file://") === 0) path = path.substring(7)
        return path
    }

    property var usageData: null

    function loadUsageData() {
        try {
            var cached = pluginService.loadPluginState("opencodeUsage", "lastData", null)
            if (cached) root.usageData = cached
        } catch (e) {}
    }

    Component.onCompleted: loadUsageData()

    Connections {
        target: root
        function onPluginDataChanged() {
            if (root.pluginData && Object.keys(root.pluginData).length > 0)
                Qt.callLater(root.loadUsageData)
        }
    }

    Connections {
        target: root.pluginService
        enabled: root.pluginService !== null
        function onPluginStateChanged(changedPluginId) {
            if (changedPluginId === "opencodeUsage")
                root.loadUsageData()
        }
    }

    function windowData(name) {
        if (!usageData || usageData.status !== "ok" || !usageData.windows) return null
        return usageData.windows[name] || null
    }

    function recentUsage() {
        if (!usageData || usageData.status !== "ok" || !usageData.recent_usage) return []
        return usageData.recent_usage
    }

    function providerList() {
        if (!usageData || usageData.status !== "ok" || !usageData.providers) return []
        return usageData.providers
    }

    function errorMessage() {
        if (!usageData) return I18n.trFor("opencodeUsage", "Loading...")
        if (usageData.status === "error") {
            var reasons = ({
                db_missing: I18n.trFor("opencodeUsage", "OpenCode database not found."),
                no_sqlite: I18n.trFor("opencodeUsage", "sqlite3 is not installed."),
                no_jq: I18n.trFor("opencodeUsage", "jq is not installed."),
                db_error: I18n.trFor("opencodeUsage", "Could not read the OpenCode database.")
            })
            return reasons[usageData.reason] || usageData.error || I18n.trFor("opencodeUsage", "Could not read OpenCode usage.")
        }
        return null
    }

    function alertTriggered() {
        if (costAlertUsd <= 0) return false
        var today = windowData("today")
        return today !== null && today.cost >= costAlertUsd
    }

    function fmtMoney(value) {
        var amount = parseFloat(value)
        if (!isFinite(amount)) return "--"
        return "$" + amount.toFixed(2)
    }

    function fmtTokens(value) {
        var n = parseInt(value, 10)
        if (!isFinite(n) || n <= 0) return "0"
        if (n >= 1000000000) return (n / 1000000000).toFixed(1) + "B"
        if (n >= 1000000) return (n / 1000000).toFixed(1) + "M"
        if (n >= 1000) return (n / 1000).toFixed(1) + "K"
        return String(n)
    }

    function tokensTotal(win) {
        if (!win) return 0
        if (win.tokens_total !== undefined) return Number(win.tokens_total) || 0
        return (Number(win.tokens_input) || 0) + (Number(win.tokens_output) || 0) +
               (Number(win.tokens_reasoning) || 0) + (Number(win.tokens_cache_read) || 0) +
               (Number(win.tokens_cache_write) || 0)
    }

    function allTimeTokens() {
        if (!usageData) return 0
        if (usageData.tokens_all_time !== undefined) return Number(usageData.tokens_all_time) || 0
        return tokensTotal(windowData("month"))
    }

    function tokenShare(name) {
        var total = allTimeTokens()
        if (total <= 0) return 0
        return Math.round(tokensTotal(windowData(name)) / total * 100)
    }

    function shareLine() {
        return I18n.trFor("opencodeUsage", "Today") + " " + tokenShare("today") + "%  ·  " +
               I18n.trFor("opencodeUsage", "7D") + " " + tokenShare("week") + "%  ·  " +
               I18n.trFor("opencodeUsage", "30D") + " " + tokenShare("month") + "%"
    }

    // --- OpenCode Go subscription limits (from the API) ---

    function limitsAvailable() {
        return usageData !== null && usageData.limits !== undefined && usageData.limits.available === true
    }

    function limitFor(key) {
        if (!limitsAvailable()) return null
        return usageData.limits[key] || null
    }

    function limitPercent(key) {
        var data = limitFor(key)
        return data ? (Number(data.percent) || 0) : 0
    }

    function limitReset(key) {
        var data = limitFor(key)
        if (!data || !data.resetsAt) return ""
        var target = Date.parse(data.resetsAt)
        if (isNaN(target)) return ""
        var seconds = Math.max(0, Math.round((target - Date.now()) / 1000))
        var days = Math.floor(seconds / 86400)
        var hours = Math.floor((seconds % 86400) / 3600)
        var minutes = Math.floor((seconds % 3600) / 60)
        if (days > 0) return days + "d " + hours + "h"
        if (hours > 0) return hours + "h " + minutes + "m"
        return minutes + "m"
    }

    function providerName(name) {
        if (name === "opencode-go") return "OpenCode Go"
        if (name === "opencode") return "OpenCode"
        return name || I18n.trFor("opencodeUsage", "Local data")
    }

    function modelCount() {
        if (!usageData || usageData.models === undefined) return 0
        return Number(usageData.models) || 0
    }

    function summaryLine() {
        var count = providerList().length
        var providerText = count === 1
            ? I18n.trFor("opencodeUsage", "%1 provider").arg(count)
            : I18n.trFor("opencodeUsage", "%1 providers").arg(count)
        return providerText + "  ·  " + fmtTokens(tokensTotal(windowData("week"))) + " " +
               I18n.trFor("opencodeUsage", "tokens this week")
    }

    function tokenLines(win) {
        if (!showTokens || !win) return []
        return [
            I18n.trFor("opencodeUsage", "Input tokens: %1").arg(fmtTokens(win.tokens_input)),
            I18n.trFor("opencodeUsage", "Output tokens: %1").arg(fmtTokens(win.tokens_output)),
            I18n.trFor("opencodeUsage", "Reasoning tokens: %1").arg(fmtTokens(win.tokens_reasoning)),
            I18n.trFor("opencodeUsage", "Cache read tokens: %1").arg(fmtTokens(win.tokens_cache_read)),
            I18n.trFor("opencodeUsage", "Cache write tokens: %1").arg(fmtTokens(win.tokens_cache_write))
        ]
    }

    function pillText() {
        var today = windowData("today")
        return today ? fmtTokens(tokensTotal(today)) : "-"
    }

    readonly property real barTextSize: Theme.barTextSize(barThickness, barConfig?.fontScale, barConfig?.maximizeWidgetText)

    horizontalBarPill: Component {
        StyledRect {
            implicitWidth: hRow.implicitWidth + Theme.spacingXS * 2
            height: parent.widgetThickness
            radius: Theme.cornerRadius
            color: Theme.surfaceContainerHigh

            Row {
                id: hRow
                anchors.centerIn: parent
                spacing: Theme.spacingXS

                Image {
                    source: root.pluginDir + "assets/opencode-logo.svg"
                    sourceSize.width: Theme.iconSizeSmall
                    sourceSize.height: Theme.iconSizeSmall
                    width: Theme.iconSizeSmall
                    height: Theme.iconSizeSmall
                    fillMode: Image.PreserveAspectFit
                    anchors.verticalCenter: parent.verticalCenter
                }

                StyledText {
                    visible: !root.usageData
                    text: "-"
                    color: Theme.surfaceTextMedium
                    font.pixelSize: root.barTextSize
                    anchors.verticalCenter: parent.verticalCenter
                }

                StyledText {
                    visible: !root.usageData || root.usageData.status === "ok"
                    text: root.pillText()
                    color: root.alertTriggered() ? Theme.error : Theme.surfaceText
                    font.pixelSize: root.barTextSize
                    anchors.verticalCenter: parent.verticalCenter
                }

                StyledText {
                    visible: root.usageData && root.usageData.status === "error"
                    text: "!"
                    color: Theme.warning
                    font.pixelSize: root.barTextSize
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }
    }

    verticalBarPill: Component {
        StyledRect {
            width: parent.widgetThickness
            implicitHeight: vCol.implicitHeight + Theme.spacingXS * 2
            radius: Theme.cornerRadius
            color: Theme.surfaceContainerHigh

            Column {
                id: vCol
                anchors.centerIn: parent
                spacing: Theme.spacingXXS

                Image {
                    source: root.pluginDir + "assets/opencode-logo.svg"
                    sourceSize.width: Theme.iconSizeSmall
                    sourceSize.height: Theme.iconSizeSmall
                    width: Theme.iconSizeSmall
                    height: Theme.iconSizeSmall
                    fillMode: Image.PreserveAspectFit
                    anchors.horizontalCenter: parent.horizontalCenter
                }

                StyledText {
                    visible: root.usageData && root.usageData.status === "error"
                    text: "!"
                    color: Theme.warning
                    font.pixelSize: Theme.fontSizeSmall
                    anchors.horizontalCenter: parent.horizontalCenter
                }

                StyledText {
                    visible: !root.usageData || root.usageData.status === "ok"
                    text: root.pillText()
                    color: root.alertTriggered() ? Theme.error : Theme.surfaceText
                    font.pixelSize: Theme.fontSizeSmall
                    anchors.horizontalCenter: parent.horizontalCenter
                }
            }
        }
    }

    // --- Popout ---

    popoutWidth: 420
    popoutHeight: 0
    popoutContent: Component {
        PopoutComponent {
            id: popout
            headerText: I18n.trFor("opencodeUsage", "OpenCode Usage")
            showCloseButton: true
            closePopout: function () { popout.visible = false }

            Column {
                width: parent.width - Theme.spacingM * 2
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Theme.spacingS

                StyledText {
                    visible: root.errorMessage() !== null
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: root.errorMessage() || ""
                    color: root.usageData && root.usageData.status === "error"
                        ? Theme.warning : Theme.surfaceVariantText
                    font.pixelSize: Theme.fontSizeSmall
                }

                Row {
                    width: parent.width
                    spacing: Theme.spacingXS

                    StyledText {
                        width: parent.width - updatedText.implicitWidth - Theme.spacingXS
                        text: root.summaryLine()
                        color: Theme.surfaceVariantText
                        font.pixelSize: Theme.fontSizeSmall
                        font.weight: Font.Bold
                        elide: Text.ElideRight
                    }

                    StyledText {
                        id: updatedText
                        text: root.usageData && root.usageData.captured_at
                            ? Qt.formatDateTime(new Date(root.usageData.captured_at * 1000), "HH:mm:ss") : "--:--:--"
                        color: Theme.surfaceTextMedium
                        font.pixelSize: Theme.fontSizeSmall
                    }
                }

                StyledText {
                    text: root.limitsAvailable()
                        ? I18n.trFor("opencodeUsage", "OpenCode Go") + " · " + root.limitPercent("monthly") + "% " + I18n.trFor("opencodeUsage", "monthly")
                        : I18n.trFor("opencodeUsage", "OpenCode Go: No API key")
                    color: root.limitsAvailable() ? Theme.primary : Theme.error
                    font.pixelSize: Theme.fontSizeSmall
                    font.weight: Font.Bold
                }

                Row {
                    width: parent.width
                    spacing: Theme.spacingS

                    Repeater {
                        model: [
                            { value: root.fmtTokens(root.tokensTotal(root.windowData("week"))), label: I18n.trFor("opencodeUsage", "TOKENS · 7D") },
                            { value: root.fmtMoney(root.windowData("week") ? root.windowData("week").cost : 0), label: I18n.trFor("opencodeUsage", "COST · 7D") },
                            { value: String(root.modelCount()), label: I18n.trFor("opencodeUsage", "MODELS") }
                        ]

                        delegate: StyledRect {
                            width: (parent.width - Theme.spacingS * 2) / 3
                            height: 58
                            radius: Theme.cornerRadius
                            color: Theme.surfaceContainerHigh

                            Column {
                                anchors.fill: parent
                                anchors.margins: Theme.spacingS
                                spacing: Theme.spacingXXS

                                StyledText {
                                    text: modelData.value
                                    color: Theme.surfaceText
                                    font.pixelSize: Theme.fontSizeLarge
                                    font.weight: Font.Bold
                                }

                                StyledText {
                                    text: modelData.label
                                    color: Theme.surfaceVariantText
                                    font.pixelSize: Theme.fontSizeSmall
                                }
                            }
                        }
                    }
                }

                StyledText {
                    visible: root.allTimeTokens() > 0
                    width: parent.width
                    text: root.shareLine()
                    color: Theme.primary
                    font.pixelSize: Theme.fontSizeSmall
                    font.weight: Font.Bold
                    horizontalAlignment: Text.AlignHCenter
                }

                StyledText {
                    text: I18n.trFor("opencodeUsage", "Providers")
                    color: Theme.surfaceVariantText
                    font.pixelSize: Theme.fontSizeSmall
                    font.weight: Font.Bold
                }

                Column {
                    width: parent.width
                    spacing: Theme.spacingXS

                    Repeater {
                        model: root.providerList()
                        delegate: Column {
                            width: parent.width
                            spacing: Theme.spacingXXS

                            Row {
                                width: parent.width
                                spacing: Theme.spacingXS

                                StyledText {
                                    text: "›"
                                    color: Theme.primary
                                    font.pixelSize: Theme.fontSizeLarge
                                    font.weight: Font.Bold
                                }

                                Column {
                                    width: parent.width - providerBadge.width - Theme.spacingS * 2
                                    spacing: Theme.spacingXXS

                                    StyledText {
                                        text: root.providerName(modelData.name)
                                        color: Theme.surfaceText
                                        font.pixelSize: Theme.fontSizeMedium
                                        font.weight: Font.Bold
                                    }

                                    StyledText {
                                        text: root.fmtTokens(modelData.tokens) + "  ·  " + String(modelData.models) + " " + I18n.trFor("opencodeUsage", "models")
                                        color: Theme.surfaceVariantText
                                        font.pixelSize: Theme.fontSizeSmall
                                    }
                                }

                                StyledRect {
                                    id: providerBadge
                                    width: badgeText.implicitWidth + Theme.spacingS * 2
                                    height: 22
                                    radius: height / 2
                                    color: Theme.surfaceContainerHighest

                                    StyledText {
                                        id: badgeText
                                        anchors.centerIn: parent
                                        text: root.fmtMoney(root.windowData("week") ? root.windowData("week").cost : 0) + " / 7D"
                                        color: Theme.surfaceText
                                        font.pixelSize: Theme.fontSizeSmall
                                    }
                                }
                            }

                            StyledText {
                                text: root.fmtTokens(modelData.tokens) + "  ·  7D  ·  " +
                                      root.fmtTokens(root.tokensTotal(root.windowData("month"))) + "  ·  30D  ·  " +
                                      I18n.trFor("opencodeUsage", "local data")
                                color: Theme.surfaceVariantText
                                font.pixelSize: Theme.fontSizeSmall
                            }

                            Rectangle {
                                width: parent.width
                                height: 4
                                radius: 2
                                color: Theme.outlineVariant

                                Rectangle {
                                    width: parent.width * Math.min(1, Math.max(0, root.tokensTotal(root.windowData("week")) > 0
                                        ? modelData.tokens / root.tokensTotal(root.windowData("week")) : 0))
                                    height: parent.height
                                    radius: parent.radius
                                    color: Theme.primary
                                }
                            }
                        }
                    }
                }

                StyledText {
                    text: I18n.trFor("opencodeUsage", "Recent usage") + "  ·  " + root.fmtTokens(root.tokensTotal(root.windowData("week"))) + " " + I18n.trFor("opencodeUsage", "tokens")
                    color: Theme.surfaceVariantText
                    font.pixelSize: Theme.fontSizeSmall
                    font.weight: Font.Bold
                }

                Item {
                    id: chartArea
                    width: parent.width
                    height: 112
                    property int hoveredIndex: -1
                    onHoveredIndexChanged: usageChart.requestPaint()

                    Canvas {
                        id: usageChart
                        anchors.fill: parent
                        property var chartData: root.recentUsage()

                        onChartDataChanged: requestPaint()
                        onWidthChanged: requestPaint()
                        onPaint: {
                            var ctx = getContext("2d")
                            ctx.clearRect(0, 0, width, height)
                            var data = chartData || []
                            if (data.length === 0) return

                            var maxValue = 0
                            for (var i = 0; i < data.length; i++)
                                maxValue = Math.max(maxValue, Number(data[i].tokens) || 0)
                            if (maxValue <= 0) maxValue = 1

                            var left = 5
                            var right = width - 5
                            var top = 8
                            var bottom = height - 8
                            var step = data.length > 1 ? (right - left) / (data.length - 1) : 0
                            var points = []

                            for (var p = 0; p < data.length; p++) {
                                var x = left + step * p
                                // Square-root scaling keeps low-usage days visible beside large spikes.
                                var relativeUsage = Math.sqrt(Math.max(0, Number(data[p].tokens) || 0) / maxValue)
                                var y = bottom - relativeUsage * (bottom - top)
                                points.push({ x: x, y: y })
                            }

                            ctx.beginPath()
                            ctx.moveTo(points[0].x, bottom)
                            for (var a = 0; a < points.length; a++)
                                ctx.lineTo(points[a].x, points[a].y)
                            ctx.lineTo(points[points.length - 1].x, bottom)
                            ctx.closePath()
                            var gradient = ctx.createLinearGradient(0, top, 0, bottom)
                            gradient.addColorStop(0, Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.35))
                            gradient.addColorStop(1, Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.03))
                            ctx.fillStyle = gradient
                            ctx.fill()

                            ctx.beginPath()
                            ctx.moveTo(points[0].x, points[0].y)
                            for (var b = 1; b < points.length; b++)
                                ctx.lineTo(points[b].x, points[b].y)
                            ctx.strokeStyle = Theme.surfaceText
                            ctx.lineWidth = 2
                            ctx.stroke()

                            ctx.fillStyle = Theme.primary
                            for (var c = 0; c < points.length; c++) {
                                ctx.beginPath()
                                ctx.arc(points[c].x, points[c].y, 2.5, 0, Math.PI * 2)
                                ctx.fill()
                            }

                            if (chartArea.hoveredIndex >= 0 && chartArea.hoveredIndex < points.length) {
                                ctx.beginPath()
                                ctx.arc(points[chartArea.hoveredIndex].x, points[chartArea.hoveredIndex].y, 5, 0, Math.PI * 2)
                                ctx.fillStyle = Theme.surfaceText
                                ctx.fill()
                                ctx.beginPath()
                                ctx.arc(points[chartArea.hoveredIndex].x, points[chartArea.hoveredIndex].y, 3, 0, Math.PI * 2)
                                ctx.fillStyle = Theme.primary
                                ctx.fill()
                            }
                        }
                    }

                    MouseArea {
                        id: chartMouseArea
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.NoButton

                        onPositionChanged: function(mouse) {
                            var data = usageChart.chartData || []
                            var left = 5
                            var right = width - 5
                            if (data.length < 2 || mouse.x < left || mouse.x > right) {
                                chartArea.hoveredIndex = -1
                                return
                            }

                            chartArea.hoveredIndex = Math.round(
                                (mouse.x - left) / (right - left) * (data.length - 1))
                        }

                        onExited: chartArea.hoveredIndex = -1
                    }

                    StyledRect {
                        visible: chartArea.hoveredIndex >= 0 && chartArea.hoveredIndex < usageChart.chartData.length
                        x: Math.max(Theme.spacingXS, Math.min(parent.width - width - Theme.spacingXS, chartMouseArea.mouseX - width / 2))
                        y: chartMouseArea.mouseY > height + 8
                            ? chartMouseArea.mouseY - height - 8
                            : chartMouseArea.mouseY + 8
                        width: tooltipText.implicitWidth + Theme.spacingS * 2
                        height: tooltipText.implicitHeight + Theme.spacingXS * 2
                        radius: Theme.cornerRadius
                        color: Theme.surfaceContainerHighest
                        z: 2

                        StyledText {
                            id: tooltipText
                            anchors.centerIn: parent
                            text: {
                                var item = usageChart.chartData[chartArea.hoveredIndex]
                                return item.date + " · " + root.fmtTokens(item.tokens) + " " +
                                    I18n.trFor("opencodeUsage", "tokens")
                            }
                            color: Theme.surfaceText
                            font.pixelSize: Theme.fontSizeSmall
                            font.weight: Font.Bold
                        }
                    }
                }

                Connections {
                    target: root
                    function onUsageDataChanged() { usageChart.requestPaint() }
                }

                Row {
                    width: parent.width
                    spacing: 0

                    Repeater {
                        model: root.recentUsage()
                        delegate: Column {
                            width: parent.width / Math.max(1, root.recentUsage().length)
                            spacing: Theme.spacingXXS

                            StyledText {
                                width: parent.width
                                text: modelData.label
                                color: Theme.surfaceVariantText
                                font.pixelSize: Theme.fontSizeSmall
                                horizontalAlignment: Text.AlignHCenter
                            }

                            StyledText {
                                width: parent.width
                                text: root.fmtTokens(modelData.tokens)
                                color: Theme.surfaceText
                                font.pixelSize: Theme.fontSizeSmall
                                horizontalAlignment: Text.AlignHCenter
                            }
                        }
                    }
                }

                StyledText {
                    text: I18n.trFor("opencodeUsage", "OpenCode Go limits")
                    color: Theme.surfaceText
                    font.pixelSize: Theme.fontSizeMedium
                    font.weight: Font.Bold
                }

                Column {
                    width: parent.width
                    spacing: Theme.spacingXS

                    Repeater {
                        model: [
                            { key: "rolling", label: "5H" },
                            { key: "weekly", label: "WEEK" },
                            { key: "monthly", label: "MONTH" }
                        ]
                        delegate: StyledRect {
                            width: parent.width
                            height: limitColumn.implicitHeight + Theme.spacingS * 2
                            radius: Theme.cornerRadius
                            color: Theme.surfaceContainerHigh

                            Column {
                                id: limitColumn
                                anchors.fill: parent
                                anchors.margins: Theme.spacingS
                                spacing: Theme.spacingXXS

                                Row {
                                    width: parent.width
                                    spacing: Theme.spacingS

                                    StyledRect {
                                        width: limitText.implicitWidth + Theme.spacingS * 2
                                        height: 20
                                        radius: height / 2
                                        anchors.verticalCenter: parent.verticalCenter
                                        color: Qt.rgba(Theme.error.r, Theme.error.g, Theme.error.b, 0.16)

                                        StyledText {
                                            id: limitText
                                            anchors.centerIn: parent
                                            text: modelData.label
                                            color: Theme.error
                                            font.pixelSize: Theme.fontSizeSmall
                                            font.weight: Font.Bold
                                        }
                                    }

                                    Item { width: parent.width - limitText.implicitWidth - Theme.spacingS * 3 - limitPercent.implicitWidth; height: 1 }

                                    StyledText {
                                        id: limitPercent
                                        text: root.limitsAvailable()
                                            ? (root.limitPercent(modelData.key) + "%")
                                            : I18n.trFor("opencodeUsage", "No API key")
                                        color: Theme.surfaceText
                                        font.pixelSize: Theme.fontSizeSmall
                                        font.weight: Font.Bold
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                }

                                Rectangle {
                                    visible: root.limitsAvailable()
                                    width: parent.width
                                    height: 4
                                    radius: 2
                                    color: Theme.outlineVariant

                                    Rectangle {
                                        width: parent.width * Math.min(1, Math.max(0, root.limitPercent(modelData.key) / 100))
                                        height: parent.height
                                        radius: parent.radius
                                        color: Theme.primary
                                    }
                                }

                                StyledText {
                                    visible: root.limitsAvailable() && root.limitReset(modelData.key) !== ""
                                    text: I18n.trFor("opencodeUsage", "resets in %1").arg(root.limitReset(modelData.key))
                                    color: Theme.surfaceVariantText
                                    font.pixelSize: Theme.fontSizeSmall
                                }

                                StyledText {
                                    visible: modelData.key === "rolling" && root.usageData && root.usageData.tokens_last_5h !== undefined
                                    text: I18n.trFor("opencodeUsage", "%1 Go tokens in the last 5h (local)")
                                        .arg(root.fmtTokens(root.usageData.tokens_last_5h))
                                    color: Theme.surfaceVariantText
                                    font.pixelSize: Theme.fontSizeSmall
                                }
                            }
                        }
                    }
                }

                StyledText {
                    width: parent.width
                    text: I18n.trFor("opencodeUsage", "R refresh  ·  local OpenCode database")
                    color: Theme.surfaceTextMedium
                    font.pixelSize: Theme.fontSizeSmall
                    horizontalAlignment: Text.AlignHCenter
                }
            }
        }
    }
}
