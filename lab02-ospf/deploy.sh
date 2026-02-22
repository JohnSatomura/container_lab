#!/bin/bash
set -e
cd "$(dirname "$0")"

CONFIG_DIR="configs-init"

if [ "$1" = "--full" ]; then
  CONFIG_DIR="configs-full"
  echo "[INFO] フルコンフィグモード（configs-full）で起動します"
else
  echo "[INFO] ハンズオンモード（configs-init）で起動します"
fi

# Linux bridge の作成（既に存在する場合はスキップ）
if ! ip link show br-area0 > /dev/null 2>&1; then
  echo "[INFO] br-area0 を作成します（sudo パスワードが必要です）"
  sudo ip link add br-area0 type bridge
  sudo ip link set br-area0 up
  echo "[INFO] br-area0 を作成しました"
else
  echo "[INFO] br-area0 は既に存在します。スキップします"
fi

if [ "$CONFIG_DIR" = "configs-full" ]; then
  sed "s|configs-init|configs-full|g" topology.yml > topology-full.yml
  containerlab deploy -t topology-full.yml
else
  containerlab deploy -t topology.yml
fi
