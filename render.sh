#!/usr/bin/env bash
# Renders one frame with the pixi-built `fractal` binary and converts it to PNG/JPEG.
#   pixi run render-gpu <out.png> <w> <h> <cx> <cy> <zoom> <iter> [1 <julia_re> <julia_im>]
set -euo pipefail
out="${1:-spiral.png}"; shift || true
frame="$(mktemp --suffix=.ppm)"
fractal "$frame" "$@"
python -c "import sys; from PIL import Image; Image.open(sys.argv[1]).save(sys.argv[2])" "$frame" "$out"
rm -f "$frame"
