#!/bin/bash
set -Eeuxo pipefail

apt-get update
apt-get install -y --no-install-recommends \
  ca-certificates \
  less \
  nano \
  git
