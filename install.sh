#!/usr/bin/env bash
set -e

# install mise if missing
if ! command -v mise >/dev/null; then
  curl https://mise.run | sh
fi

# install tools
mise install

