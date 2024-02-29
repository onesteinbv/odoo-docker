#!/bin/bash
set -Eeuxo pipefail

arch=`uname -m`

if [[ $arch = "aarch64" ]]; then
  arch="arm64"
fi

  # This evil hack changes the requirements, as the Odoo versions' just don't work for ARM64
if [[ $arch = "arm64" ]]; then
  SEARCH1="gevent==21.8.0 ; python_version > '3.9' and python_version <= '3.10'  # (Jammy)"
  REPLACE1="gevent==22.10.2 ; python_version > '3.9' and python_version <= '3.10'  # (Jammy)"
  SEARCH2="greenlet==1.1.2 ; python_version  > '3.9' and python_version <= '3.10'  # (Jammy)"
  REPLACE2="greenlet==2.0.2 ; python_version  > '3.9' and python_version <= '3.10'  # (Jammy)"
  sed -i".bak" "s/$SEARCH1/$REPLACE1/; s/$SEARCH2/$REPLACE2/" /odoo/src/odoo/requirements.txt

fi
