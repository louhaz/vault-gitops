# HashiCorp Vault GitOps Infrastructure

This repository contains the HashiCorp Vault infrastructure deployment for Kubernetes/OpenShift using GitOps principles with ArgoCD.

## Overview

This repository provides a reusable Vault infrastructure that can be consumed by multiple applications. It deploys:

- **Vault Server**: HashiCorp Vault using the official Helm chart
- **Vault Namespace**: Dedicated `vault` namespace for Vault components
- **Vault Operators**: Vault Secrets Operator for secret synchronization
- **RBAC**: Cluster-level RBAC for Vault authentication and token review

## Architecture

```
vault-gitops/
├── argocd/                    # ArgoCD Applications
│   ├── vault-namespace.yaml   # Creates vault namespace (sync-wave: 10)
│   ├── vault-common.yaml      # Common RBAC (sync-wave: 20)
│   └── vault.yaml             # Vault Helm deployment (sync-wave: 30)
├── components/
│   ├── vault-namespace/       # Namespace and OperatorGroup
│   ├── vault-common/          # ServiceAccount and ClusterRole
│   └── operators/vault/       # Vault Secrets Operator subscription
├── scripts/                   # Vault management scripts
└── VAULT_INTEGRATION.md       # Detailed integration guide
```

## Prerequisites

- Kubernetes 1.20+ or OpenShift 4.x
- ArgoCD or Red Hat OpenShift GitOps installed
- Cluster admin access for operator installation

## Quick Start

### 1. Deploy Vault Infrastructure

Apply the ArgoCD applications to deploy Vault:

```bash
kubectl apply -f argocd/vault-namespace.yaml
kubectl apply -f argocd/vault-common.yaml
kubectl apply -f argocd/vault.yaml
```

### 2. Wait for Vault to be Ready

```bash
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=vault -n vault --timeout=300s
```

### 3. Initialize and Unseal Vault

```bash
# Port-forward to Vault
kubectl port-forward -n vault svc/vault 8200:8200 &

# Initialize Vault (save the output securely!)
vault operator init -key-shares=5 -key-threshold=3

# Unseal Vault (repeat 3 times with different keys)
vault operator unseal <unseal-key-1>
vault operator unseal <unseal-key-2>
vault operator unseal <unseal-key-3>
```

### 4. Configure Kubernetes Authentication

```bash
./scripts/configure-vault-kubernetes-auth.sh
```

## Application Integration

Applications in other repositories can consume this Vault infrastructure by:

1. Creating a `VaultConnection` pointing to `http://vault.vault.svc.cluster.local:8200`
2. Creating a `VaultAuth` with Kubernetes authentication
3. Creating `VaultStaticSecret` resources to sync secrets

Example application configuration (in your app repository):

```yaml
apiVersion: secrets.hashicorp.com/v1beta1
kind: VaultConnection
metadata:
  name: vault-connection
  namespace: my-app
spec:
  address: http://vault.vault.svc.cluster.local:8200
  skipTLSVerify: true
---
apiVersion: secrets.hashicorp.com/v1beta1
kind: VaultAuth
metadata:
  name: my-app-auth
  namespace: my-app
spec:
  vaultConnectionRef: vault-connection
  method: kubernetes
  mount: kubernetes
  kubernetes:
    role: my-app-role
    serviceAccount: my-app-sa
```

## Components

### Vault Server

- **Deployment**: Helm chart from HashiCorp (v0.32.0)
- **Version**: Vault 1.21.2
- **Storage**: File-based storage with 10Gi PVC
- **UI**: Enabled and accessible via ClusterIP service
- **TLS**: Disabled (for internal cluster communication)

### Vault Secrets Operator

- **Purpose**: Syncs secrets from Vault to Kubernetes secrets
- **Namespace**: Installed in `openshift-operators`
- **Channel**: stable

### RBAC

- **ServiceAccount**: `vault-sa` in `vault` namespace
- **ClusterRole**: `vault-auth-delegator` for token review
- **Purpose**: Allows Vault to authenticate Kubernetes service accounts

## Management Scripts

### Configure Vault

```bash
./scripts/configure-vault.sh
```

Configures Kubernetes authentication, policies, and roles.

### Configure Kubernetes Auth

```bash
./scripts/configure-vault-kubernetes-auth.sh
```

Improved script for setting up Kubernetes authentication with proper policy handling.

### Backup Vault Data

```bash
./scripts/backup-vault-data.sh [namespace] [backup-dir]
```

Creates a Raft snapshot backup of Vault data.

### Restore Vault Data

```bash
./scripts/restore-vault-data.sh [namespace] <backup-file>
```

Restores Vault data from a Raft snapshot.

## Sync Waves

The ArgoCD applications use sync waves to ensure proper deployment order:

1. **Wave 10**: Vault namespace and OperatorGroup
2. **Wave 20**: Common RBAC (ServiceAccount, ClusterRole)
3. **Wave 30**: Vault server deployment

Applications consuming Vault should use higher sync waves (40+).

## Security Considerations

1. **Unseal Keys**: Store unseal keys securely (e.g., in a password manager or KMS)
2. **Root Token**: Rotate the root token after initial setup
3. **Auto-Unseal**: Consider configuring auto-unseal for production using cloud KMS
4. **TLS**: Enable TLS for production deployments
5. **Audit Logging**: Enable audit logging to track all Vault access
6. **Backup**: Regularly backup Vault data using the provided scripts

## Troubleshooting

### Vault Pod Not Starting

```bash
kubectl get pods -n vault
kubectl logs -n vault vault-0
kubectl describe pod -n vault vault-0
```

### Vault Sealed

```bash
kubectl exec -n vault vault-0 -- vault status
kubectl exec -n vault vault-0 -- vault operator unseal <key>
```

### Check Operator Status

```bash
kubectl get subscription -n openshift-operators vault-secrets-operator
kubectl get csv -n openshift-operators | grep vault
```

## Documentation

- [VAULT_INTEGRATION.md](VAULT_INTEGRATION.md) - Comprehensive integration guide
- [HashiCorp Vault Documentation](https://www.vaultproject.io/docs)
- [Vault Secrets Operator](https://github.com/hashicorp/vault-secrets-operator)

## License

See [LICENSE](LICENSE) file for details.

## Contributing

This is infrastructure code. Changes should be:
1. Tested in a development environment
2. Reviewed by the platform team
3. Applied during maintenance windows for production

## Support

For issues or questions:
- Check the [VAULT_INTEGRATION.md](VAULT_INTEGRATION.md) guide
- Review Vault logs: `kubectl logs -n vault vault-0`
- Contact the platform team