# Security

The security roles are lab tooling and controls, not a claim of production
hardening.

## Implemented components

- `kube_bench` installs a pinned Debian package on every cluster node. Run
  checks with `ansible k8s_cluster -b -a "kube-bench run"`.
- `trivy` installs the Trivy CLI from the Aqua Security APT repository on
  every cluster node. A control-plane scan can be run with
  `sudo KUBECONFIG=/etc/kubernetes/admin.conf trivy k8s cluster --report summary`.
- `kyverno` installs the Kyverno Helm chart and applies two lab policies: an
  audit policy for restricted Pod Security Standards and an enforce policy for
  privileged containers outside selected system namespaces.
- `falco` installs as a DaemonSet through Helm and observes containerd-backed
  workloads. Falcosidekick is disabled in the role values.
- Pod Security Admission can be enabled with
  `-e enable_pod_security_admission=true`. The role writes admission
  configuration and modifies the kube-apiserver static-pod manifest, creating
  backups first. It is disabled by default.

## Planned hardening

The roadmap includes audit logging, etcd encryption at rest, seccomp profile
management, and broader CKS-related hardening and validation. These are not
currently implemented by numbered playbooks or separate roadmap files.

## Operational caveats

The Kyverno policies are explicitly lab policies, and kube-bench/Trivy provide
tools and reports rather than an automated security acceptance gate. The
security roles should be reviewed against the target Kubernetes version and
lab constraints before enabling them elsewhere.
