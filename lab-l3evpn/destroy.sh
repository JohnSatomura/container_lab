#!/bin/bash
set -e
cd "$(dirname "$0")"

# containerlab 停止・削除
containerlab destroy -t topology.yml

# 自動生成ディレクトリを削除
rm -rf clab-l3evpn/

# ansible-lab-l3evpn コンテナを削除
if docker ps -a --format '{{.Names}}' | grep -q '^ansible-lab-l3evpn$'; then
  echo "[INFO] ansible-lab-l3evpn コンテナを削除します"
  docker rm -f ansible-lab-l3evpn
fi

# ansible-eos イメージを削除
if docker image inspect ansible-eos &>/dev/null; then
  echo "[INFO] ansible-eos イメージを削除します"
  docker rmi ansible-eos
fi
