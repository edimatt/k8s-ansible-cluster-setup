# Kubernetes Lab Bootstrap

This project uses Ansible to provision a two-node Kubernetes cluster on Ubuntu:
one control-plane node and one worker node. It automates the setup of the
container runtime and Kubernetes packages, initializes the cluster, joins the
worker, and installs core platform components such as Cilium, ingress, storage,
and security tooling.

It is a small, reproducible Kubernetes lab that demonstrates infrastructure
automation, cluster bootstrapping, and the deployment of common Kubernetes
platform services.

Run the main playbook from this directory. The inventory is configured in
`ansible.cfg` and points to `inventory/hosts.ini`.

Run the full bootstrap:

```bash
./bootstrap.sh
```

The first role is `sudo_nopass`. It checks whether passwordless sudo already
works. If not, it prompts for the sudo password, creates
`/etc/sudoers.d/<ssh-user>`, validates it with `visudo`, and then the bootstrap
continues.

After the first successful run, sudo passwordless is configured and future
bootstraps should not prompt for sudo.

To run only passwordless sudo, use its tag:

```bash
ansible-playbook site.yaml --tags sudo
```

This role prompts for the sudo password itself, without using Ansible
`become`.

## Inventory

The inventory currently defines one control-plane node and one worker node:

```ini
[k8s_control_plane]
k8s-control-01

[k8s_workers]
k8s-worker-01

[k8s_cluster:children]
k8s_control_plane
k8s_workers
```

When adding worker nodes, keep control-plane hosts in `k8s_control_plane` and
add workers under `k8s_workers`:

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

For a new cluster, bootstrap the control plane first:

```bash
./bootstrap.sh --limit k8s_control_plane
```

Then add worker hosts to `inventory/hosts.ini` under `k8s_workers` and bootstrap
them:

```bash
./bootstrap.sh --limit k8s_workers
```

Run the full bootstrap against every host in `k8s_cluster`:

```bash
./bootstrap.sh --limit k8s_cluster
```

Limit the bootstrap to one inventory group or host:

```bash
./bootstrap.sh --limit k8s_control_plane
./bootstrap.sh --limit k8s_cluster
./bootstrap.sh --limit k8s-worker-01
```

Run Ansible check mode through the bootstrap sequence:

```bash
./bootstrap.sh --check
```

The `sudo_nopass` role ends early in check mode because it bootstraps sudo with
raw commands.

Run a syntax check:

```bash
ansible-playbook --syntax-check site.yaml
```

`--limit` accepts any Ansible inventory host or group. Use `k8s_cluster` for the
parent group that contains both `k8s_control_plane` and `k8s_workers`.

The bootstrap passes a default Cilium LoadBalancer pool containing
`192.168.1.80` through `192.168.1.89`. Override it with the
`CILIUM_LB_POOL_BLOCKS` environment variable when that range is not available
on the lab network:

```bash
CILIUM_LB_POOL_BLOCKS='[{"start":"192.168.1.100","stop":"192.168.1.109"}]' \
  ./bootstrap.sh
```

The same value can be passed directly to the main playbook with
`-e/--extra-vars`. The pool must be reachable on the node LAN, and the
interface used by the L2 announcement policy defaults to `enp0s1`; override
`cilium_l2_interface_regex` if the nodes use another interface.

With `--limit k8s_control_plane`, only plays targeting the control plane run.
With `--limit k8s_workers` or a worker hostname, the worker preparation and
join roles run, while control-plane roles have no matching hosts.

Optional monitoring and Pod Security Admission are disabled by default. Enable
them explicitly:

```bash
ansible-playbook site.yaml -e enable_monitoring=true
ansible-playbook site.yaml -e enable_pod_security_admission=true
```

Use tags to run a focused part of the site:

```bash
ansible-playbook site.yaml --tags cilium
ansible-playbook site.yaml --tags security
ansible-playbook site.yaml --skip-tags optional
```

Pass other extra arguments directly to `ansible-playbook`. Everything after `--`
is forwarded unchanged:

```bash
./bootstrap.sh -- --tags some_tag
```

## Adding a Worker Node

Add the new host to the inventory under `k8s_workers`, then run the bootstrap
limited to that host:

```bash
./bootstrap.sh --limit k8s-worker-01
```

The bootstrap prepares the vanilla Ubuntu node, installs Kubernetes packages,
and the `kubeadm_worker` role joins it to the existing control plane. The join command
is generated automatically on the first host in `k8s_control_plane`.

## Container Runtime

