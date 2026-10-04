#!/usr/bin/env bash
# Runs inside a Modal GPU container (created through the Modal MCP connector, which
# supplies auth). Installs pixi, which builds fractal.mojo with the pixi-build Mojo
# backend, then renders.
#   setup:  bash modal_sandbox.sh setup
#   render: bash modal_sandbox.sh render <out.png> <w> <h> <cx> <cy> <zoom> <iter> [julia re im]
set -euo pipefail
cd /app
export PATH="$HOME/.pixi/bin:$PATH"
case "${1:-}" in
  setup)
    command -v curl >/dev/null || { apt-get update -qq && apt-get install -y -qq curl ca-certificates >/dev/null; }
    command -v pixi >/dev/null || curl -fsSL https://pixi.sh/install.sh | bash
    pixi install
    nvidia-smi --query-gpu=name --format=csv,noheader
    ;;
  render)
    shift
    pixi run render "$@"
    ;;
  *) echo "usage: $0 setup|render ..." >&2; exit 2 ;;
esac
