#!/usr/bin/env bash
# Checks the test account from .test-account: playlist loads, Xtream API answers,
# and the first live channel is reachable as HLS (what the app plays).
set -euo pipefail
cd "$(dirname "$0")/.."
source .test-account
UA="OnAir/1.0"
M3U="$SERVER/get.php?username=$USERNAME&password=$PASSWORD&type=m3u_plus&output=ts"
n=$(curl -sf -m 60 -A "$UA" "$M3U" | grep -c '^#EXTINF') && echo "M3U: $n canais"
c=$(curl -sf -m 60 -A "$UA" "$SERVER/player_api.php?username=$USERNAME&password=$PASSWORD&action=get_live_categories" | grep -o category_id | wc -l | tr -d ' ')
echo "Xtream: $c categorias"
id=$(curl -sf -m 60 -A "$UA" "$SERVER/player_api.php?username=$USERNAME&password=$PASSWORD&action=get_live_streams" | grep -o '"stream_id":[0-9]*' | head -1 | cut -d: -f2)
code=$(curl -s -m 20 -L -A "$UA" -o /dev/null -w '%{http_code}' "$SERVER/live/$USERNAME/$PASSWORD/$id.m3u8")
echo "HLS canal $id: HTTP $code"
[[ "$code" == 200 ]]
