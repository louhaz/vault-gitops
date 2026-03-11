# HashiCorp Vault GitOps Infrastructure

This repository provides a standalone HashiCorp Vault infrastructure deployment for Kubernetes/OpenShift using GitOps principles with ArgoCD. This Vault instance can be consumed by multiple applications across your cluster.

## Overview

This repository deploys:

- **Vault Server**: HashiCorp Vault 1.21.2 using the official Helm chart
- **Vault Namespace**: Dedicated `vault` namespace for Vault components
- **Vault Secrets Operator**: For syncing secrets from Vault to Kubernetes
- **RBAC**: Cluster-level RBAC for Vault authentication and token review

## Architecture

```
vault-gitops/
├── argocd/                    # ArgoCD Applications
│   ├── bootstrap.yaml         # Bootstrap application
│   ├── kustomization.yaml     # Kustomize configuration
│   ├── vault-namespace.yaml   # Creates vault namespace (sync-wave: 10)
│   ├── vault-common.yaml      # Common RBAC (sync-wave: 20)
│   └── vault.yaml             # Vault Helm deployment (sync-wave: 30)
├── components/
│   ├── vault-namespace/       # Namespace and OperatorGroup
│   ├── vault-common/          # ServiceAccount and ClusterRole
│   └── operators/vault/       # Vault Secrets Operator subscription
└── scripts/                   # Vault management scripts
    ├── configure-vault.sh
    ├── backup-vault-data.sh
    └── restore-vault-data.sh
```

## Prerequisites

- Kubernetes 1.20+ or OpenShift 4.10+
- ArgoCD or Red Hat OpenShift GitOps installed
- Cluster admin access for operator installation
- `kubectl` or `oc` CLI installed
- `vault` CLI installed (for configuration)

## Installation

### Step 1: Fork and Configure Repository

1. **Fork this repository** to your own GitHub account or Git server

2. **Clone your forked repository:**
   ```bash
   git clone <your-repo-url>
   cd vault-gitops
   ```

3. **Update the repository URL** in `argocd/bootstrap.yaml` and `argocd/kustomization.yaml`

4. **Commit and push changes:**
   ```bash
   git add argocd/
   git commit -m "Update repository URL"
   git push
   ```

### Step 2: Deploy Vault Infrastructure

Apply the ArgoCD bootstrap application:

```bash
kubectl apply -f argocd/bootstrap.yaml
```

This will deploy:
- Vault namespace and OperatorGroup
- Vault Secrets Operator
- Common RBAC resources
- Vault server (Helm chart)

### Step 3: Wait for Vault to be Ready

```bash
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=vault -n vault --timeout=300s
```

### Step 4: Initialize Vault

**First time only** - Initialize Vault and save the unseal keys and root token securely:

```bash
kubectl exec -n vault vault-0 -- vault operator init -key-shares=5 -key-threshold=3
```

**IMPORTANT:** Save the output! You'll receive:
- 5 unseal keys (you need 3 to unseal)
- 1 root token (for administrative access)

Store these securely in a password manager or secrets management system. **Never commit them to git!**

### Step 5: Unseal Vault

Vault starts in a sealed state. Unseal it using 3 of the 5 unseal keys:

```bash
kubectl exec -n vault vault-0 -- vault operator unseal <unseal-key-1>
kubectl exec -n vault vault-0 -- vault operator unseal <unseal-key-2>
kubectl exec -n vault vault-0 -- vault operator unseal <unseal-key-3>
```

Verify Vault is unsealed:

```bash
kubectl exec -n vault vault-0 -- vault status
```

### Step 6: Configure Vault for Applications

Login with the root token:

```bash
kubectl exec -n vault vault-0 -- vault login <root-token>
```

Run the configuration script to set up Kubernetes authentication:

```bash
./scripts/configure-vault.sh
```

This script:
- Enables Kubernetes authentication
- Configures Kubernetes auth to trust your cluster
- Creates a default policy for IBM Verify Access
- Creates a Kubernetes auth role

## Vault Components

### Vault Server
- **Version**: Vault 1.21.2
- **Storage**: File-based storage with 10Gi PVC
- **UI**: Enabled at `http://vault.vault.svc.cluster.local:8200`
- **TLS**: Disabled (for internal cluster communication)
- **High Availability**: Single instance (can be scaled)

### Vault Secrets Operator
- **Purpose**: Syncs secrets from Vault to Kubernetes secrets
- **Namespace**: Installed in `openshift-operators` (cluster-wide)
- **Channel**: stable

