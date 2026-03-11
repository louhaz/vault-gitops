#!/bin/bash
set -e

echo "=== Configuring HashiCorp Vault for IBM Verify Access ==="
echo ""

# Step 1: Enable Kubernetes Authentication
echo "Step 1: Enabling Kubernetes authentication..."
kubectl exec -n ibm-verify vault-0 -- vault auth enable kubernetes || echo "Kubernetes auth already enabled"
echo "✓ Kubernetes auth enabled"
echo ""

# Step 2: Configure Kubernetes Auth
echo "Step 2: Configuring Kubernetes authentication..."
kubectl exec -n ibm-verify vault-0 -- vault write auth/kubernetes/config \
    kubernetes_host="https://kubernetes.default.svc:443"
echo "✓ Kubernetes auth configured"
echo ""

# Step 3: Create Vault Policy
echo "Step 3: Creating Vault policy for IBM Verify Access..."
kubectl exec -n ibm-verify vault-0 -- sh -c 'vault policy write ibm-verify-policy - <<EOF
# Allow reading IBM Verify Access secrets
path "ibm-verify/data/ivia-secrets" {
  capabilities = ["read", "list"]
}

# Allow reading metadata
path "ibm-verify/metadata/ivia-secrets" {
  capabilities = ["read", "list"]
}
EOF'
echo "✓ Vault policy created"
echo ""

# Step 4: Create Kubernetes Auth Role
echo "Step 4: Creating Kubernetes auth role..."
kubectl exec -n ibm-verify vault-0 -- vault write auth/kubernetes/role/ibm-verify \
    bound_service_account_names=ibm-verify-sa,default \
    bound_service_account_namespaces=ibm-verify \
    policies=ibm-verify-policy \
    ttl=24h
echo "✓ Kubernetes auth role created"
echo ""

# Step 5: Verify Configuration
echo "Step 5: Verifying configuration..."
echo ""
echo "Enabled auth methods:"
kubectl exec -n ibm-verify vault-0 -- vault auth list
echo ""
echo "Vault policies:"
kubectl exec -n ibm-verify vault-0 -- vault policy list
echo ""
echo "Kubernetes auth role details:"
kubectl exec -n ibm-verify vault-0 -- vault read auth/kubernetes/role/ibm-verify
echo ""

echo "=== Vault Configuration Complete ==="
echo ""
echo "Next steps:"
echo "1. Create VaultAuth and VaultStaticSecret custom resources"
echo "2. Deploy them to sync secrets from Vault to Kubernetes"
echo "3. Update IBM Verify Access deployments to use the synced secrets"

# Made with Bob
