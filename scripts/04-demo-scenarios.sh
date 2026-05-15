#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
header() { echo -e "\n${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; echo -e "${CYAN}  $1${NC}"; echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"; }

API_URL="http://localhost:9090"

wait_for_user() {
    echo ""
    echo -e "${YELLOW}Press Enter to continue...${NC}"
    read -r
}

echo "============================================"
echo "  Crossplane in Action — Demo Scenarios"
echo "============================================"
echo ""
echo "Make sure port-forward is running:"
echo "  kubectl port-forward svc/resource-api 9090:8080 -n crossplane-demo"
echo ""
echo "And in another terminal, watch Crossplane resources:"
echo "  kubectl get managed -w"
wait_for_user

# ── Scenario 1: Verify the App + LocalStack ────────────────────────
header "Scenario 1: Verify the App and LocalStack S3"
info "Checking health..."
curl -s "$API_URL/health" | python3 -m json.tool 2>/dev/null || true
echo ""
info "Putting a test object..."
curl -s -X POST "$API_URL/api/object/put" \
    -H "Content-Type: application/json" \
    -d '{"key":"hello.txt","content":"Hello from Crossplane in Action!"}' | python3 -m json.tool 2>/dev/null || true
echo ""
info "Listing objects..."
curl -s "$API_URL/api/objects" | python3 -m json.tool 2>/dev/null || true
echo ""
info "Getting the object back..."
curl -s "$API_URL/api/object?key=hello.txt" | python3 -m json.tool 2>/dev/null || true
wait_for_user

# ── Scenario 2: Install the AWS S3 Provider ────────────────────────
header "Scenario 2: Install the AWS S3 Provider"
info "Applying the Crossplane AWS S3 provider..."
kubectl apply -f "$PROJECT_DIR/crossplane/provider-aws.yaml"
echo ""
info "Waiting for provider to become healthy (this may take 1-2 minutes)..."
kubectl wait --for=condition=healthy provider.pkg/provider-aws-s3 --timeout=300s 2>/dev/null || true
echo ""
info "Provider status:"
kubectl get providers
wait_for_user

# ── Scenario 3: Configure ProviderConfig for LocalStack ────────────
header "Scenario 3: Configure ProviderConfig for LocalStack"
info "Applying LocalStack ProviderConfig..."
kubectl apply -f "$PROJECT_DIR/crossplane/provider-config-localstack.yaml"
echo ""
info "ProviderConfig status:"
kubectl get providerconfig 2>/dev/null || kubectl get providerconfigs.aws.upbound.io 2>/dev/null || true
wait_for_user

# ── Scenario 4: Provision an S3 Bucket via Crossplane ──────────────
header "Scenario 4: Provision an S3 Bucket via Crossplane CRD"
info "Applying Crossplane Bucket claim..."
kubectl apply -f "$PROJECT_DIR/crossplane/bucket-claim.yaml"
echo ""
info "Watching the bucket get provisioned..."
echo "  kubectl get bucket.s3.aws.upbound.io -w"
echo ""
info "Current managed resources:"
kubectl get managed 2>/dev/null || true
wait_for_user

# ── Scenario 5: Bucket with Versioning ─────────────────────────────
header "Scenario 5: Bucket with Versioning"
info "Applying bucket + versioning configuration..."
kubectl apply -f "$PROJECT_DIR/crossplane/bucket-with-versioning.yaml"
echo ""
info "Managed resources after adding versioning:"
kubectl get managed 2>/dev/null || true
wait_for_user

# ── Scenario 6: Compositions + XRDs ────────────────────────────────
header "Scenario 6: Platform Abstraction with XRD + Composition"
info "Applying XRD (CompositeResourceDefinition)..."
kubectl apply -f "$PROJECT_DIR/crossplane/xrd-objectstorage.yaml"
echo ""
info "Applying Composition..."
kubectl apply -f "$PROJECT_DIR/crossplane/composition-objectstorage.yaml"
echo ""
info "Creating a claim using the platform API..."
kubectl apply -f "$PROJECT_DIR/crossplane/claim-objectstorage.yaml"
echo ""
info "XRD status:"
kubectl get xrd 2>/dev/null || true
echo ""
info "Compositions:"
kubectl get compositions 2>/dev/null || true
echo ""
info "Claims:"
kubectl get objectstorages -n crossplane-demo 2>/dev/null || true
echo ""
info "Composite resources:"
kubectl get xobjectstorages 2>/dev/null || true
wait_for_user

# ── Scenario 7: Drift Detection ────────────────────────────────────
header "Scenario 7: Drift Detection — Delete the Bucket, Watch Crossplane Recreate It"
info "Deleting the bucket directly in LocalStack..."
kubectl exec deployment/localstack -n crossplane-demo -- \
    awslocal s3 rb s3://crossplane-demo-bucket --force 2>/dev/null || true
echo ""
info "Bucket deleted manually. Crossplane will detect the drift and recreate it."
info "Watch with: kubectl get bucket.s3.aws.upbound.io -w"
info "The SYNCED and READY columns will temporarily show False, then recover."
wait_for_user

echo ""
echo "============================================"
echo "  Demo Complete!"
echo "============================================"
echo ""
echo "Try more experiments:"
echo "  - Apply crossplane/bucket-real-aws.yaml with real AWS creds"
echo "  - Modify the Composition to add encryption or lifecycle rules"
echo "  - Create multiple claims to see how the platform API works"
echo "  - Delete a Crossplane-managed bucket and watch it self-heal"
