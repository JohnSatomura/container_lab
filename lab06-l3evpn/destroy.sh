#!/bin/bash
set -e
cd "$(dirname "$0")"

# containerlab 停止・削除
if [ -f topology-full.yml ]; then
  containerlab destroy -t topology-full.yml
else
  containerlab destroy -t topology.yml
fi

# 自動生成ディレクトリと topology-full.yml を削除
rm -rf clab-lab06-l3evpn/ topology-full.yml

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
