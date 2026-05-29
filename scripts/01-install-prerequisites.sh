#!/usr/bin/env bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check if a Homebrew formula has a newer version available.
# Usage: check_brew_upgrade <formula>
check_brew_upgrade() {
    local formula="$1"
    local outdated
    outdated=$(brew outdated --formula 2>/dev/null | grep -w "$formula" || true)
    if [[ -n "$outdated" ]]; then
        local installed latest
        installed=$(brew list --versions "$formula" 2>/dev/null | awk '{print $2}')
        latest=$(brew info --json=v2 "$formula" 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin)['formulae'][0]['versions']['stable'])" 2>/dev/null || echo "unknown")
        warn "$formula can be upgraded: $installed → $latest"
        warn "  Run: brew upgrade $formula"
    fi
}

# Check Docker Desktop version against the latest release on GitHub.
check_docker_upgrade() {
    local current latest
    current=$(docker --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    if [[ -z "$current" ]]; then return; fi
    latest=$(curl -sf --max-time 5 "https://api.github.com/repos/docker/cli/tags?per_page=1" \
        | python3 -c "import sys,json; tags=json.load(sys.stdin); print(tags[0]['name'].lstrip('v'))" 2>/dev/null || echo "")
    if [[ -z "$latest" ]]; then return; fi
    if [[ "$current" != "$latest" ]]; then
        warn "Docker can be upgraded: $current → $latest"
        warn "  Update via Docker Desktop → Check for Updates"
    fi
}

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
    info "kubectl already installed: $(kubectl version --client -o json 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin)['clientVersion']['gitVersion'])" 2>/dev/null || echo "")"
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

# ── Check for newer versions ──────────────────────────────
echo ""
echo -e "${CYAN}Checking for available upgrades...${NC}"
check_brew_upgrade minikube
check_brew_upgrade kubernetes-cli
check_brew_upgrade helm
check_docker_upgrade

if [[ -z "$(brew outdated --formula 2>/dev/null | grep -wE 'minikube|kubernetes-cli|helm' || true)" ]]; then
    info "All Homebrew tools are up to date."
fi

echo ""
info "All prerequisites are ready."
