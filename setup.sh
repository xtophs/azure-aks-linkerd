#!/bin/bash

set -e

export RG="xtoph-aks-linkerd-11"
export LOCATION=eastus

./scripts/setup-cluster.sh
./scripts/setup-linkerd.sh
./scripts/setup-canary.sh

