#!/bin/bash
set -e

# containerlab 停止・削除
containerlab destroy -t topology.yml

# 自動生成ディレクトリを削除（次回 deploy 時に startup-config が確実に反映されるようにする）
rm -rf clab-lab03-bgp/
