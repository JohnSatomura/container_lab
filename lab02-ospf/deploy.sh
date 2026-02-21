#!/bin/bash
set -e

# Linux bridge の作成（既に存在する場合はスキップ）
if ! ip link show br-area0 > /dev/null 2>&1; then
  echo "[INFO] br-area0 を作成します（sudo パスワードが必要です）"
  sudo ip link add br-area0 type bridge
  sudo ip link set br-area0 up
  echo "[INFO] br-area0 を作成しました"
else
  echo "[INFO] br-area0 は既に存在します。スキップします"
fi

# containerlab デプロイ
containerlab deploy -t topology.yml
