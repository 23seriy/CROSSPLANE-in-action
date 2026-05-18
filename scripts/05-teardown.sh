#!/bin/bash
# Note: no 'set -e' — cleanup commands are best-effort because
# minikube delete at the end will wipe everything regardless.
set -uo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }

PROFILE="crossplane-demo"

echo "============================================"
echo "  Crossplane in Action — Teardown"
echo "============================================"
echo ""

read -p "This will delete the Minikube cluster '$PROFILE'. Continue? (y/N) " -n 1 -r
echo ""

if [[ $REPLY =~ ^[Yy]$ ]]; then

    # Best-effort cleanup — if the API server is unreachable, skip
    # straight to minikube delete which nukes everything anyway.
    if kubectl cluster-info &>/dev/null; then
        info "Deleting composite resources and managed resources..."
        kubectl delete xobjectstorages --all --timeout=30s 2>/dev/null || true
        kubectl delete bucket.s3.aws.upbound.io --all --wait=false 2>/dev/null || true
        kubectl delete bucketversioning.s3.aws.upbound.io --all --wait=false 2>/dev/null || true

        info "Deleting Compositions and XRDs..."
        kubectl delete compositions --all --timeout=30s 2>/dev/null || true
        kubectl delete xrd --all --timeout=30s 2>/dev/null || true

        info "Deleting demo namespace..."
        kubectl delete namespace crossplane-demo --ignore-not-found --wait=false 2>/dev/null || true

        info "Uninstalling Crossplane functions..."
        kubectl delete functions --all --timeout=30s 2>/dev/null || true

        info "Uninstalling Crossplane providers..."
        kubectl delete providers --all --wait=false 2>/dev/null || true

        info "Uninstalling Crossplane..."
        helm uninstall crossplane -n crossplane-system --timeout=60s 2>/dev/null || true
        kubectl delete namespace crossplane-system --ignore-not-found --wait=false 2>/dev/null || true
    else
        warn "Cluster API server is unreachable — skipping resource cleanup."
        warn "minikube delete will remove everything."
    fi

    echo ""
    info "Deleting Minikube cluster..."
    minikube delete -p "$PROFILE"

    info "Teardown complete!"
else
    warn "Teardown cancelled."
fi
