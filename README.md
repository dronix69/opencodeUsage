# OpenCode Usage

A [DankMaterialShell](https://danklinux.com/) plugin that shows your local
[OpenCode](https://opencode.ai) spending in the bar and a detailed popout panel:
tokens and cost for today, the last 7 days and the current month, recent usage
chart, providers, models, and your **OpenCode Go** subscription limits.

Everything is read locally. No account, no telemetry, and the plugin never
stores your API key.

![OpenCode Usage](assets/opencode-logo.svg)

## Features

- Bar pill with 7-day token usage (turns red when today's cost passes a configurable threshold).
- Popout panel with:
  - Summary cards: tokens (7D), cost (7D) and number of models.
  - Share line: today / 7D / 30D as a percentage of total usage.
  - Provider breakdown with progress bar.
  - Recent usage chart for the last 7 days.
  - **OpenCode Go limits**: rolling (5 h), weekly and monthly percentages with
    reset countdown.
- Spanish translations included (`translations/es.json`).

## Requirements

| Requirement | Purpose |
| --- | --- |
| DankMaterialShell `>= 1.5.0` | Host shell |
| `sqlite3` | Read `opencode.db` |
| `jq` | Parse JSON |
| `curl` | Fetch OpenCode Go limits |
| [OpenCode](https://opencode.ai) with local usage | Source of the data |

## Install

Copy this directory into your DMS plugins folder:

```sh
cp -r opencodeUsage "${XDG_CONFIG_HOME:-$HOME/.config}/DankMaterialShell/plugins/"
```

Then open **DankMaterialShell Settings → Plugins** and enable **OpenCode Usage**.
Add the widget to a bar from the bar configuration.

## Data sources

The plugin reads two local files, both owned by the OpenCode CLI:

| Data | Source |
| --- | --- |
| Tokens, cost, chart, providers, models | `~/.local/share/opencode/opencode.db` (read-only) |
| OpenCode Go limits | `~/.local/share/opencode/auth.json` → `https://opencode.ai/zen/go/v1/usage` |

- The database is opened in read-only mode and never modified.
- Usage windows are computed from each assistant message timestamp, so a session
  that spans several days is attributed to the day the tokens were spent.
- Cache read/write tokens are included in the totals.
- The API key is read at fetch time and passed through a temporary file with
  `0600` permissions that is removed immediately. It is never logged, stored, or
  committed.

Override the data directory with `OPENCODE_DATA_DIR` if your OpenCode install
lives elsewhere.

## How it works

```text
opencode CLI ──► opencode.db ──┐
                               ├──► fetch-usage.sh ──JSON──► plugin state ──► widget
auth.json ──► opencode.ai API ─┘
```

1. The daemon runs `fetch-usage.sh` every `refreshInterval` seconds.
2. The script queries the database and (when a key exists) the OpenCode Go
   usage endpoint, then writes a single JSON object to the plugin state.
3. The widget renders that state. If there is no API key or the network is
   unavailable, it falls back to local data and shows `No API key`.

## Settings

| Setting | Default | Description |
| --- | --- | --- |
| Refresh Interval | `60` | How often to re-read the database (15–300 s) |
| Show Tokens | `true` | Show input/output/reasoning/cache token counts |
| Show Session Count | `true` | Show session counts per window |
| Daily Cost Alert | `0` | Turn the bar pill red when today's cost reaches this amount (`0` disables) |

## Translations

UI strings live in `translations/<locale>.json`. English is the built-in
fallback; a Spanish translation is included. Contributions welcome.

## Privacy

- No data leaves your machine except the request to `opencode.ai` for your own
  subscription limits, authenticated with your own key.
- The plugin does not embed, transmit or persist any credential.

## License

MIT — see [LICENSE](LICENSE).
