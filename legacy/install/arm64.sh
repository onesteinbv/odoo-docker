#!/bin/bash
set -Eeuxo pipefail

arch=`uname -m`

if [[ $arch = "aarch64" ]]; then
  arch="arm64"
fi

if [[ $arch = "arm64" ]]; then
  apt-get install -y --no-install-recommends \
    libldap2-dev \
    libsasl2-dev \
    libpq-dev \
    g++
fi
