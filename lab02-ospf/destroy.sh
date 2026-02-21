#!/bin/bash
set -e

# containerlab 停止・削除
containerlab destroy -t topology.yml

# 自動生成ディレクトリを削除（次回 deploy 時に startup-config が確実に反映されるようにする）
rm -rf clab-lab02-ospf/

# Linux bridge の削除
if ip link show br-area0 > /dev/null 2>&1; then
  echo "[INFO] br-area0 を削除します（sudo パスワードが必要です）"
  sudo ip link delete br-area0
  echo "[INFO] br-area0 を削除しました"
else
  echo "[INFO] br-area0 は存在しません。スキップします"
fi
