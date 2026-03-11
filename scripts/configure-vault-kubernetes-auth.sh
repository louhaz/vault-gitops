#!/bin/bash
# Improved script to configure Vault Kubernetes authentication
# This version handles the policy creation issue

set -e

VAULT_NAMESPACE="vault"
VAULT_POD="vault-0"
APP_NAMESPACE="ibm-verify"
ROLE_NAME="ibm-verify"
POLICY_NAME="ibm-verify-policy"
SA_NAME="ibm-verify-sa"

echo "=========================================="
echo "Configuring Vault Kubernetes Auth"
echo "=========================================="
echo "Vault Namespace: ${VAULT_NAMESPACE}"
echo "App Namespace: ${APP_NAMESPACE}"
echo ""

# Check if Vault pod exists
if ! kubectl get pod -n ${VAULT_NAMESPACE} ${VAULT_POD} &>/dev/null; then
    echo "ERROR: Vault pod ${VAULT_POD} not found in namespace ${VAULT_NAMESPACE}"
    exit 1
fi

# Check if Vault is unsealed
echo "Checking Vault status..."
if ! kubectl exec -n ${VAULT_NAMESPACE} ${VAULT_POD} -- vault status &>/dev/null; then
    echo "ERROR: Cannot connect to Vault or Vault is sealed"
    echo "Please unseal Vault first"
    exit 1
fi

echo "✓ Vault is accessible"
echo ""

# Prompt for root token
read -sp "Enter Vault root token: " ROOT_TOKEN
echo ""

# Login to Vault
echo "Logging in to Vault..."
if ! kubectl exec -n ${VAULT_NAMESPACE} ${VAULT_POD} -- vault login ${ROOT_TOKEN} &>/dev/null; then
    echo "ERROR: Failed to login to Vault. Check your root token."
    exit 1
fi
echo "✓ Logged in successfully"
echo ""

# Enable Kubernetes auth
echo "Enabling Kubernetes auth method..."
kubectl exec -n ${VAULT_NAMESPACE} ${VAULT_POD} -- vault auth enable kubernetes 2>/dev/null || echo "  (already enabled)"
echo "✓ Kubernetes auth enabled"
echo ""

# Configure Kubernetes auth
echo "Configuring Kubernetes auth..."
kubectl exec -n ${VAULT_NAMESPACE} ${VAULT_POD} -- vault write auth/kubernetes/config \
    kubernetes_host="https://kubernetes.default.svc:443"
echo "✓ Kubernetes auth configured"
echo ""

# Create policy using file method
echo "Creating policy ${POLICY_NAME}..."
cat > /tmp/vault-policy-$$.hcl <<'EOF'
path "ibm-verify/*" {
  capabilities = ["read", "list"]
}

path "ibm-verify/data/*" {
  capabilities = ["read", "list"]
}

path "ibm-verify/metadata/*" {
  capabilities = ["read", "list"]
}
EOF

kubectl cp /tmp/vault-policy-$$.hcl ${VAULT_NAMESPACE}/${VAULT_POD}:/tmp/policy.hcl
kubectl exec -n ${VAULT_NAMESPACE} ${VAULT_POD} -- vault policy write ${POLICY_NAME} /tmp/policy.hcl
kubectl exec -n ${VAULT_NAMESPACE} ${VAULT_POD} -- rm /tmp/policy.hcl
rm /tmp/vault-policy-$$.hcl
echo "✓ Policy created"
echo ""

# Create role
echo "Creating Kubernetes auth role ${ROLE_NAME}..."
kubectl exec -n ${VAULT_NAMESPACE} ${VAULT_POD} -- vault write auth/kubernetes/role/${ROLE_NAME} \
    bound_service_account_names="${SA_NAME}" \
    bound_service_account_namespaces="${APP_NAMESPACE}" \
    policies="${POLICY_NAME}" \
    ttl="24h"
echo "✓ Role created"
echo ""

# Enable KV secrets engine
echo "Enabling KV v2 secrets engine..."
kubectl exec -n ${VAULT_NAMESPACE} ${VAULT_POD} -- vault secrets enable -path=ibm-verify kv-v2 2>/dev/null || echo "  (already enabled)"
echo "✓ KV secrets engine enabled"
echo ""

# Verify configuration
echo "=========================================="
echo "Verifying Configuration"
echo "=========================================="

echo ""
echo "Auth methods:"
kubectl exec -n ${VAULT_NAMESPACE} ${VAULT_POD} -- vault auth list | grep kubernetes

echo ""
echo "Policy:"
kubectl exec -n ${VAULT_NAMESPACE} ${VAULT_POD} -- vault policy read ${POLICY_NAME}

echo ""
echo "Role configuration:"
kubectl exec -n ${VAULT_NAMESPACE} ${VAULT_POD} -- vault read auth/kubernetes/role/${ROLE_NAME}

echo ""
echo "=========================================="
echo "Configuration Complete!"
echo "=========================================="
echo ""
echo "Next steps:"
echo "1. Check VaultAuth status: kubectl get vaultauth -n ${APP_NAMESPACE}"
echo "2. Check VaultStaticSecret status: kubectl get vaultstaticsecret -n ${APP_NAMESPACE}"
echo "3. Check synced secrets: kubectl get secret -n ${APP_NAMESPACE}"
echo ""
echo "If VaultStaticSecret still shows errors, restart the operator:"
echo "  kubectl delete pod -n ${VAULT_NAMESPACE} -l app.kubernetes.io/name=vault-secrets-operator"

# Made with Bob
