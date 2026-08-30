#!/usr/bin/env bash
#
# The whisper.cpp weights the bundled fallback needs (ADR-0003). They are MIT and they are
# plain files, but they are far too large to live in git, so they are fetched once and land
# next to the binary — `swift run` has no .app bundle, so Bundle.main.resourceURL is the
# build directory itself. `swift package clean` takes them with it; re-run this if it does.
#
# Parakeet, the default engine, is not fetched here. Without it BundledASR.parakeet throws
# and transcribe falls through to whisper, which is the behaviour this script buys you.
#
# Usage:
#   scripts/fetch-models.sh                 # full turbo weights, ~1.6 GB
#   scripts/fetch-models.sh --quant q5_0    # quantised, ~575 MB
#   scripts/fetch-models.sh --dest DIR      # somewhere other than .build/debug

set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dest="$repo/.build/debug"
quant="full"

while [ $# -gt 0 ]; do
    case "$1" in
        --quant) quant="${2:?--quant needs a value}"; shift 2 ;;
        --dest) dest="${2:?--dest needs a value}"; shift 2 ;;
        -h|--help) sed -n '2,14p' "${BASH_SOURCE[0]}" | cut -c3-; exit 0 ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
done

case "$quant" in
    full) remote="ggml-large-v3-turbo.bin"; floor=$((1024 * 1024 * 1024)) ;;
    q5_0) remote="ggml-large-v3-turbo-q5_0.bin"; floor=$((400 * 1024 * 1024)) ;;
    *) echo "unknown --quant: $quant (expected full or q5_0)" >&2; exit 2 ;;
esac

# BundledASR.loadWhisper reads exactly this name, whichever quantisation is behind it.
local_name="ggml-large-v3-turbo.bin"
url="https://huggingface.co/ggerganov/whisper.cpp/resolve/main/$remote?download=true"
target="$dest/$local_name"

command -v curl >/dev/null || { echo "curl not found" >&2; exit 1; }

# A build directory only exists after a build, and downloading into a path SwiftPM has not
# made yet would put the weights somewhere the app never looks.
if [ ! -d "$dest" ]; then
    echo "no $dest — run 'swift build' first, or pass --dest" >&2
    exit 1
fi

# Size is the only check worth making without a published checksum: an interrupted fetch or
# an HTML error page is small, and a whole model is not.
if [ -f "$target" ]; then
    have=$(/usr/bin/stat -f%z "$target")
    if [ "$have" -ge "$floor" ]; then
        echo "already there: $target ($((have / 1024 / 1024)) MB)"
        exit 0
    fi
    echo "resuming a partial $local_name ($((have / 1024 / 1024)) MB)"
fi

echo "fetching $remote -> $target"
curl --fail --location --progress-bar --continue-at - --output "$target" "$url"

got=$(/usr/bin/stat -f%z "$target")
if [ "$got" -lt "$floor" ]; then
    echo "downloaded $((got / 1024 / 1024)) MB, expected far more — leaving it for a resume" >&2
    exit 1
fi

echo "$target ($((got / 1024 / 1024)) MB). Speak now falls through to whisper."
