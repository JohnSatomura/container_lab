#!/bin/bash
set -e

# containerlab デプロイ（Linux bridge 不要・P2P リンクのみ）
containerlab deploy -t topology.yml