### RBAC
- **ServiceAccount**: `vault-sa` in `vault` namespace
- **ClusterRole**: `vault-auth-delegator` for token review
- **Purpose**: Allows Vault to authenticate Kubernetes service accounts

## Application Integration

Applications can consume this Vault infrastructure by creating these resources in their namespace:

### 1. VaultConnection

```yaml
apiVersion: secrets.hashicorp.com/v1beta1
kind: VaultConnection
metadata:
  name: vault-connection
  namespace: my-app
spec:
  address: http://vault.vault.svc.cluster.local:8200
  skipTLSVerify: true
```

### 2. VaultAuth

```yaml
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

### 3. VaultStaticSecret

```yaml
apiVersion: secrets.hashicorp.com/v1beta1
kind: VaultStaticSecret
metadata:
  name: my-app-secret
  namespace: my-app
spec:
  vaultAuthRef: my-app-auth
  mount: my-app
  path: my-secrets
  destination:
    create: true
    name: my-app-secret
  refreshAfter: 30s
```

## Management Scripts

### Configure Vault
```bash
./scripts/configure-vault.sh
```
Configures Kubernetes authentication, policies, and roles for IBM Verify Access.

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

## Accessing Vault

### Via Port-Forward
```bash
kubectl port-forward -n vault svc/vault 8200:8200
```

Then access:
- **CLI**: `export VAULT_ADDR=http://localhost:8200`
- **UI**: http://localhost:8200

### Via Service (from within cluster)
- **Address**: `http://vault.vault.svc.cluster.local:8200`

## Sync Waves

The ArgoCD applications use sync waves to ensure proper deployment order:

1. **Wave 10**: Vault namespace and OperatorGroup
2. **Wave 20**: Common RBAC (ServiceAccount, ClusterRole)
3. **Wave 30**: Vault Secrets Operator
4. **Wave 40**: Vault server deployment

Applications consuming Vault should use higher sync waves (50+).

## Security Considerations

### Production Recommendations

1. **Unseal Keys**: 
   - Store unseal keys in a secure key management system (AWS KMS, Azure Key Vault, etc.)
   - Never commit unseal keys to git
   - Consider using auto-unseal for production

2. **Root Token**:
   - Rotate the root token after initial setup
   - Use limited-privilege tokens for day-to-day operations
   - Revoke root token when not needed

3. **TLS**:
   - Enable TLS for production deployments
   - Use proper certificates (not self-signed)

4. **Audit Logging**:
   - Enable audit logging to track all Vault access
   ```bash
   kubectl exec -n vault vault-0 -- vault audit enable file file_path=/vault/logs/audit.log
   ```

5. **Backup**:
   - Regularly backup Vault data using the provided scripts
   - Test restore procedures

6. **High Availability**:
   - Scale Vault to 3+ replicas for production
   - Use Raft storage backend for HA

## Troubleshooting

### Vault Pod Not Starting

```bash
kubectl get pods -n vault
kubectl logs -n vault vault-0
kubectl describe pod -n vault vault-0
```

### Vault Sealed After Restart

Vault seals automatically on restart. Unseal it again:

```bash
kubectl exec -n vault vault-0 -- vault operator unseal <key-1>
kubectl exec -n vault vault-0 -- vault operator unseal <key-2>
kubectl exec -n vault vault-0 -- vault operator unseal <key-3>
```

### Check Vault Status

```bash
kubectl exec -n vault vault-0 -- vault status
```

### Check Operator Status

```bash
kubectl get subscription -n openshift-operators vault-secrets-operator
kubectl get csv -n openshift-operators | grep vault
```

### View Vault Logs

```bash
kubectl logs -n vault vault-0 -f
```

## Documentation

- [HashiCorp Vault Documentation](https://www.vaultproject.io/docs)
- [Vault Secrets Operator](https://github.com/hashicorp/vault-secrets-operator)
- [Kubernetes Auth Method](https://www.vaultproject.io/docs/auth/kubernetes)

## Example: IBM Verify Access Integration

See the [verify-gitops-demo](https://github.com/louhaz/verify-gitops-demo) repository for a complete example of integrating this Vault infrastructure with IBM Verify Access.

## License

See [LICENSE](LICENSE) file for details.

## Contributing

This is infrastructure code. Changes should be:
1. Tested in a development environment
2. Reviewed by the platform team
3. Applied during maintenance windows for production

## Support

For issues or questions:
- Review Vault logs: `kubectl logs -n vault vault-0`
- Check Vault status: `kubectl exec -n vault vault-0 -- vault status`
- Consult HashiCorp Vault documentation