#!/bin/bash
# SVG -> 512px PNG via Quick Look (ImageMagick's own SVG renderer drops gradients), corners cut back to transparent
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd); assets="$here/../assets"; tmp=$(mktemp -d)
python3 "$here/make-icons.py"
for svg in "$here"/*.svg; do
  name=$(basename "$svg" .svg)
  qlmanage -t -s 512 -o "$tmp" "$svg" >/dev/null 2>&1
  magick "$tmp/$name.svg.png" -alpha set \
    \( -size 512x512 xc:none -fill white -draw "roundrectangle 32,32 479,479 104,104" \) \
    -compose DstIn -composite "$assets/$name.png"
done
rm -r "$tmp"
