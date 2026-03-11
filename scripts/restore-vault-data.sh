#!/bin/bash
# Script to restore Vault data to the new namespace
# This should be run AFTER deploying Vault to the new namespace

set -e

TARGET_NAMESPACE="${1:-vault}"
BACKUP_FILE="${2}"

echo "=========================================="
echo "Vault Data Restore Script"
echo "=========================================="
echo "Target Namespace: ${TARGET_NAMESPACE}"
echo "Backup File: ${BACKUP_FILE}"
echo ""

# Check if backup file is provided
if [ -z "${BACKUP_FILE}" ]; then
    echo "ERROR: Backup file not specified"
    echo "Usage: $0 [target-namespace] <backup-file>"
    echo "Example: $0 vault ./vault-backups/vault-backup-20240310-120000.snap"
    exit 1
fi

# Check if backup file exists
if [ ! -f "${BACKUP_FILE}" ]; then
    echo "ERROR: Backup file not found: ${BACKUP_FILE}"
    exit 1
fi

# Check if Vault pod exists
VAULT_POD="vault-0"
echo "Checking for Vault pod in namespace ${TARGET_NAMESPACE}..."
if ! kubectl get pod -n ${TARGET_NAMESPACE} ${VAULT_POD} &>/dev/null; then
    echo "ERROR: Vault pod ${VAULT_POD} not found in namespace ${TARGET_NAMESPACE}"
    echo "Please ensure Vault is deployed to the target namespace first."
    exit 1
fi

# Check if Vault is initialized
echo "Checking Vault initialization status..."
INIT_STATUS=$(kubectl exec -n ${TARGET_NAMESPACE} ${VAULT_POD} -- vault status -format=json 2>/dev/null | jq -r '.initialized')
if [ "$INIT_STATUS" != "true" ]; then
    echo "ERROR: Vault is not initialized. Please initialize Vault first."
    exit 1
fi

# Check if Vault is unsealed
echo "Checking Vault seal status..."
SEAL_STATUS=$(kubectl exec -n ${TARGET_NAMESPACE} ${VAULT_POD} -- vault status -format=json 2>/dev/null | jq -r '.sealed')
if [ "$SEAL_STATUS" = "true" ]; then
    echo "ERROR: Vault is sealed. Please unseal Vault before restoring."
    exit 1
fi

echo "Vault is initialized, unsealed, and ready for restore."
echo ""

# Copy backup file to pod
echo "Copying backup file to Vault pod..."
kubectl cp "${BACKUP_FILE}" ${TARGET_NAMESPACE}/${VAULT_POD}:/tmp/vault-restore.snap

# Restore snapshot
echo "Restoring Raft snapshot..."
echo "WARNING: This will overwrite all data in the target Vault instance!"
read -p "Are you sure you want to continue? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo "Restore cancelled."
    kubectl exec -n ${TARGET_NAMESPACE} ${VAULT_POD} -- rm -f /tmp/vault-restore.snap
    exit 0
fi

kubectl exec -n ${TARGET_NAMESPACE} ${VAULT_POD} -- vault operator raft snapshot restore -force /tmp/vault-restore.snap

# Clean up temporary file
echo "Cleaning up temporary files..."
kubectl exec -n ${TARGET_NAMESPACE} ${VAULT_POD} -- rm -f /tmp/vault-restore.snap

echo ""
echo "=========================================="
echo "Restore completed successfully!"
echo "=========================================="
echo ""
echo "IMPORTANT: Vault may need to be unsealed again after restore."
echo "Please check the Vault status and unseal if necessary."
echo ""
echo "To check status:"
echo "  kubectl exec -n ${TARGET_NAMESPACE} ${VAULT_POD} -- vault status"

# Made with Bob
