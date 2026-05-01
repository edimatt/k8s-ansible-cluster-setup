#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

playbooks=(
  00-preflight.yml
  01-os-prep.yml
  02-containerd.yml
  03-kubernetes-packages.yml
  04-kubeadm-init.yml
  05-single-node.yml
  06-helm.yml
  07-cilium-cli.yml
  08-cilium-platform.yml
  09-local-storage.yml
  10-metrics-server.yml
  11-validation.yml
  12-cert-manager.yml
)

# 13-monitoring.yml

default_cilium_lb_pool_blocks='[{"start":"192.168.1.80","stop":"192.168.1.89"}]'
cilium_lb_pool_blocks="${CILIUM_LB_POOL_BLOCKS:-$default_cilium_lb_pool_blocks}"
from_playbook=""
ansible_mode=()
ansible_args=()
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT
cilium_extra_vars_file="${tmpdir}/cilium-extra-vars.json"

printf '{"cilium_lb_pool_blocks":%s}\n' "$cilium_lb_pool_blocks" > "$cilium_extra_vars_file"

usage() {
  printf '%s\n' \
    "Usage: ./bootstrap.sh [--from PLAYBOOK] [--check] [--syntax-check] [-- ANSIBLE_ARGS...]" \
    "" \
    "Examples:" \
    "  ./bootstrap.sh" \
    "  ./bootstrap.sh --from 08-cilium-platform.yml" \
    "  CILIUM_LB_POOL_BLOCKS='[{\"start\":\"192.168.1.80\",\"stop\":\"192.168.1.99\"}]' ./bootstrap.sh" \
    "  ./bootstrap.sh -- --limit k8s_control_plane"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --from)
      if [[ $# -lt 2 ]]; then
        printf 'Missing value for --from\n' >&2
        usage >&2
        exit 2
      fi
      from_playbook="$2"
      shift 2
      ;;
    --check)
      ansible_mode+=(--check)
      shift
      ;;
    --syntax-check)
      ansible_mode+=(--syntax-check)
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      ansible_args+=("$@")
      break
      ;;
    *)
      printf 'Unknown option: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

start_index=0
if [[ -n "$from_playbook" ]]; then
  found=false
  for index in "${!playbooks[@]}"; do
    if [[ "${playbooks[$index]}" == "$from_playbook" ]]; then
      start_index="$index"
      found=true
      break
    fi
  done

  if [[ "$found" == false ]]; then
    printf 'Unknown playbook for --from: %s\n' "$from_playbook" >&2
    exit 2
  fi
fi

for index in "${!playbooks[@]}"; do
  if (( index < start_index )); then
    continue
  fi

  playbook="${playbooks[$index]}"
  cmd=(ansible-playbook "${ansible_mode[@]}" "$playbook")

  if [[ "$playbook" == "08-cilium-platform.yml" ]]; then
    cmd+=(-e "@${cilium_extra_vars_file}")
  fi

  cmd+=("${ansible_args[@]}")

  printf '\n==> %s\n' "$playbook"
  "${cmd[@]}"
done
