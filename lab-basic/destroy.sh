#!/bin/bash
set -e
cd "$(dirname "$0")"

if [ -f topology-full.yml ]; then
  containerlab destroy -t topology-full.yml
else
  containerlab destroy -t topology.yml
fi
rm -rf clab-lab-basic/ topology-full.yml
