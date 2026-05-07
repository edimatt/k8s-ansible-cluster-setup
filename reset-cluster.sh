#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

yes=false
ask_become_pass=false
ansible_args=()
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT
become_extra_vars_file="${tmpdir}/become-extra-vars.yml"

usage() {
  printf '%s\n' \
    "Usage: ./reset-cluster.sh [--yes] [-K|--ask-become-pass] [-- ANSIBLE_ARGS...]" \
    "" \
    "This resets Kubernetes cluster state on k8s_cluster hosts." \
    "It removes kubeadm state, CNI config, containerd runtime state, user kubeconfig, and local-path data." \
    "" \
    "Examples:" \
    "  ./reset-cluster.sh" \
    "  ./reset-cluster.sh -K" \
    "  ./reset-cluster.sh --yes" \
    "  ./reset-cluster.sh -- --limit k8s-control-01"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --yes|-y)
      yes=true
      shift
      ;;
    -K|--ask-become-pass)
      ask_become_pass=true
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

if [[ "$ask_become_pass" == true ]]; then
  if [[ -z "${ANSIBLE_BECOME_PASSWORD:-}" ]]; then
    printf '%s' 'BECOME password: '
    read -r -s become_password
    printf '\n'
  else
    become_password="$ANSIBLE_BECOME_PASSWORD"
  fi

  {
    printf 'ansible_become_password: |-\n'
    printf '  %s\n' "$become_password"
  } > "$become_extra_vars_file"
  chmod 600 "$become_extra_vars_file"
  unset become_password

  ansible_args+=(-e "@${become_extra_vars_file}")
fi

ansible-playbook reset-cluster.yml "${ansible_args[@]}"
