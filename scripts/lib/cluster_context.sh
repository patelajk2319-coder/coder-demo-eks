#!/usr/bin/env bash
# Ensure kubectl is pointing at the correct cluster context.
# Source this file from any script that calls kubectl or helm.

: "${EKS_CLUSTER_NAME:?EKS_CLUSTER_NAME must be set in .env}"

EXPECTED_CONTEXT="${EKS_CLUSTER_NAME}-admin"

current=$(kubectl config current-context 2>/dev/null || echo "")

if [[ "${current}" != "${EXPECTED_CONTEXT}" ]]; then
  kubectl config use-context "${EXPECTED_CONTEXT}" >/dev/null
fi
