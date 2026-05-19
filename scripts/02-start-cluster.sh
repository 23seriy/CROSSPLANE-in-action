#!/bin/bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }

print_crossplane_diagnostics() {
    warn "Crossplane did not become ready in time. Collecting diagnostics..."
    echo ""
    kubectl get deployments -n crossplane-system || true
    echo ""
    kubectl get pods -n crossplane-system -o wide || true
    echo ""
    kubectl get events -n crossplane-system --sort-by=.metadata.creationTimestamp | tail -n 30 || true
}

PROFILE="crossplane-demo"
TARGET_K8S_VERSION="v1.32.0"

echo "============================================"
echo "  Crossplane in Action — Cluster Setup"
echo "============================================"
echo ""

if minikube status -p "$PROFILE" &> /dev/null; then
    info "Minikube cluster '$PROFILE' is already running"
    warn "This script expects Kubernetes ${TARGET_K8S_VERSION}. If this cluster was created with an older version, recreate it with: minikube delete -p $PROFILE"
else
    info "Starting Minikube cluster '$PROFILE'..."
    minikube start \
        --profile="$PROFILE" \
        --cpus=4 \
        --memory=8192 \
        --driver=docker \
        --kubernetes-version="$TARGET_K8S_VERSION"
fi

info "Setting kubectl context to '$PROFILE'..."
kubectl config use-context "$PROFILE"

info "Adding Crossplane Helm repository..."
helm repo add crossplane-stable https://charts.crossplane.io/stable >/dev/null 2>&1 || true
helm repo update >/dev/null

kubectl create namespace crossplane-system --dry-run=client -o yaml | kubectl apply -f -

if helm status crossplane -n crossplane-system >/dev/null 2>&1; then
    info "Crossplane Helm release already exists. Reconciling with upgrade --install..."
else
    info "Installing Crossplane..."
fi

helm upgrade --install crossplane crossplane-stable/crossplane \
    --namespace crossplane-system \
    --wait

if ! kubectl wait --for=condition=available deployment/crossplane -n crossplane-system --timeout=300s; then
    print_crossplane_diagnostics
    exit 1
fi

if ! kubectl wait --for=condition=available deployment/crossplane-rbac-manager -n crossplane-system --timeout=300s; then
    print_crossplane_diagnostics
    exit 1
fi

echo ""
info "Cluster and Crossplane are ready."
