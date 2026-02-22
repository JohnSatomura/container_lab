#!/bin/bash
set -e

CONFIG_DIR="configs-init"

if [ "$1" = "--full" ]; then
  CONFIG_DIR="configs-full"
  echo "[INFO] フルコンフィグモード（configs-full）で起動します"
else
  echo "[INFO] ハンズオンモード（configs-init）で起動します"
fi

if [ "$CONFIG_DIR" = "configs-full" ]; then
  TMP=$(mktemp /tmp/topology-XXXXXX.yml)
  sed "s|configs-init|configs-full|g" topology.yml > "$TMP"
  containerlab deploy -t "$TMP"
  rm -f "$TMP"
else
  containerlab deploy -t topology.yml
fi
