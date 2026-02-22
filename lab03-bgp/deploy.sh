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

if [ "$CONFIG_DIR" = "configs-full" ]; then
  sed "s|configs-init|configs-full|g" topology.yml > topology-full.yml
  containerlab deploy -t topology-full.yml
else
  containerlab deploy -t topology.yml
fi
