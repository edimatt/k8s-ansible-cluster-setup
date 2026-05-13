# Kubernetes Lab Bootstrap

Run the playbooks from this directory. The inventory is configured in
`ansible.cfg` and points to `inventory/hosts.ini`.

Run the full bootstrap:

```bash
./bootstrap.sh
```

The first playbook is `00-sudo-nopass.yml`. It checks whether passwordless sudo
already works. If not, it prompts for the sudo password, creates
`/etc/sudoers.d/<ssh-user>`, validates it with `visudo`, and then the bootstrap
continues.

After the first successful run, sudo passwordless is configured and future
bootstraps should not prompt for sudo.

To configure only passwordless sudo and stop there, run:

```bash
ansible-playbook 00-sudo-nopass.yml
```

This playbook prompts for the sudo password itself, without using Ansible
`become`.

## Inventory

The inventory currently defines a single control-plane node:

```ini
[k8s_control_plane]
k8s-control-01

[k8s_cluster:children]
k8s_control_plane
```

When adding worker nodes, keep control-plane hosts in `k8s_control_plane` and
add a worker group under `k8s_cluster`:

```ini
[k8s_control_plane]
k8s-control-01

[k8s_workers]
k8s-worker-01
k8s-worker-02

[k8s_cluster:children]
k8s_control_plane
k8s_workers
```

## Bootstrap

Run the full bootstrap:

```bash
./bootstrap.sh
```

Resume from a specific playbook:

```bash
./bootstrap.sh --from 09-cilium-platform.yml
```

Run Ansible check mode through the bootstrap sequence:

```bash
./bootstrap.sh --check
```

`00-sudo-nopass.yml` is skipped in check mode because it bootstraps sudo with
raw commands.

Run syntax checks through the bootstrap sequence:

```bash
./bootstrap.sh --syntax-check
```

Pass extra arguments directly to `ansible-playbook`. Everything after `--` is
forwarded unchanged. For example, `--limit` runs the bootstrap only on matching
inventory hosts or groups:

```bash
./bootstrap.sh -- --limit k8s_control_plane
```

## Reset

Reset the cluster before a fresh bootstrap:

```bash
./reset-cluster.sh
./bootstrap.sh
```

Non-interactive reset:

```bash
./reset-cluster.sh --yes
```

Reset when sudo on the target requires a password:

```bash
./reset-cluster.sh -K
```

## Bootstrap Order

```bash
ansible-playbook 00-sudo-nopass.yml
ansible-playbook 00-preflight.yml
ansible-playbook 01-os-prep.yml
ansible-playbook 02-firewall.yml
ansible-playbook 03-containerd.yml
ansible-playbook 04-kubernetes-packages.yml
ansible-playbook 05-kubeadm-init.yml
ansible-playbook 06-single-node.yml
ansible-playbook 07-helm.yml
ansible-playbook 08-cilium-cli.yml
ansible-playbook 09-cilium-platform.yml \
  -e '{"cilium_lb_pool_blocks":[{"start":"192.168.1.80","stop":"192.168.1.89"}]}'
ansible-playbook 10-local-storage.yml
ansible-playbook 11-metrics-server.yml
ansible-playbook 12-validation.yml
ansible-playbook 13-cert-manager.yml
ansible-playbook 14-nginx-ingress-lab.yml
# ansible-playbook 15-monitoring.yml
# ansible-playbook 16-pod-security-admission.yml
```

## Firewall

`02-firewall.yml` configures UFW for this Kubernetes lab. It allows SSH, common
node ports, NodePort TCP/UDP, Cilium VXLAN, Cilium health/Hubble server,
ingress/Gateway HTTP and HTTPS, and node-exporter. Control plane ports are only
opened on `k8s_control_plane` hosts. Incoming traffic is denied by default;
outgoing, routed traffic, and UFW packet forwarding are allowed for pod and
service networking.

The control-plane-only firewall ports are `6443`, `2379-2380`, `10257`, and
`10259`. Common node ports include `10250`, `80`, `443`, `4240`, `4244`,
`8472/udp`, `9100`, and `30000-32767` TCP/UDP.

## Pod Security Admission

`16-pod-security-admission.yml` configures the built-in Kubernetes Pod Security
Admission controller through the kube-apiserver static pod. Cluster defaults are
kept permissive with `enforce=privileged`, while `audit` and `warn` use the
`restricted` profile so violations are visible without breaking existing lab
workloads.

The playbook does not create permanent test namespaces.

## Common Commands

Re-run a single playbook:

```bash
ansible-playbook <playbook>.yml
```

Re-run Cilium platform networking:

```bash
ansible-playbook 09-cilium-platform.yml \
  -e '{"cilium_lb_pool_blocks":[{"start":"192.168.1.80","stop":"192.168.1.89"}]}'
```

Syntax check:

```bash
ansible-playbook --syntax-check <playbook>.yml
```

## CKS / Security Layer Roadmap

```text
16-pod-security-admission.yml
17-kube-bench.yml
18-trivy.yml
19-kyverno.yml
20-falco.yml
21-audit-logging.yml
22-etcd-encryption.yml
23-seccomp-profiles.yml
```
