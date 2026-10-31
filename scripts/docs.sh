#!/usr/bin/env bash
set -euo pipefail

# Run from the repository root. GOOSDOC names goosdoc's main.goose.
exec "${GOOSE:-goose}" run "${GOOSDOC:-../goosdoc/main.goose}" -- \
  --title "goosopt API" --symbols api.txt --require-docs --require-examples \
  --output "${DOC_OUTPUT:-API.md}" "$@" goosopt.goose
