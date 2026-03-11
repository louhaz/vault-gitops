# Vault Infrastructure Migration Guide

This document describes the migration of Vault infrastructure from `verify-gitops-demo` to this dedicated `vault-gitops` repository.

## What Was Migrated

### Files Moved to vault-gitops

The following files were copied from `verify-gitops-demo` to this repository:

#### ArgoCD Applications (3 files)
- `argocd/vault-namespace.yaml` - Creates vault namespace (sync-wave: 10)
- `argocd/vault-common.yaml` - Common RBAC for Vault (sync-wave: 20)
- `argocd/vault.yaml` - Vault Helm chart deployment (sync-wave: 30)

#### Component Manifests
- `components/vault-namespace/base/` - Namespace and OperatorGroup
  - `namespace.yaml`
  - `operatorgroup.yaml`
  - `kustomization.yaml`

- `components/vault-common/base/` - Common RBAC
  - `serviceaccount.yaml` - vault-sa
  - `clusterrole.yaml` - vault-auth-delegator
  - `clusterrolebinding.yaml`
  - `kustomization.yaml`

- `components/operators/vault/base/` - Vault Secrets Operator
  - `subscription.yaml`
  - `kustomization.yaml`

#### Scripts (4 files)
- `scripts/configure-vault.sh`
- `scripts/configure-vault-kubernetes-auth.sh`
- `scripts/backup-vault-data.sh`
- `scripts/restore-vault-data.sh`

#### Documentation
- `VAULT_INTEGRATION.md` - Complete integration guide
- `LICENSE` - License file

### Files Remaining in verify-gitops-demo

The following files should **remain** in `verify-gitops-demo` as they are application-specific:

#### ArgoCD Applications
- `argocd/vault-rbac.yaml` - Cross-namespace auth for ibm-verify (sync-wave: 40)
- `argocd/vault-config.yaml` - VaultAuth/VaultStaticSecret resources (sync-wave: 300)

#### Component Manifests
- `components/vault-rbac/base/` - Cross-namespace RBAC
  - `clusterrole-vault-auth.yaml`
  - `clusterrolebinding-ibm-verify.yaml`
  - `kustomization.yaml`

- `components/vault-config/base/` - Application Vault configuration
  - `serviceaccount.yaml` - ibm-verify-sa
  - `role.yaml`
  - `rolebinding.yaml`
  - `vault-connection.yaml` - Points to vault.vault.svc
  - `vault-auth.yaml` - Kubernetes auth for ibm-verify
  - `vault-static-secret.yaml` - Syncs secrets from Vault
  - `kustomization.yaml`

- `components/operators/vault-config/base/` - Vault Config Operator (if used)

## Required Updates

### 1. Update ArgoCD Applications in vault-gitops

You need to update the `repoURL` in the ArgoCD applications to point to your new repository.

**Files to update:**
- `argocd/vault-namespace.yaml`
- `argocd/vault-common.yaml`

**Change:**
```yaml
spec:
  source:
    repoURL: https://github.com/IBM-Security/verify-gitops-demo  # OLD
    repoURL: https://github.com/YOUR-ORG/vault-gitops            # NEW
```

**Note:** `argocd/vault.yaml` uses a Helm chart repository, so no change is needed.

### 2. No Changes Needed in verify-gitops-demo

The files remaining in `verify-gitops-demo` already reference the Vault service correctly:

```yaml
# vault-connection.yaml
spec:
  address: http://vault.vault.svc.cluster.local:8200
```

This service endpoint remains the same regardless of which repository the Vault infrastructure is deployed from.

## Deployment Order

The sync waves ensure proper deployment order across both repositories:

1. **Wave 10** (vault-gitops): Vault namespace
2. **Wave 20** (vault-gitops): Vault common RBAC
3. **Wave 30** (vault-gitops): Vault server
4. **Wave 40** (verify-gitops-demo): Cross-namespace RBAC for ibm-verify
5. **Wave 300** (verify-gitops-demo): Vault configuration and secrets

## Post-Migration Steps

### 1. Update Repository URLs

Edit the following files in `vault-gitops`:

```bash
# Update vault-namespace.yaml
vim argocd/vault-namespace.yaml
# Change repoURL to: https://github.com/YOUR-ORG/vault-gitops

# Update vault-common.yaml
vim argocd/vault-common.yaml
# Change repoURL to: https://github.com/YOUR-ORG/vault-gitops
```

### 2. Commit and Push vault-gitops

```bash
cd vault-gitops
git add .
git commit -m "Initial commit: Vault infrastructure from verify-gitops-demo"
git remote add origin https://github.com/YOUR-ORG/vault-gitops.git
git push -u origin main
```

