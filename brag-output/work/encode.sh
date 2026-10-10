#!/bin/bash
# Encode frames + soundtrack, then bake the poster in as frame 0 (replacing it, so timing is unchanged).
set -e
cd "$(dirname "$0")"
POSTER=frames/f0165.png   # t = 5.5s, reveal headline fully settled
cp "$POSTER" poster.png
ffmpeg -v error -y -i poster.png -q:v 2 ../brag.jpg
mkdir -p seq && rm -f seq/*.png
cp frames/*.png seq/ && cp poster.png seq/f0000.png
ffmpeg -v error -y -framerate 30 -i seq/f%04d.png -i soundtrack.wav \
  -c:v libx264 -preset slow -crf 18 -pix_fmt yuv420p -profile:v high -movflags +faststart \
  -c:a aac -b:a 192k -shortest ../brag.mp4
ffprobe -v error -show_entries format=duration:stream=codec_name,width,height,r_frame_rate -of compact ../brag.mp4
