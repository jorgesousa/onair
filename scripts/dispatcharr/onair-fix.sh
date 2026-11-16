#!/usr/bin/env bash
# ONAIR auto-fix: a Dispatcharr stream profile that makes every channel playable by Apple's
# players (Mac, iPhone, iPad), doing only what each channel needs.
#
#   onair-fix.sh <userAgent> <streamUrl>      → MPEG-TS on stdout
#
# One connection to the provider (it allows one): the stream is read once; its first bytes are
# kept, inspected, then handed to ffmpeg together with the rest of the same connection.
#   - video fine, audio AAC/AC-3       → passed through untouched (remux only)
#   - audio MP2 or anything else       → audio to AAC, video untouched
#   - video malformed (too many reference frames), interlaced, or not H.264/HEVC
#                                      → video re-encoded to 720p H.264 (and audio to AAC)
set -u
export LD_LIBRARY_PATH=/usr/local/lib
UA="$1"; URL="$2"
PROBE_BYTES=${ONAIR_PROBE_BYTES:-2000000}
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
log() { echo "onair-fix: $*" >&2; }

curl -sL --fail -A "$UA" "$URL" | {
    # Up to ~2 MB or 2.5 s, whichever comes first: Dispatcharr wants data within 5 s, and an SD
    # channel (~1.5 Mbps) would take ~10 s to fill 2 MB. 2.5 s is plenty to see the format.
    timeout "${ONAIR_PROBE_SECONDS:-2.5}" head -c "$PROBE_BYTES" > "$WORK/head.ts"
    [ -s "$WORK/head.ts" ] || { log "no data"; exit 1; }

    probe() { ffprobe -v quiet -select_streams "$1" -show_entries stream="$2" -of default=nw=1:nk=1 "$WORK/head.ts" | head -1; }
    vcodec=$(probe v:0 codec_name); field=$(probe v:0 field_order); acodec=$(probe a:0 codec_name)
    broken=0
    ffmpeg -v error -i "$WORK/head.ts" -map 0:v:0 -f null - 2>&1 | grep -q -E 'exceeds max|corrupt' && broken=1

    video=(-c:v copy); audio=(-c:a copy); why=()
    case "$acodec" in aac|ac3|eac3|"") ;; *) audio=(-c:a aac -b:a 160k); why+=("audio $acodec") ;; esac
    if [ "$broken" = 1 ] || { [ -n "$field" ] && [ "$field" != progressive ] && [ "$field" != unknown ]; } \
       || { [ -n "$vcodec" ] && [ "$vcodec" != h264 ] && [ "$vcodec" != hevc ]; }; then
        video=(-c:v libx264 -preset veryfast -tune zerolatency -profile:v high -level 4.0 -refs 3 -g 50
               -vf yadif=mode=0:deint=interlaced,scale=-2:720 -b:v 3500k -maxrate 4000k -bufsize 8000k)
        audio=(-c:a aac -b:a 160k)
        why+=("video $vcodec/$field/broken=$broken")
    fi
    log "video=$vcodec field=$field audio=$acodec → ${why[*]:-pass-through}"

    cat "$WORK/head.ts" - | ffmpeg -v error -fflags +genpts+discardcorrupt -i pipe:0 \
        -map 0:v:0 -map '0:a:0?' "${video[@]}" "${audio[@]}" -f mpegts pipe:1
}
