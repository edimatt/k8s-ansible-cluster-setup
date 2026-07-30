#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

default_cilium_lb_pool_blocks='[{"start":"192.168.125.80","stop":"192.168.125.89"}]'
cilium_lb_pool_blocks="${CILIUM_LB_POOL_BLOCKS:-$default_cilium_lb_pool_blocks}"

exec ansible-playbook site.yaml \
  -e "{\"cilium_lb_pool_blocks\":${cilium_lb_pool_blocks}}" \
  "$@"
