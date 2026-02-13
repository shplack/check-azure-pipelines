#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR" || exit 1

if ! ./check-azure-pipelines.sh -q -i 953; then
  ./show-color.sh red
  exit 1
fi

if ! ./check-azure-pipelines.sh -q -i 1003; then
  ./show-color.sh red
  exit 1
fi

./show-color.sh green
