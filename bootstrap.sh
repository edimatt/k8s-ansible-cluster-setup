#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

playbooks=(
  00-sudo-nopass.yml
  00-preflight.yml
  01-os-prep.yml
  02-firewall.yml
  03-containerd.yml
  04-kubernetes-packages.yml
  05-kubeadm-init.yml
  05-worker-join.yml
  06-single-node.yml
  07-helm.yml
  08-cilium-cli.yml
  09-cilium-platform.yml
  10-local-storage.yml
  11-metrics-server.yml
  12-validation.yml
  13-cert-manager.yml
  14-nginx-ingress-lab.yml
  # 15-monitoring.yml
  # 16-pod-security-admission.yml
  17-kube-bench.yml
  17-spark-operator.yml
)

default_cilium_lb_pool_blocks='[{"start":"192.168.1.80","stop":"192.168.1.89"}]'
cilium_lb_pool_blocks="${CILIUM_LB_POOL_BLOCKS:-$default_cilium_lb_pool_blocks}"
from_playbook=""
limit_pattern=""
syntax_check=false
ansible_mode=()
ansible_args=()
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT
cilium_extra_vars_file="${tmpdir}/cilium-extra-vars.json"

printf '{"cilium_lb_pool_blocks":%s}\n' "$cilium_lb_pool_blocks" > "$cilium_extra_vars_file"

limit_scope() {
  case "$limit_pattern" in
    "")
      printf 'all\n'
      ;;
    k8s_workers|k8s-worker-*|*":k8s_workers"|*"k8s_workers:"*|*":k8s-worker-"*)
      printf 'worker\n'
      ;;
    k8s_control_plane|k8s-control-*|*":k8s_control_plane"|*"k8s_control_plane:"*|*":k8s-control-"*)
      printf 'control_plane\n'
      ;;
    *)
      printf 'custom\n'
      ;;
  esac
}

usage() {
  printf '%s\n' \
    "Usage: ./bootstrap.sh [--from PLAYBOOK] [--limit HOST_OR_GROUP] [--check] [--syntax-check] [-- ANSIBLE_ARGS...]" \
    "" \
    "Examples:" \
    "  ./bootstrap.sh" \
    "  ./bootstrap.sh --limit k8s_control_plane" \
    "  ./bootstrap.sh --limit k8s-worker-01" \
    "  ./bootstrap.sh --from 09-cilium-platform.yml" \
    "  CILIUM_LB_POOL_BLOCKS='[{\"start\":\"192.168.1.80\",\"stop\":\"192.168.1.99\"}]' ./bootstrap.sh" \
    "  ./bootstrap.sh -- --tags some_tag"
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
    -l|--limit)
      if [[ $# -lt 2 ]]; then
        printf 'Missing value for --limit\n' >&2
        usage >&2
        exit 2
      fi
      limit_pattern="$2"
      ansible_args+=(--limit "$2")
      shift 2
      ;;
    --syntax-check)
      ansible_mode+=(--syntax-check)
      syntax_check=true
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
  scope="$(limit_scope)"

  if [[ "$syntax_check" == false ]]; then
    if [[ "$scope" == "control_plane" && "$playbook" == "05-worker-join.yml" ]]; then
      continue
    fi

    if [[ "$scope" == "worker" ]]; then
      case "$playbook" in
        00-sudo-nopass.yml|00-preflight.yml|01-os-prep.yml|02-firewall.yml|03-containerd.yml|04-kubernetes-packages.yml|05-worker-join.yml|17-kube-bench.yml)
          ;;
        *)
          continue
          ;;
      esac
    fi
  fi

  cmd=(ansible-playbook "${ansible_mode[@]}" "$playbook")

  if [[ "$playbook" == "09-cilium-platform.yml" ]]; then
    cmd+=(-e "@${cilium_extra_vars_file}")
  fi

  cmd+=("${ansible_args[@]}")

  printf '\n==> %s\n' "$playbook"
  "${cmd[@]}"

  if [[ "$playbook" == "17-kube-bench.yml" && "$scope" == "worker" && "$syntax_check" == false ]]; then
    break
  fi
done
