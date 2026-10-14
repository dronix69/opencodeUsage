import QtQuick
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Modules.Plugins

PluginComponent {
    id: root
    pluginId: "opencodeUsage"

    property int refreshInterval: pluginData.refreshInterval || 60
    property string pluginDir: {
        var url = Qt.resolvedUrl(".")
        var path = url.toString()
        if (path.indexOf("file://") === 0) path = path.substring(7)
        return path
    }

    property var usageData: null
    property bool fetchQueued: false

    Timer {
        id: refreshTimer
        interval: root.refreshInterval * 1000
        running: true
        repeat: true
        triggeredOnStart: false
        onTriggered: root.requestFetch()
    }

    Process {
        id: fetchProcess
        command: ["sh", root.pluginDir + "fetch-usage.sh"]
        stdout: SplitParser {
            onRead: line => {
                try {
                    var t = line.trim()
                    if (t.length === 0) return
                    root.usageData = JSON.parse(t)
                    pluginService.savePluginState("opencodeUsage", "lastData", root.usageData)
                } catch (e) {}
            }
        }
        stderr: SplitParser { onRead: line => {} }
        onExited: code => {
            if (root.fetchQueued) {
                root.fetchQueued = false
                Qt.callLater(function () { root.requestFetch() })
            }
        }
    }

    function requestFetch() {
        if (fetchProcess.running) {
            fetchQueued = true
            return
        }
        fetchProcess.running = true
    }

    Connections {
        target: root.pluginService
        enabled: root.pluginService !== null
        function onPluginDataChanged(changedPluginId) {
            // A changed refresh interval restarts the timer via pluginData binding.
            if (changedPluginId === "opencodeUsage")
                Qt.callLater(function () { root.requestFetch() })
        }
    }

    Component.onCompleted: {
        try {
            var c = pluginService.loadPluginState("opencodeUsage", "lastData", null)
            if (c) root.usageData = c
        } catch (e) {}
        // PluginComponent loads pluginData after child completion; defer the first request.
        Qt.callLater(function () { root.requestFetch() })
    }
}
