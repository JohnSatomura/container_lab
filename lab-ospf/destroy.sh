#!/bin/bash
set -e
cd "$(dirname "$0")"

# containerlab 停止・削除
# --full でデプロイされた場合は topology-full.yml が存在する
if [ -f topology-full.yml ]; then
  containerlab destroy -t topology-full.yml
else
  containerlab destroy -t topology.yml
fi

# 自動生成ディレクトリと topology-full.yml を削除（次回 deploy 時に確実に反映されるように）
rm -rf clab-ospf/ topology-full.yml

# Linux bridge の削除
if ip link show br-area0 > /dev/null 2>&1; then
  echo "[INFO] br-area0 を削除します（sudo パスワードが必要です）"
  sudo ip link delete br-area0
  echo "[INFO] br-area0 を削除しました"
else
  echo "[INFO] br-area0 は存在しません。スキップします"
fi
