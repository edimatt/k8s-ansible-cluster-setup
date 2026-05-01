#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

yes=false
ansible_args=()

usage() {
  printf '%s\n' \
    "Usage: ./reset-cluster.sh [--yes] [-- ANSIBLE_ARGS...]" \
    "" \
    "This resets Kubernetes cluster state on k8s_cluster hosts." \
    "It removes kubeadm state, CNI config, containerd runtime state, user kubeconfig, and local-path data." \
    "" \
    "Examples:" \
    "  ./reset-cluster.sh" \
    "  ./reset-cluster.sh --yes" \
    "  ./reset-cluster.sh -- --limit k8s-control-01"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --yes|-y)
      yes=true
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

if [[ "$yes" != true ]]; then
  printf '%s\n' "This will reset Kubernetes cluster state and delete local-path data."
  printf '%s' "Type RESET to continue: "
  read -r confirmation

  if [[ "$confirmation" != "RESET" ]]; then
    printf '%s\n' "Aborted."
    exit 1
  fi
fi

ansible-playbook reset-cluster.yml "${ansible_args[@]}"
