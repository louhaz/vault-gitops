#!/bin/bash
# Script to backup Vault data from the current namespace
# This should be run BEFORE migrating Vault to a new namespace

set -e

SOURCE_NAMESPACE="${1:-ibm-verify}"
BACKUP_DIR="${2:-./vault-backups}"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_FILE="${BACKUP_DIR}/vault-backup-${TIMESTAMP}.snap"

echo "=========================================="
echo "Vault Data Backup Script"
echo "=========================================="
echo "Source Namespace: ${SOURCE_NAMESPACE}"
echo "Backup Directory: ${BACKUP_DIR}"
echo "Backup File: ${BACKUP_FILE}"
echo ""

# Create backup directory if it doesn't exist
mkdir -p "${BACKUP_DIR}"

# Check if Vault pod exists
VAULT_POD="vault-0"
echo "Checking for Vault pod in namespace ${SOURCE_NAMESPACE}..."
if ! kubectl get pod -n ${SOURCE_NAMESPACE} ${VAULT_POD} &>/dev/null; then
    echo "ERROR: Vault pod ${VAULT_POD} not found in namespace ${SOURCE_NAMESPACE}"
    exit 1
fi

# Check if Vault is unsealed
echo "Checking Vault seal status..."
SEAL_STATUS=$(kubectl exec -n ${SOURCE_NAMESPACE} ${VAULT_POD} -- vault status -format=json 2>/dev/null | jq -r '.sealed')
if [ "$SEAL_STATUS" = "true" ]; then
    echo "ERROR: Vault is sealed. Please unseal Vault before backing up."
    exit 1
fi

echo "Vault is unsealed and ready for backup."
echo ""

# Create snapshot
echo "Creating Raft snapshot..."
kubectl exec -n ${SOURCE_NAMESPACE} ${VAULT_POD} -- vault operator raft snapshot save /tmp/vault-backup.snap

# Copy snapshot from pod to local filesystem
echo "Copying snapshot from pod to local filesystem..."
kubectl cp ${SOURCE_NAMESPACE}/${VAULT_POD}:/tmp/vault-backup.snap "${BACKUP_FILE}"

# Verify backup file exists
if [ -f "${BACKUP_FILE}" ]; then
    BACKUP_SIZE=$(du -h "${BACKUP_FILE}" | cut -f1)
    echo ""
    echo "=========================================="
    echo "Backup completed successfully!"
    echo "=========================================="
    echo "Backup file: ${BACKUP_FILE}"
    echo "Backup size: ${BACKUP_SIZE}"
    echo ""
    echo "IMPORTANT: Store this backup in a secure location!"
    echo ""
else
    echo "ERROR: Backup file was not created successfully"
    exit 1
fi

# Clean up temporary file in pod
echo "Cleaning up temporary files..."
kubectl exec -n ${SOURCE_NAMESPACE} ${VAULT_POD} -- rm -f /tmp/vault-backup.snap

# Export secrets list for reference
echo ""
echo "Exporting secrets list for reference..."
SECRETS_LIST="${BACKUP_DIR}/vault-secrets-list-${TIMESTAMP}.txt"
kubectl exec -n ${SOURCE_NAMESPACE} ${VAULT_POD} -- vault kv list -format=json ibm-verify 2>/dev/null > "${SECRETS_LIST}" || echo "No secrets found or KV v2 not enabled"

echo ""
echo "Backup process complete!"
echo "Files created:"
echo "  - ${BACKUP_FILE}"
echo "  - ${SECRETS_LIST}"

# Made with Bob
