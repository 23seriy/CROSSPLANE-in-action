#!/bin/bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

echo "============================================"
echo "  Crossplane in Action — Prerequisites"
echo "============================================"
echo ""

if [[ "$(uname)" != "Darwin" ]]; then
    error "This script is designed for macOS. Adjust package manager commands for your OS."
    exit 1
fi

if ! command -v brew &> /dev/null; then
    error "Homebrew is required. Install it from https://brew.sh"
    exit 1
fi

if command -v minikube &> /dev/null; then
    info "minikube already installed: $(minikube version --short 2>/dev/null || minikube version | head -1)"
else
    info "Installing minikube..."
    brew install minikube
fi

if command -v kubectl &> /dev/null; then
    info "kubectl already installed"
else
    info "Installing kubectl..."
    brew install kubectl
fi

if command -v helm &> /dev/null; then
    info "helm already installed: $(helm version --short 2>/dev/null)"
else
    info "Installing helm..."
    brew install helm
fi

if command -v docker &> /dev/null; then
    info "Docker already installed: $(docker --version)"
else
    error "Docker is required. Install Docker Desktop from https://docker.com"
    exit 1
fi

echo ""
info "All prerequisites are ready."
