import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    id: root
    pluginId: "opencodeUsage"

    StyledText {
        width: parent.width
        text: I18n.trFor("opencodeUsage", "Local OpenCode session spending, read from opencode.db.")
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    SliderSetting {
        settingKey: "refreshInterval"
        label: I18n.trFor("opencodeUsage", "Refresh Interval")
        description: I18n.trFor("opencodeUsage", "How often to re-read the OpenCode database.")
        defaultValue: 60
        minimum: 15
        maximum: 300
        unit: "sec"
    }

    ToggleSetting {
        settingKey: "showTokens"
        label: I18n.trFor("opencodeUsage", "Show Tokens")
        description: I18n.trFor("opencodeUsage", "Show input, output, and reasoning token counts in the popout.")
        defaultValue: true
    }

    ToggleSetting {
        settingKey: "showSessions"
        label: I18n.trFor("opencodeUsage", "Show Session Count")
        description: I18n.trFor("opencodeUsage", "Show how many sessions fall in each window in the popout.")
        defaultValue: true
    }

    SliderSetting {
        settingKey: "costAlertUsd"
        label: I18n.trFor("opencodeUsage", "Daily Cost Alert")
        description: I18n.trFor("opencodeUsage", "Turn the bar pill red when today's cost reaches this amount. 0 disables the alert.")
        defaultValue: 0
        minimum: 0
        maximum: 20
        unit: "USD"
    }
}
