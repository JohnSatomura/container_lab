#!/bin/bash
set -e
cd "$(dirname "$0")"

# containerlab 停止・削除
containerlab destroy -t topology.yml

# 自動生成ディレクトリを削除
rm -rf clab-lab-l3evpn/

# ansible-lab06 コンテナを削除
if docker ps -a --format '{{.Names}}' | grep -q '^ansible-lab06$'; then
  echo "[INFO] ansible-lab06 コンテナを削除します"
  docker rm -f ansible-lab06
fi

# ansible-eos イメージを削除
if docker image inspect ansible-eos &>/dev/null; then
  echo "[INFO] ansible-eos イメージを削除します"
  docker rmi ansible-eos
fi
