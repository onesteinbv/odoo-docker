#!/bin/bash
set -eo pipefail

arch=`uname -m`

if [[ $arch = "aarch64" ]]; then
  arch="arm64"
  hash="c73c547159bcc12467f5163f86f49d493237cf007f8b7507783f51f35ed9bea1"
else
  arch="amd64"
  hash="bb9b55630aa63da22bafb2132f06fe00f298ef16272a99134e69495c37b33ce9"
fi
curl -o "dockerize-linux.tar.gz" -SL "https://github.com/jwilder/dockerize/releases/download/v0.7.0/dockerize-linux-${arch}-v0.7.0.tar.gz"
echo "${hash} dockerize-linux.tar.gz" | sha256sum -c -
tar xvfz dockerize-linux.tar.gz -C /usr/local/bin && rm dockerize-linux.tar.gz
