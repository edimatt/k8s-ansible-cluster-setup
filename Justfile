set positional-arguments

default: help

# Show the minimal project workflow.
help:
    @printf '%s\n' \
        'Minimal workflow:' \
        '  just check                              # Lint and validate the project' \
        '  just bootstrap -- --tags bootstrap     # Prepare hosts and install Kubernetes packages' \
        '  just bootstrap -- --tags platform      # Create the cluster and install platform services' \
        '  just bootstrap -- --tags security      # Install cluster security tooling' \
        '' \
        'Optional components:' \
        '  just bootstrap -- --tags optional      # Install Spark; monitoring stays disabled' \
        '  just bootstrap -- --tags optional -e enable_monitoring=true  # Install Spark and monitoring' \
        '  just bootstrap -- --tags psa -e enable_pod_security_admission=true  # Enable optional PSA controls' \
        '' \
        'Reset and rebuild:' \
        '  just reset                              # Confirm and remove cluster state' \
        '  just bootstrap -- --tags bootstrap     # Start the workflow again'

# Bootstrap the cluster, forwarding arguments to ansible-playbook.
bootstrap *ansible_args:
    #!/usr/bin/env bash
    set -euo pipefail

    default_cilium_lb_pool_blocks='[{"start":"192.168.125.80","stop":"192.168.125.89"}]'
    cilium_lb_pool_blocks="${CILIUM_LB_POOL_BLOCKS:-$default_cilium_lb_pool_blocks}"

    if [[ "${1:-}" == "--" ]]; then
        shift
    fi

    exec ansible-playbook site.yaml \
        -e "{\"cilium_lb_pool_blocks\":${cilium_lb_pool_blocks}}" \
        "$@"

# Reset cluster state after an interactive confirmation.
reset *ansible_args:
    #!/usr/bin/env bash
    set -euo pipefail

    printf '%s\n' "This will reset Kubernetes cluster state and delete local-path data."
    printf '%s' "Type RESET to continue: "
    read -r confirmation

    if [[ "$confirmation" != "RESET" ]]; then
        printf '%s\n' "Aborted."
        exit 1
    fi

    if [[ "${1:-}" == "--" ]]; then
        shift
    fi

    exec ansible-playbook reset-cluster.yml "$@"

# Reset cluster state without prompting.
reset-force *ansible_args:
    #!/usr/bin/env bash
    set -euo pipefail

    if [[ "${1:-}" == "--" ]]; then
        shift
    fi

    exec ansible-playbook reset-cluster.yml "$@"

# Run all local static checks.
check: lint syntax-check

# Lint the top-level Ansible files.
lint:
    yamllint --config-data '{extends: default, rules: {line-length: {max: 200}, truthy: {check-keys: false}}}' site.yaml reset-cluster.yml group_vars/all.yml .github/workflows/ansible-ci.yml
    ansible-lint --exclude roles site.yaml reset-cluster.yml

# Validate the inventory and playbook syntax.
syntax-check:
    ansible-inventory --graph
    ansible-playbook site.yaml --syntax-check
    ansible-playbook reset-cluster.yml --syntax-check
