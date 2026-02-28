#!/bin/bash
set -e
cd "$(dirname "$0")"

# containerlab 停止・削除
containerlab destroy -t topology.yml

# 自動生成ディレクトリを削除（次回 deploy 時に startup-config が確実に反映されるようにする）
rm -rf clab-lab-ansible/

# ansible-lab-ansible コンテナを削除
if docker ps -a --format '{{.Names}}' | grep -q '^ansible-lab-ansible$'; then
  echo "[INFO] ansible-lab-ansible コンテナを削除します"
  docker rm -f ansible-lab-ansible
fi

# ansible-eos イメージを削除
if docker image inspect ansible-eos &>/dev/null; then
  echo "[INFO] ansible-eos イメージを削除します"
  docker rmi ansible-eos
fi
