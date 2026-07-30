# Kubernetes Lab Bootstrap

[![Ansible CI](https://github.com/edimatt/k8s-ansible-cluster-setup/actions/workflows/ansible-ci.yml/badge.svg?branch=main)](https://github.com/edimatt/k8s-ansible-cluster-setup/actions/workflows/ansible-ci.yml)

This personal homelab project uses Ansible to configure SSH-ready Ubuntu nodes
and bootstrap a Kubernetes cluster. The current inventory describes one
control-plane node and one worker node. The automation prepares the operating
system, installs containerd and Kubernetes packages, initializes the control
plane, joins workers, and installs platform and security components.

It is a lab environment and portfolio project. It is not presented as a
production-ready cluster or as a generic reusable Ansible collection.

## Project status

| Status | Scope |
| --- | --- |
| Implemented | SSH-based node preparation, containerd, Kubernetes packages, kubeadm control-plane bootstrap, worker joining, Cilium networking and L2 LoadBalancer IPAM, Gateway API CRDs (`v1.4.1`), ingress-nginx, local-path storage, Metrics Server, cert-manager, Kyverno, Falco, kube-bench, Trivy, and basic validation output. |
| Optional | kube-prometheus-stack monitoring, Pod Security Admission, and Spark Operator. Monitoring and PSA are disabled by default; Spark Operator is tagged optional but has no `when` gate. |
| Planned | A broader automated validation contract, stronger lifecycle/idempotency coverage, and additional security hardening such as audit logging, etcd encryption at rest, seccomp profile management, and CKS-related improvements. |

## Architecture

[k8s-terraform-cluster-setup](https://github.com/edimatt/k8s-terraform-cluster-setup)
is the external producer of the nodes. This repository starts after those
nodes have completed first boot and are
reachable over SSH.

```text
k8s-terraform-cluster-setup
  libvirt VMs and cloud-init
          |
          v
SSH-ready Ubuntu nodes
          |
          v
common node preparation
          |
          v
containerd and Kubernetes packages
          |
          v
kubeadm control plane
          |
          v
worker join
          |
          v
Cilium networking
          |
          v
ingress, storage and optional monitoring
          |
          v
security controls
          |
          v
validation
```

## Project boundary

The `k8s-terraform-cluster-setup` repository owns the infrastructure that
produces the nodes:

- libvirt storage and network attachment
- Ubuntu VM lifecycle
- cloud-image and copy-on-write disk provisioning
- cloud-init first boot
- stable node identity
- SSH-ready infrastructure

This repository owns the cluster configuration after SSH is available:

- Ansible inventory
- node operating-system configuration
- container runtime
- Kubernetes packages
- kubeadm control-plane bootstrap
- worker-node joining
- CNI and platform add-ons
- monitoring and security controls
- cluster validation

Ansible does not create or destroy the libvirt VMs.

## Quick start

Run commands from the repository root. The inventory is configured by
`ansible.cfg` and defaults to `inventory/hosts.ini`.

The canonical orchestration entry point is `site.yaml`. `bootstrap.sh` is a
convenience wrapper around that same playbook. It supplies
the lab's default Cilium LoadBalancer pool and forwards its arguments to
`ansible-playbook`; `site.yaml` remains the source of truth for orchestration.

```bash
./bootstrap.sh
```

On the first run, `sudo_nopass` may prompt for the SSH user's sudo password,
validate a sudoers file with `visudo`, and configure passwordless sudo. It does
not use Ansible `become` for that initial sudo setup. The role is skipped early
in check mode.

For a new cluster, target the control plane first and then the workers:

```bash
./bootstrap.sh --limit k8s_control_plane
```

Use `--limit` with any inventory host or group. Arguments are passed unchanged
to `ansible-playbook`:

```bash
./bootstrap.sh --tags cilium
```

The numbered playbooks were intentionally removed. There is one orchestration
entry point, `site.yaml`; do not add numbered orchestration playbooks.

Detailed reset, check-mode, limit, tag, argument-forwarding, and Helm
operational guidance is in [docs/operations.md](docs/operations.md).

## Inventory

The current lab inventory is:

```ini
[k8s_control_plane]
k8s-control-01

[k8s_workers]
k8s-worker-01

[k8s_cluster:children]
k8s_control_plane
k8s_workers
```

Add workers under `k8s_workers`. The first host in `k8s_control_plane` is used
as the control-plane host for generating the worker join command.

The inventory is static and contains the author's current lab hostnames. They
are defaults for this repository, not portable names supplied by Terraform.

## Main configuration

Non-secret defaults are intentionally lab-specific:

- Cilium LoadBalancer pool: `192.168.124.80` through `192.168.124.89`
- Cilium L2 announcement interface: `enp1s0` via `cilium_l2_interface_regex: "^enp1s0$"`
- kubeadm pod network CIDR: `10.244.0.0/16`
- control-plane user for the kubeconfig: `edoardo`
- local-path storage root: `/opt/local-path-provisioner`
- control-plane taint: always removed by the `single_node` role so workloads
  can run on the control-plane node in this lab
- monitoring: disabled by default
- Pod Security Admission: disabled by default

The Cilium pool is passed by `bootstrap.sh` from
`CILIUM_LB_POOL_BLOCKS`, or can be supplied directly as an extra variable:

```bash
CILIUM_LB_POOL_BLOCKS='[{"start":"192.168.1.100","stop":"192.168.1.109"}]' \
  ./bootstrap.sh
```

The pool must be reachable on the node LAN. Override the interface selection
with `-e cilium_l2_interface_regex='^enp0s1$'` (or the interface used by the
nodes). Other role defaults can be overridden with Ansible extra vars or
inventory/group variables.

Enable optional components explicitly where applicable:

```bash
ansible-playbook site.yaml -e enable_monitoring=true
ansible-playbook site.yaml -e enable_pod_security_admission=true
ansible-playbook site.yaml --tags spark
```

## What gets installed

| Lifecycle or purpose | Implemented components |
| --- | --- |
| Node preparation | Passwordless sudo bootstrap, preflight facts, swap disablement, kernel modules and sysctl settings, base packages, locale, chrony, sysstat, and UFW rules. |
| Kubernetes core | containerd with systemd cgroups, `crictl`, `nerdctl`, Helm, `kubelet`, `kubeadm`, `kubectl`, kubeadm control-plane initialization, worker joining, and removal of the control-plane taint for lab workloads. |
| Networking | Cilium with kube-proxy replacement, Hubble Relay, L2 announcements, Cilium LoadBalancer IPAM, Gateway API CRDs (`v1.4.1`), and the Cilium GatewayClass. |
| Ingress and storage | ingress-nginx (LoadBalancer by default, NodePort override), cert-manager, and Rancher local-path provisioner with the `local-path` StorageClass as default. |
| Observability | Metrics Server by default. kube-prometheus-stack monitoring is optional and disabled by default. |
| Security | kube-bench and Trivy on cluster nodes; Kyverno with lab policies; Falco as a DaemonSet; optional Pod Security Admission configuration on the control plane. |
| Optional platform | Spark Operator and its lab RBAC checks. |

See [docs/networking.md](docs/networking.md) for LoadBalancer, L2, interface,
NodePort, firewall, and port details. See [docs/security.md](docs/security.md)
for security component behavior and planned hardening.

## Validation

Validation currently implemented in the roles includes:

- Cilium waits for its operator and agent rollouts, reports healthy Cilium
  status, and waits for the node and CoreDNS rollout.
- The `validation` role prints `kubectl get nodes`, all pod status, and
  `cilium status --wait=false`. It also creates a temporary echo Deployment
  and `LoadBalancer` Service, waits for Cilium to allocate an IP, and curls
  that IP from the Ansible controller to verify LAN-side L2 advertisement.
- Platform roles wait for relevant rollouts or resources, including the
  Cilium GatewayClass, ingress controller, local-path provisioner and
  StorageClass, Metrics APIService, cert-manager resources, and security or
  optional component deployments where those roles run.
- ingress-nginx requires a LoadBalancer address when its service type is
  `LoadBalancer`.
- Spark Operator checks its Helm release, pods, CRDs, API resources, and lab
  service-account permissions.

The repository does not yet implement a single end-to-end validation contract
for all of the following. These remain planned validation work:

- every node reports `Ready`
- Cilium is healthy
- CoreDNS resolves and serves cluster DNS
- a test workload can be scheduled
- pod-to-pod networking works
- ingress receives an address and serves a test request
- a persistent volume claim binds and can be used
- required security components are running and usable

The current role output is useful for a lab run, but it is not a complete
automated acceptance test.

## Known limitations

- The inventory is static and currently describes one control-plane node and
  one worker.
- The cluster has a single control-plane node; control-plane high availability
  is not implemented.
- Cilium's address pool and interface selection assume the author's LAN unless
  overridden.
- The local-path provisioner uses node-local storage under
  `/opt/local-path-provisioner`; it is not replicated storage.
- The project is run locally from an operator machine over SSH. Terraform and
  libvirt provisioning are outside this repository.
- Monitoring and Pod Security Admission are opt-in. Spark Operator is exposed
  through an optional tag but is not disabled by a variable in `site.yaml`.
- Validation is partly role-local and observational; complete end-to-end
  validation is not implemented.
- Several Helm chart versions are currently unpinned, including Kyverno, Falco,
  Metrics Server, and Spark Operator.
- The automation downloads packages, binaries, charts, and manifests from
  external repositories during execution.
- The monitoring role contains a lab default Grafana password and is not a
  production credential-management design.

## Repository layout

```text
site.yaml                 canonical orchestration entry point
bootstrap.sh              convenience wrapper and Cilium pool override
reset-cluster.yml         reset playbook
reset-cluster.sh          reset convenience wrapper
ansible.cfg               inventory and Ansible defaults
inventory/hosts.ini       static lab inventory
group_vars/all.yml        optional component defaults
roles/                    node, cluster, platform, security, and validation roles
docs/                     focused operational, networking, and security notes
```

Roles are grouped by what they configure rather than by numbered playbooks.
The play order and host targeting are defined in `site.yaml`.

## Roadmap

### Cluster lifecycle and idempotency

- Improve repeat-run behavior and make the full lifecycle predictable after
  partial failures.
- Add clearer lifecycle handling for reset, re-bootstrap, and worker changes.
- Continue replacing command-based Helm edge cases with stricter desired-state
  checks where useful.

### Automated validation

- Add the end-to-end validation contract described above.
- Add disposable test workloads for scheduling, pod networking, ingress, and
  persistent storage.
- Make validation results explicit and fail the run when required components
  are not usable.

### Security hardening

- Audit logging.
- etcd encryption at rest.
- Seccomp profile management.
- Extend CKS-related hardening and validation around PSA, Kyverno, Falco,
  kube-bench, and Trivy.

### CI and quality gates

- Extend linting coverage to all roles and supporting YAML files.
- Add a test or disposable-lab gate for the validation contract.

The existing Ansible CI workflow checks top-level YAML, Ansible syntax and
inventory parsing, runs Ansible lint on the orchestration playbooks, and checks
the shell scripts with ShellCheck. A safe Ubuntu preflight smoke test is also
available through manual workflow dispatch.

## Related repository

[`k8s-terraform-cluster-setup`](https://github.com/edimatt/k8s-terraform-cluster-setup)
owns the libvirt VM lifecycle and produces the SSH-ready Ubuntu nodes consumed
here.
