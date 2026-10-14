#!/bin/sh
# Print one JSON line with local OpenCode spending for today, this week
# (Monday start), and this month. Reads opencode.db in read-only mode.
#
# Windows are computed from per-message timestamps, so a session that spans
# several days is attributed to the day the tokens were actually spent.
# The 7-day window is rolling, matching the usage dashboard view.
# Cache read/write tokens are included in the totals because they are part of
# the real consumption.
#
# Env:
#   OPENCODE_DATA_DIR  data directory (default: $XDG_DATA_HOME/opencode or ~/.local/share/opencode)
set -u
umask 077

data_dir="${OPENCODE_DATA_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/opencode}"
db="$data_dir/opencode.db"
now=$(date +%s)

fail() {
    jq -cn --arg reason "$1" --arg msg "$2" --argjson now "$now" \
        '{status: "error", reason: $reason, error: $msg, captured_at: $now}'
    exit 0
}

# Keep only plain non-negative numbers; anything else becomes 0.
num() {
    case "${1:-}" in
        ''|*[!0-9.]*) echo 0 ;;
        *) echo "$1" ;;
    esac
}

# OpenCode Go usage limits, read from the subscription API with the key stored
# in auth.json. Returns a compact JSON object; never prints the key.
fetch_go_limits() {
    auth_file="$data_dir/auth.json"
    [ -f "$auth_file" ] || { echo '{"available":false,"reason":"no_key"}'; return; }
    command -v curl >/dev/null 2>&1 || { echo '{"available":false,"reason":"no_curl"}'; return; }
    command -v jq >/dev/null 2>&1 || { echo '{"available":false,"reason":"no_jq"}'; return; }
    api_key=$(jq -r '."opencode-go".key // empty' "$auth_file" 2>/dev/null)
    [ -n "$api_key" ] || { echo '{"available":false,"reason":"no_key"}'; return; }
    cfg=$(mktemp) || { echo '{"available":false,"reason":"error"}'; return; }
    chmod 600 "$cfg" 2>/dev/null
    printf 'header = "Authorization: Bearer %s"\n' "$api_key" > "$cfg"
    raw=$(curl -sS -K "$cfg" --max-time 10 "https://opencode.ai/zen/go/v1/usage" 2>/dev/null)
    rm -f "$cfg"
    api_key=""
    [ -n "$raw" ] || { echo '{"available":false,"reason":"error"}'; return; }
    echo "$raw" | jq -c 'if .usage then {available:true, rolling:.usage.rolling, weekly:.usage.weekly, monthly:.usage.monthly} else {available:false, reason:"error"} end' 2>/dev/null \
        || echo '{"available":false,"reason":"error"}'
}

[ -f "$db" ] || fail db_missing "OpenCode database not found at $db."
command -v sqlite3 >/dev/null 2>&1 || fail no_sqlite "sqlite3 is not installed."
command -v jq >/dev/null 2>&1 || fail no_jq "jq is not installed."

