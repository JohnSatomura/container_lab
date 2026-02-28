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
rm -rf clab-lab-bgp/ topology-full.yml
