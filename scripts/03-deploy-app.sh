#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }

PROFILE="crossplane-demo"

echo "============================================"
echo "  Crossplane in Action — Deploy Application"
echo "============================================"
echo ""

info "Configuring Docker to use Minikube's daemon..."
eval $(minikube -p "$PROFILE" docker-env)

info "Building resource-api image..."
docker build -t crossplane-demo/resource-api:latest "$PROJECT_DIR/apps/resource-api"

info "Creating namespace..."
kubectl apply -f "$PROJECT_DIR/k8s/namespace.yaml"

info "Deploying LocalStack (local AWS simulator)..."
kubectl apply -f "$PROJECT_DIR/k8s/localstack.yaml"

info "Waiting for LocalStack to be ready..."
kubectl wait --for=condition=available deployment/localstack -n crossplane-demo --timeout=180s

info "Creating S3 bucket in LocalStack..."
kubectl exec deployment/localstack -n crossplane-demo -- \
    awslocal s3 mb s3://crossplane-demo-bucket 2>/dev/null || warn "Bucket may already exist"

info "Deploying resource-api..."
kubectl apply -f "$PROJECT_DIR/k8s/resource-api-sa.yaml"
kubectl apply -f "$PROJECT_DIR/k8s/aws-credentials.yaml"
kubectl apply -f "$PROJECT_DIR/k8s/resource-api-config.yaml"
kubectl apply -f "$PROJECT_DIR/k8s/resource-api.yaml"
kubectl apply -f "$PROJECT_DIR/k8s/resource-api-service.yaml"

info "Restarting resource-api so rebuilt image is picked up..."
kubectl rollout restart deployment/resource-api -n crossplane-demo

info "Waiting for resource-api to be ready..."
kubectl rollout status deployment/resource-api -n crossplane-demo --timeout=180s

echo ""
info "Application deployed successfully!"
echo ""
kubectl get pods -n crossplane-demo
echo ""
echo "Access the resource API with:"
echo "  kubectl port-forward svc/resource-api 9090:8080 -n crossplane-demo"
echo ""
echo "Next step: ./scripts/04-demo-scenarios.sh"