### 3. Remove Migrated Files from verify-gitops-demo

**IMPORTANT:** Only do this after vault-gitops is successfully deployed and tested!

```bash
cd verify-gitops-demo

# Remove migrated ArgoCD applications
git rm argocd/vault-namespace.yaml
git rm argocd/vault-common.yaml
git rm argocd/vault.yaml

# Remove migrated components
git rm -r components/vault-namespace/
git rm -r components/vault-common/
git rm -r components/operators/vault/

# Remove migrated scripts (keep if you want them in both repos)
git rm scripts/configure-vault.sh
git rm scripts/configure-vault-kubernetes-auth.sh
git rm scripts/backup-vault-data.sh
git rm scripts/restore-vault-data.sh

# Remove migrated documentation (keep if you want it in both repos)
git rm VAULT_INTEGRATION.md

git commit -m "Remove Vault infrastructure (moved to vault-gitops repository)"
git push
```

### 4. Deploy from vault-gitops

```bash
# Apply Vault infrastructure from new repository
kubectl apply -f https://raw.githubusercontent.com/YOUR-ORG/vault-gitops/main/argocd/vault-namespace.yaml
kubectl apply -f https://raw.githubusercontent.com/YOUR-ORG/vault-gitops/main/argocd/vault-common.yaml
kubectl apply -f https://raw.githubusercontent.com/YOUR-ORG/vault-gitops/main/argocd/vault.yaml

# Wait for Vault to be ready
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=vault -n vault --timeout=300s
```

### 5. Verify Application Integration

```bash
# Check that verify-gitops-demo applications can still connect
kubectl get vaultconnection -n ibm-verify
kubectl get vaultauth -n ibm-verify
kubectl get vaultstaticsecret -n ibm-verify
kubectl get secret ivia-secrets -n ibm-verify
```

## Rollback Plan

If something goes wrong, you can rollback:

### Option 1: Revert verify-gitops-demo

```bash
cd verify-gitops-demo
git revert <commit-hash>
git push
```

### Option 2: Keep Both Temporarily

You can keep the files in both repositories during a transition period. Just ensure only one set of ArgoCD applications is active at a time.

## Benefits of This Separation

1. **Reusability**: Vault infrastructure can be used by multiple applications
2. **Separation of Concerns**: Infrastructure vs application configuration
3. **Independent Lifecycle**: Update Vault without touching app configs
4. **Clear Ownership**: Platform team owns vault-gitops, app team owns vault-config
5. **Reduced Coupling**: Applications only depend on Vault service endpoint

## Architecture After Migration

```
┌─────────────────────────────────────┐
│     vault-gitops Repository         │
│  (Platform Team Ownership)          │
├─────────────────────────────────────┤
│ • Vault Namespace                   │
│ • Vault Server (Helm)               │
│ • Vault Operators                   │
│ • Common RBAC                       │
│ • Management Scripts                │
└─────────────────────────────────────┘
              │
              │ Provides: vault.vault.svc:8200
              ▼
┌─────────────────────────────────────┐
│  verify-gitops-demo Repository      │
│  (Application Team Ownership)       │
├─────────────────────────────────────┤
│ • VaultConnection                   │
│ • VaultAuth                         │
│ • VaultStaticSecret                 │
│ • Application Secrets               │
│ • Cross-namespace RBAC              │
└─────────────────────────────────────┘
```

## Verification Checklist

After migration, verify:

- [ ] vault-gitops repository created and pushed
- [ ] ArgoCD applications updated with correct repoURL
- [ ] Vault namespace exists: `kubectl get ns vault`
- [ ] Vault pod running: `kubectl get pods -n vault`
- [ ] Vault service accessible: `kubectl get svc -n vault vault`
- [ ] VaultConnection working: `kubectl get vaultconnection -n ibm-verify`
- [ ] VaultAuth working: `kubectl get vaultauth -n ibm-verify`
- [ ] Secrets syncing: `kubectl get vaultstaticsecret -n ibm-verify`
- [ ] IBM Verify apps can access secrets
- [ ] Old files removed from verify-gitops-demo (optional)

## Support

For issues:
1. Check Vault logs: `kubectl logs -n vault vault-0`
2. Check operator logs: `kubectl logs -n openshift-operators -l app.kubernetes.io/name=vault-secrets-operator`
3. Review [VAULT_INTEGRATION.md](VAULT_INTEGRATION.md)
4. Contact platform team

## Next Steps

1. Update the repoURL in ArgoCD applications
2. Test deployment in a development environment
3. Create a backup before production migration
4. Deploy to production during maintenance window
5. Monitor for 24-48 hours
6. Remove old files from verify-gitops-demo once stable