The `containerd` role installs containerd with systemd cgroups and configures
`crictl` to use the containerd socket. It installs `cri-tools` from APT when
available; otherwise it downloads the pinned `crictl` `v1.35.0` archive for
`amd64` or `arm64` from the upstream Kubernetes cri-tools release.

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

## Roles and main playbook

`site.yaml` is the canonical entry point. It groups roles by lifecycle stage
and target host group: node preparation, control-plane initialization, worker
joining, platform services, and security tooling. Each role is under
`roles/<role-name>/` with its tasks, defaults, and handlers.

The numbered playbooks were intentionally removed so there is one source of
truth for orchestration. `bootstrap.sh` remains as a small convenience wrapper
for the main playbook and the Cilium LoadBalancer environment variable.

## Ingress And Monitoring

The `nginx_ingress` role installs the pinned ingress-nginx chart as a
`LoadBalancer` Service by default. It waits for an external address from
Cilium LoadBalancer IPAM/L2 and fails with a remediation message if no address
is assigned. For a lab that does not provide LoadBalancer addresses, use:

```bash
ansible-playbook site.yaml --tags ingress \
  -e nginx_ingress_service_type=NodePort
```

The role cleans up stale pending Helm releases and retries failed Helm
installations. The `monitoring` role applies the same stale-release cleanup and
retry behavior, waits up to 20 minutes for the kube-prometheus-stack release,
and gives Grafana startup, readiness, and liveness probes enough time for a
slow lab node to initialize.

Run monitoring separately when required:

```bash
ansible-playbook site.yaml --tags monitoring -e enable_monitoring=true
```

## Kube-bench

The `kube_bench` role installs the pinned kube-bench Debian package on every host
in `k8s_cluster`. Run checks on each node with Ansible:

```bash
ansible k8s_cluster -b -a "kube-bench run"
```

## Trivy

The `trivy` role installs the Trivy CLI from the official Aqua Security APT
repository on every host in `k8s_cluster`. Run a cluster scan from a
control-plane node with:

```bash
sudo KUBECONFIG=/etc/kubernetes/admin.conf trivy k8s cluster --report summary
```

## Kyverno

The `kyverno` role installs Kyverno with the official Helm chart on the control
plane and adds CKS lab policies: one policy audits Pods against the latest
restricted Pod Security Standards, and one simple enforce policy blocks
privileged containers outside system namespaces.

Inspect Kyverno and policy reports:

```bash
kubectl -n kyverno get pods
kubectl get clusterpolicies
kubectl get policyreports -A
```

## Falco

The `falco` role installs Falco with the official Falco Security Helm chart on the
control plane. The chart deploys Falco as a DaemonSet so runtime detection runs
on every node, which fits CKS practice for behavioral detection and incident
response.

Inspect Falco:

```bash
kubectl -n falco get pods -o wide
kubectl -n falco logs -l app.kubernetes.io/name=falco -c falco --tail=50
```

## Firewall

The `firewall` role configures UFW for this Kubernetes lab. It allows SSH, common
node ports, NodePort TCP/UDP, Cilium VXLAN, Cilium health/Hubble server,
ingress/Gateway HTTP and HTTPS, and node-exporter. Control plane ports are only
opened on `k8s_control_plane` hosts. Incoming traffic is denied by default;
outgoing, routed traffic, and UFW packet forwarding are allowed for pod and
service networking.

The control-plane-only firewall ports are `6443`, `2379-2380`, `10257`, and
`10259`. Common node ports include `10250`, `80`, `443`, `4240`, `4244`,
`8472/udp`, `9100`, and `30000-32767` TCP/UDP.

## Pod Security Admission

The `pod_security_admission` role configures the built-in Kubernetes Pod Security
Admission controller through the kube-apiserver static pod. Cluster defaults are
kept permissive with `enforce=privileged`, while `audit` and `warn` use the
`restricted` profile so violations are visible without breaking existing lab
workloads.

The role does not create permanent test namespaces.

## Common Commands

Run a single role by tag:

```bash
ansible-playbook site.yaml --tags ingress
```

Re-run Cilium platform networking:

```bash
ansible-playbook site.yaml --tags cilium \
  -e '{"cilium_lb_pool_blocks":[{"start":"192.168.1.80","stop":"192.168.1.89"}]}'
```

Syntax check:

```bash
ansible-playbook --syntax-check site.yaml
```

## CKS / Security Layer Roadmap

```text
roles/pod_security_admission
roles/kube_bench
roles/trivy
roles/kyverno
roles/falco
21-audit-logging.yml
22-etcd-encryption.yml
23-seccomp-profiles.yml
```
