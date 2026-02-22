#!/bin/bash
set -e
cd "$(dirname "$0")"

containerlab destroy -t topology.yml
rm -rf clab-lab01-basic/
