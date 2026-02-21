#!/bin/bash
set -e

containerlab destroy -t topology.yml
rm -rf clab-lab01-basic/
