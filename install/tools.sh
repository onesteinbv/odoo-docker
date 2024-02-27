#!/bin/bash
set -Eeuxo pipefail

apt-get install -y --no-install-recommends \
  ca-certificates \
  less \
  nano \
  gcc \
  python3-dev \
  git \
  openssh-client