row=$(sqlite3 -readonly -cmd '.timeout 2000' "$db" "
WITH w AS (
    SELECT
        CAST(strftime('%s', 'now', 'localtime', 'start of day') AS INTEGER) * 1000 AS today,
        CAST(strftime('%s', 'now', 'localtime', '-6 days', 'start of day') AS INTEGER) * 1000 AS week,
        CAST(strftime('%s', 'now', 'localtime', 'start of month') AS INTEGER) * 1000 AS month
),
m AS (
    SELECT
        time_created,
        session_id,
        coalesce(json_extract(data, '\$.cost'), 0) AS cost,
        coalesce(json_extract(data, '\$.tokens.input'), 0) AS tin,
        coalesce(json_extract(data, '\$.tokens.output'), 0) AS tout,
        coalesce(json_extract(data, '\$.tokens.reasoning'), 0) AS tre,
        coalesce(json_extract(data, '\$.tokens.cache.read'), 0) AS tcr,
        coalesce(json_extract(data, '\$.tokens.cache.write'), 0) AS tcw
    FROM message
    WHERE json_extract(data, '\$.role') = 'assistant'
)
SELECT
    coalesce(round(sum(CASE WHEN m.time_created >= w.today THEN m.cost END), 4), 0),
    coalesce(sum(CASE WHEN m.time_created >= w.today THEN m.tin END), 0),
    coalesce(sum(CASE WHEN m.time_created >= w.today THEN m.tout END), 0),
    coalesce(sum(CASE WHEN m.time_created >= w.today THEN m.tre END), 0),
    coalesce(sum(CASE WHEN m.time_created >= w.today THEN m.tcr END), 0),
    coalesce(sum(CASE WHEN m.time_created >= w.today THEN m.tcw END), 0),
    count(DISTINCT CASE WHEN m.time_created >= w.today THEN m.session_id END),
    coalesce(round(sum(CASE WHEN m.time_created >= w.week THEN m.cost END), 4), 0),
    coalesce(sum(CASE WHEN m.time_created >= w.week THEN m.tin END), 0),
    coalesce(sum(CASE WHEN m.time_created >= w.week THEN m.tout END), 0),
    coalesce(sum(CASE WHEN m.time_created >= w.week THEN m.tre END), 0),
    coalesce(sum(CASE WHEN m.time_created >= w.week THEN m.tcr END), 0),
    coalesce(sum(CASE WHEN m.time_created >= w.week THEN m.tcw END), 0),
    count(DISTINCT CASE WHEN m.time_created >= w.week THEN m.session_id END),
    coalesce(round(sum(CASE WHEN m.time_created >= w.month THEN m.cost END), 4), 0),
    coalesce(sum(CASE WHEN m.time_created >= w.month THEN m.tin END), 0),
    coalesce(sum(CASE WHEN m.time_created >= w.month THEN m.tout END), 0),
    coalesce(sum(CASE WHEN m.time_created >= w.month THEN m.tre END), 0),
    coalesce(sum(CASE WHEN m.time_created >= w.month THEN m.tcr END), 0),
    coalesce(sum(CASE WHEN m.time_created >= w.month THEN m.tcw END), 0),
    count(DISTINCT CASE WHEN m.time_created >= w.month THEN m.session_id END),
    coalesce(round(sum(m.cost), 4), 0),
    coalesce(sum(m.tin), 0),
    coalesce(sum(m.tout), 0),
    coalesce(sum(m.tre), 0),
    coalesce(sum(m.tcr), 0),
    coalesce(sum(m.tcw), 0)
FROM m, w
" 2>/dev/null)

[ -n "$row" ] || fail db_error "Could not read the OpenCode database."

old_ifs=$IFS
IFS='|'
# shellcheck disable=SC2086
set -- $row
IFS=$old_ifs

t_cost=$(num "${1:-}")   t_in=$(num "${2:-}")   t_out=$(num "${3:-}")   t_re=$(num "${4:-}")   t_cr=$(num "${5:-}")   t_cw=$(num "${6:-}")   t_n=$(num "${7:-}")
w_cost=$(num "${8:-}")   w_in=$(num "${9:-}")   w_out=$(num "${10:-}")  w_re=$(num "${11:-}")  w_cr=$(num "${12:-}")  w_cw=$(num "${13:-}")  w_n=$(num "${14:-}")
m_cost=$(num "${15:-}")  m_in=$(num "${16:-}")  m_out=$(num "${17:-}")  m_re=$(num "${18:-}")  m_cr=$(num "${19:-}")  m_cw=$(num "${20:-}")  m_n=$(num "${21:-}")
a_cost=$(num "${22:-}")  a_in=$(num "${23:-}")  a_out=$(num "${24:-}")  a_re=$(num "${25:-}")  a_cr=$(num "${26:-}")  a_cw=$(num "${27:-}")

# Recent seven-day usage for the chart and provider summary.
daily_json=$(sqlite3 -readonly -cmd '.timeout 2000' "$db" "
WITH RECURSIVE days(day) AS (
    SELECT date('now', 'localtime', '-6 days')
    UNION ALL
    SELECT date(day, '+1 day') FROM days WHERE day < date('now', 'localtime')
),
usage AS (
    SELECT
        date(time_created / 1000, 'unixepoch', 'localtime') AS day,
        coalesce(sum(
            coalesce(json_extract(data, '\$.tokens.input'), 0) +
            coalesce(json_extract(data, '\$.tokens.output'), 0) +
            coalesce(json_extract(data, '\$.tokens.reasoning'), 0) +
            coalesce(json_extract(data, '\$.tokens.cache.read'), 0) +
            coalesce(json_extract(data, '\$.tokens.cache.write'), 0)
        ), 0) AS tokens
    FROM message
    WHERE json_extract(data, '\$.role') = 'assistant'
    GROUP BY day
)
SELECT coalesce(json_group_array(json_object(
    'date', days.day,
    'label', CASE strftime('%w', days.day)
        WHEN '0' THEN 'Sun' WHEN '1' THEN 'Mon' WHEN '2' THEN 'Tue'
        WHEN '3' THEN 'Wed' WHEN '4' THEN 'Thu' WHEN '5' THEN 'Fri'
        ELSE 'Sat' END,
    'tokens', coalesce(usage.tokens, 0)
)), '[]')
FROM days LEFT JOIN usage ON usage.day = days.day
" 2>/dev/null)
[ -n "$daily_json" ] || daily_json='[]'

providers_json=$(sqlite3 -readonly -cmd '.timeout 2000' "$db" "
WITH bounds AS (
    SELECT CAST(strftime('%s', 'now', 'localtime', '-6 days', 'start of day') AS INTEGER) * 1000 AS since
),
providers AS (
    SELECT
        coalesce(json_extract(data, '\$.providerID'), 'local') AS name,
        coalesce(sum(
            coalesce(json_extract(data, '\$.tokens.input'), 0) +
            coalesce(json_extract(data, '\$.tokens.output'), 0) +
            coalesce(json_extract(data, '\$.tokens.reasoning'), 0) +
            coalesce(json_extract(data, '\$.tokens.cache.read'), 0) +
            coalesce(json_extract(data, '\$.tokens.cache.write'), 0)
        ), 0) AS tokens,
        count(DISTINCT json_extract(data, '\$.modelID')) AS models
    FROM message, bounds
    WHERE json_extract(data, '\$.role') = 'assistant' AND time_created >= bounds.since
    GROUP BY name
)
SELECT coalesce(json_group_array(json_object('name', name, 'tokens', tokens, 'models', models)), '[]') FROM providers
" 2>/dev/null)
[ -n "$providers_json" ] || providers_json='[]'

models_count=$(sqlite3 -readonly -cmd '.timeout 2000' "$db" "
SELECT count(DISTINCT json_extract(data, '\$.modelID'))
FROM message
WHERE json_extract(data, '\$.role') = 'assistant'
  AND time_created >= CAST(strftime('%s', 'now', 'localtime', '-6 days', 'start of day') AS INTEGER) * 1000
" 2>/dev/null)
models_count=$(num "$models_count")

# OpenCode Go subscription limits, from the API using the local auth.json key.
limits_json=$(fetch_go_limits)
[ -n "$limits_json" ] || limits_json='{"available":false,"reason":"error"}'

jq -cn --argjson now "$now" \
    --argjson tc "$t_cost" --argjson ti "$t_in" --argjson to "$t_out" --argjson tr "$t_re" --argjson tcr "$t_cr" --argjson tcw "$t_cw" --argjson tn "$t_n" \
    --argjson wc "$w_cost" --argjson wi "$w_in" --argjson wo "$w_out" --argjson wr "$w_re" --argjson wcr "$w_cr" --argjson wcw "$w_cw" --argjson wn "$w_n" \
    --argjson mc "$m_cost" --argjson mi "$m_in" --argjson mo "$m_out" --argjson mr "$m_re" --argjson mcr "$m_cr" --argjson mcw "$m_cw" --argjson mn "$m_n" \
    --argjson ai "$a_in" --argjson ao "$a_out" --argjson ar "$a_re" --argjson acr "$a_cr" --argjson acw "$a_cw" \
    --argjson daily "$daily_json" --argjson providers "$providers_json" --argjson models "$models_count" \
    --argjson limits "$limits_json" \
    '{
        status: "ok",
        captured_at: $now,
        tokens_all_time: ($ai + $ao + $ar + $acr + $acw),
        recent_usage: $daily,
        providers: $providers,
        models: $models,
        limits: $limits,
        windows: {
            today: {
                cost: $tc,
                tokens_input: $ti, tokens_output: $to, tokens_reasoning: $tr,
                tokens_cache_read: $tcr, tokens_cache_write: $tcw,
                tokens_total: ($ti + $to + $tr + $tcr + $tcw),
                sessions: $tn
            },
            week: {
                cost: $wc,
                tokens_input: $wi, tokens_output: $wo, tokens_reasoning: $wr,
                tokens_cache_read: $wcr, tokens_cache_write: $wcw,
                tokens_total: ($wi + $wo + $wr + $wcr + $wcw),
                sessions: $wn
            },
            month: {
                cost: $mc,
                tokens_input: $mi, tokens_output: $mo, tokens_reasoning: $mr,
                tokens_cache_read: $mcr, tokens_cache_write: $mcw,
                tokens_total: ($mi + $mo + $mr + $mcr + $mcw),
                sessions: $mn
            }
        }
    }'
