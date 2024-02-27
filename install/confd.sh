#!/bin/bash
set -eo pipefail

arch=`uname -m`

if [[ $arch = "aarch64" ]]; then
  arch="arm64"
  hash="23d8b7796def38821394033e40b48f001b0271a072a5436397ccc57806dbf1f7"
else
  arch="amd64"
  hash="255d2559f3824dd64df059bdc533fd6b697c070db603c76aaf8d1d5e6b0cc334"
fi

pushd /usr/local/bin
curl -SL -o confd "https://github.com/kelseyhightower/confd/releases/download/v0.16.0/confd-0.16.0-linux-${arch}"
echo "${hash} confd" | sha256sum -c -
chmod +x confd
popd
