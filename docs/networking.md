# Networking

## Cilium and LoadBalancer IPAM

The Cilium role enables kube-proxy replacement, L2 announcements, Gateway API,
and Hubble Relay. It creates a Cilium LoadBalancer IP pool named `lan-pool`.
The convenience wrapper supplies the author's lab default pool:
`192.168.124.80`–`192.168.124.89`.

Override the pool with:

```bash
CILIUM_LB_POOL_BLOCKS='[{"start":"192.168.1.100","stop":"192.168.1.109"}]' \
  ./bootstrap.sh
```

The addresses must be available and reachable on the node LAN. The same value
can be passed as `-e cilium_lb_pool_blocks=...` directly to Ansible.

## L2 announcements and interface selection

The current role default selects `enp1s0` using
`cilium_l2_interface_regex: "^enp1s0$"`. Override it when the SSH-ready nodes
use another interface:

```bash
ansible-playbook site.yaml -e "cilium_l2_interface_regex=^enp0s1$"
```

The role prints available interfaces before applying the Cilium L2 policy.

## Ingress and NodePort fallback

ingress-nginx is installed as a `LoadBalancer` Service by default. With Cilium
IPAM and L2 announcements configured, the role waits for and requires an
external address. If the lab LAN cannot provide LoadBalancer addresses, use
NodePort:

```bash
ansible-playbook site.yaml --tags ingress \
  -e nginx_ingress_service_type=NodePort
```

## Firewall and ports

The firewall role installs and enables UFW, allows SSH, permits routed pod and
Service traffic, and configures these broad lab rules:

- TCP: `80`, `443`, `10250`, `30000:32767`; control-plane hosts also expose
  `6443`, `2379:2380`, `10257`, and `10259`.
- UDP: `8472` for Cilium VXLAN and `30000:32767` for NodePort Services.
- TCP `4240` and `4244` for Cilium health and Hubble, and TCP `9100` for the
  monitoring node exporter.
- ICMP/ICMPv6 echo handling required by the configured firewall rules.

These rules are sized for this lab topology and should be reviewed before
using the roles on a different network.
