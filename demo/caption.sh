#!/bin/bash
# Adds a caption strip above a recording, so a new reader knows what each clip shows.
#
#   bash demo/caption.sh <in.gif> <out base name> "Title" "Step line 1" "Step line 2" ...
#
# It writes <out base name>.gif and <out base name>.mp4. It needs rsvg-convert and ffmpeg
# (on macOS: brew install librsvg ffmpeg). It runs on your machine only, never in CI.
# Set TRIM=15 to keep only the first 15 seconds.
# The mp4 is for GitHub: drag it into the editor of an issue or the README to get a link
# that plays inline. Do not commit mp4 files: the plugin directory holds unknown binaries.
set -e
IN="$1"; OUT="$2"; TITLE="$3"; shift 3
[ -f "$IN" ] && [ -n "$OUT" ] && [ -n "$TITLE" ] || { sed -n 2,9p "$0"; exit 1; }
command -v rsvg-convert >/dev/null && command -v ffmpeg >/dev/null || { echo "Install librsvg and ffmpeg."; exit 1; }

esc() { printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'; }

W="$(ffprobe -v error -select_streams v:0 -show_entries stream=width -of csv=p=0 "$IN")"
LINES=$#
H=$((96 + LINES * 50))
TMP="$(mktemp -d)"
{
  printf '<svg xmlns="http://www.w3.org/2000/svg" width="%s" height="%s">' "$W" "$H"
  printf '<rect width="100%%" height="100%%" fill="#11111b"/>'
  printf '<text x="40" y="62" font-family="Helvetica, Arial, sans-serif" font-size="40" font-weight="700" fill="#f5e0dc">'
  printf '<tspan fill="#f5c2e7">TEMPER</tspan>  %s</text>' "$(esc "$TITLE")"
  y=112
  for line in "$@"; do
    printf '<text x="40" y="%s" font-family="Helvetica, Arial, sans-serif" font-size="30" fill="#cdd6f4">%s</text>' "$y" "$(esc "$line")"
    y=$((y + 50))
  done
  printf '</svg>'
} > "$TMP/cap.svg"
rsvg-convert -w "$W" -o "$TMP/cap.png" "$TMP/cap.svg"

FILTER="[0:v]pad=iw:ih+${H}:0:${H}:color=0x11111b[v];[v][1:v]overlay=0:0,scale=1280:-2:flags=lanczos"
ffmpeg -v error -y -i "$IN" -i "$TMP/cap.png" \
  -filter_complex "${FILTER},split[a][b];[b]palettegen=stats_mode=diff[p];[a][p]paletteuse=dither=bayer:bayer_scale=5" \
  -loop 0 ${TRIM:+-t $TRIM} "$OUT.gif"
ffmpeg -v error -y -i "$IN" -i "$TMP/cap.png" \
  -filter_complex "${FILTER},format=yuv420p" -c:v libx264 -crf 23 -an ${TRIM:+-t $TRIM} "$OUT.mp4" 2>/dev/null \
  || echo "mp4 skipped: this ffmpeg has no libx264"
rm -rf "$TMP"
ls -la "$OUT.gif" "$OUT.mp4" 2>/dev/null | awk '{print $5, $9}'
