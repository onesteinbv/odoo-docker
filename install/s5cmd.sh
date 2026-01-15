#!/bin/bash
set -Eeuxo pipefail

curl -o s5cmd.tar.gz -SL "https://github.com/peak/s5cmd/releases/download/v2.3.0/s5cmd_2.3.0_Linux-64bit.tar.gz"
tar xvfz s5cmd.tar.gz -C /usr/local/bin
chmod +x /usr/local/bin/s5cmd

# verify that the binary works
s5cmd --help
