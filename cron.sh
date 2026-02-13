#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR" || exit 1

# check if repo is updated and if updated, pull changes and exit
git fetch origin main
LOCAL=$(git rev-parse @)
REMOTE=$(git rev-parse @{u})
if [ "$LOCAL" != "$REMOTE" ]; then
  echo "Repo is not up to date. Pulling changes..."
  git pull origin main
  exit 0
fi

if ! ./check-azure-pipelines.sh -q -i 953; then
  ./show-color.sh red
  exit 1
fi

if ! ./check-azure-pipelines.sh -q -i 1003; then
  ./show-color.sh red
  exit 1
fi

./show-color.sh green
