# Operations

These commands operate the lab cluster configured by `site.yaml`.

Run `just` or `just help` for the minimal project workflow. Arguments after
`--` are forwarded to `ansible-playbook`; use Ansible's plural `--tags` option
to run the `bootstrap`, `platform`, or `security` phase. `bootstrap` only
prepares the hosts and installs Kubernetes packages. `platform` initializes
the control plane, joins workers, and installs the platform services. The
`optional` phase installs Spark by default; monitoring in that phase only runs
when `enable_monitoring=true` is passed as an extra variable.

## Reset and re-bootstrap

`just reset` is destructive to cluster state on the selected hosts. It
removes kubeadm state, Kubernetes and CNI paths, the user kubeconfig,
containerd runtime state, Cilium links, and local-path data. It does not manage
the underlying libvirt VMs.

```bash
just reset
just bootstrap
```

Use `reset-force` for a non-interactive reset. Pass Ansible arguments after
`--`, including `-K` or `--ask-become-pass` when sudo requires a password:

```bash
just reset-force
just reset -- -K
just reset -- --limit k8s-control-01
```

The reset playbook has a fixed `kube_user` default of `edoardo` for removing
that user's kubeconfig. Override it if the lab user differs.

## Check mode, limits, and tags

`site.yaml` supports normal Ansible check mode, inventory limits, tags, and
extra vars. The `sudo_nopass` role ends its play early in check mode because its
initial setup uses raw commands and a password prompt.

```bash
ansible-playbook site.yaml --syntax-check
just bootstrap -- --check
just bootstrap -- --limit k8s_control_plane
just bootstrap -- --limit k8s-worker-01
ansible-playbook site.yaml --tags cilium
ansible-playbook site.yaml --tags security
ansible-playbook site.yaml --skip-tags optional
```

`--limit` can select any inventory host or group. `k8s_cluster` selects both
the control plane and workers. The `bootstrap` recipe handles its convenience
option through the shell environment and forwards all arguments after `--`
directly to `ansible-playbook`.

## Helm retries and cleanup

The ingress-nginx and monitoring roles inspect their current Helm release,
remove stale pending or failed releases, and retry installation when the Helm
command fails. Monitoring uses a 20-minute Helm timeout. The ingress role waits
for the controller and, with a `LoadBalancer` service, for an external address.

Run monitoring separately when it is enabled:

```bash
ansible-playbook site.yaml --tags monitoring -e enable_monitoring=true
```

## Common commands

```bash
just
just check
ansible k8s_cluster -b -a "kube-bench run"
sudo KUBECONFIG=/etc/kubernetes/admin.conf trivy k8s cluster --report summary
kubectl get nodes -o wide
kubectl get pods -A -o wide
cilium status
```

Run cluster commands on the control plane with the kubeconfig created for the
configured `kube_user`, or set `KUBECONFIG=/etc/kubernetes/admin.conf` when
using root.
