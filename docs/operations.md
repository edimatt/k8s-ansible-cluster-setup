# Operations

These commands operate the lab cluster configured by `site.yaml`.

## Reset and re-bootstrap

`reset-cluster.sh` is destructive to cluster state on the selected hosts. It
removes kubeadm state, Kubernetes and CNI paths, the user kubeconfig,
containerd runtime state, Cilium links, and local-path data. It does not manage
the underlying libvirt VMs.

```bash
./reset-cluster.sh
./bootstrap.sh
```

Use `--yes` for a non-interactive reset, `-K` or `--ask-become-pass` when sudo
requires a password, and pass Ansible arguments after `--`:

```bash
./reset-cluster.sh --yes
./reset-cluster.sh -K
./reset-cluster.sh -- --limit k8s-control-01
```

The reset playbook has a fixed `kube_user` default of `edoardo` for removing
that user's kubeconfig. Override it if the lab user differs.

## Check mode, limits, and tags

`site.yaml` supports normal Ansible check mode, inventory limits, tags, and
extra vars. The `sudo_nopass` role ends its play early in check mode because its
initial setup uses raw commands and a password prompt.

```bash
ansible-playbook site.yaml --syntax-check
./bootstrap.sh --check
./bootstrap.sh --limit k8s_control_plane
./bootstrap.sh --limit k8s-worker-01
ansible-playbook site.yaml --tags cilium
ansible-playbook site.yaml --tags security
ansible-playbook site.yaml --skip-tags optional
```

`--limit` can select any inventory host or group. `k8s_cluster` selects both
the control plane and workers. `bootstrap.sh` handles its own convenience
options only through the shell environment and forwards all command-line
arguments directly to `ansible-playbook`.

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
ansible-playbook site.yaml --syntax-check
ansible k8s_cluster -b -a "kube-bench run"
sudo KUBECONFIG=/etc/kubernetes/admin.conf trivy k8s cluster --report summary
kubectl get nodes -o wide
kubectl get pods -A -o wide
cilium status
```

Run cluster commands on the control plane with the kubeconfig created for the
configured `kube_user`, or set `KUBECONFIG=/etc/kubernetes/admin.conf` when
using root.
