#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
err()   { echo -e "${RED}[BREAK]${NC} $1"; }
fix()   { echo -e "${MAGENTA}[FIX]${NC} $1"; }
header() { echo -e "\n${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; echo -e "${CYAN}  $1${NC}"; echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"; }
break_header() { echo -e "\n${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; echo -e "${RED}  🔥 $1${NC}"; echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"; }

API_URL="http://localhost:9090"

wait_for_user() {
    echo ""
    echo -e "${YELLOW}Press Enter to continue...${NC}"
    read -r
}

echo "============================================"
echo "  Crossplane in Action — Demo Scenarios"
echo ""
echo "  Includes happy-path AND troubleshooting"
echo "  scenarios marked with 🔥 BREAK IT"
echo "============================================"
echo ""
echo "Make sure port-forward is running:"
echo "  kubectl port-forward svc/resource-api 9090:8080 -n crossplane-demo"
echo ""
echo "And in another terminal, watch Crossplane resources:"
echo "  kubectl get managed -w"
wait_for_user

# ═══════════════════════════════════════════════════════════
# HAPPY PATH — Scenario 1: Verify the App + LocalStack
# ═══════════════════════════════════════════════════════════
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

# ═══════════════════════════════════════════════════════════
# HAPPY PATH — Scenario 2: Install the AWS S3 Provider
# ═══════════════════════════════════════════════════════════
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

# ═══════════════════════════════════════════════════════════
# HAPPY PATH — Scenario 3: Configure ProviderConfig
# ═══════════════════════════════════════════════════════════
header "Scenario 3: Configure ProviderConfig for LocalStack"
info "Applying LocalStack ProviderConfig..."
kubectl apply -f "$PROJECT_DIR/crossplane/provider-config-localstack.yaml"
echo ""
info "ProviderConfig status:"
kubectl get providerconfig 2>/dev/null || kubectl get providerconfigs.aws.upbound.io 2>/dev/null || true
wait_for_user

# ═══════════════════════════════════════════════════════════
# HAPPY PATH — Scenario 4: Provision an S3 Bucket
# ═══════════════════════════════════════════════════════════
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

# ═══════════════════════════════════════════════════════════
# 🔥 BREAK IT — Scenario 5: Bad Credentials
# ═══════════════════════════════════════════════════════════
break_header "Scenario 5: BREAK IT — Bad Credentials"
err "Real-world problem: Someone deploys a ProviderConfig that references a Secret"
err "that doesn't exist. The bucket gets stuck at SYNCED=False / READY=False."
echo ""
info "Applying broken ProviderConfig + Bucket (secret 'this-secret-does-not-exist')..."
kubectl apply -f "$PROJECT_DIR/crossplane/broken-bad-credentials.yaml"
echo ""
info "Waiting 15 seconds for Crossplane to attempt reconciliation..."
sleep 15
echo ""
err "Let's see the damage:"
echo ""
info "All managed resources — notice 'broken-creds-bucket' is stuck:"
kubectl get managed 2>/dev/null || true
echo ""
info "Describe the broken bucket to find the root cause:"
kubectl describe bucket.s3.aws.upbound.io broken-creds-bucket 2>/dev/null | tail -20 || true
echo ""
warn "──────────────────────────────────────────────"
warn "DIAGNOSIS: Look at the Events and Conditions above."
warn "You'll see 'cannot get credentials' or 'secret not found'."
warn "This is the #1 on-call issue with Crossplane in production."
warn "──────────────────────────────────────────────"
wait_for_user

fix "Fixing: Patch the bucket to use the working 'localstack' ProviderConfig..."
kubectl patch bucket.s3.aws.upbound.io broken-creds-bucket \
    --type merge -p '{"spec":{"providerConfigRef":{"name":"localstack"}}}' 2>/dev/null || true
echo ""
info "Waiting 15 seconds for Crossplane to reconcile with correct credentials..."
sleep 15
echo ""
info "Bucket status after fix:"
kubectl get bucket.s3.aws.upbound.io broken-creds-bucket 2>/dev/null || true
echo ""
info "Cleaning up broken ProviderConfig..."
kubectl delete providerconfig bad-creds 2>/dev/null || true
kubectl delete bucket.s3.aws.upbound.io broken-creds-bucket 2>/dev/null || true
wait_for_user

# ═══════════════════════════════════════════════════════════
# 🔥 BREAK IT — Scenario 6: Wrong Endpoint
# ═══════════════════════════════════════════════════════════
break_header "Scenario 6: BREAK IT — Wrong Endpoint (Provider Can't Reach Backend)"
err "Real-world problem: The ProviderConfig points to the wrong URL."
err "Credentials are fine, but the provider can't connect to the cloud API."
err "This happens when someone changes a VPC endpoint, swaps environments,"
err "or has a typo in the service URL."
echo ""
info "Applying ProviderConfig pointing to 'localstack-typo:9999' (dead endpoint)..."
kubectl apply -f "$PROJECT_DIR/crossplane/broken-wrong-endpoint.yaml"
echo ""
info "Waiting 20 seconds for the connection to fail..."
sleep 20
echo ""
err "Let's investigate:"
echo ""
info "Bucket status — SYNCED and READY should both be False:"
kubectl get bucket.s3.aws.upbound.io broken-endpoint-bucket 2>/dev/null || true
echo ""
info "Describe the bucket for error details:"
kubectl describe bucket.s3.aws.upbound.io broken-endpoint-bucket 2>/dev/null | tail -20 || true
echo ""
info "Provider pod logs (look for connection errors):"
kubectl logs -n crossplane-system -l pkg.crossplane.io/revision --tail=10 2>/dev/null | grep -i "error\|refused\|no such host\|timeout" | head -5 || true
echo ""
warn "──────────────────────────────────────────────"
warn "DIAGNOSIS: The provider can't resolve 'localstack-typo'."
warn "You'll see 'no such host' or 'connection refused' in the"
warn "describe output and/or provider logs."
warn ""
warn "Key debug commands:"
warn "  kubectl describe <managed-resource>     — check Status.Conditions"
warn "  kubectl logs -n crossplane-system -l pkg.crossplane.io/revision"
warn "  kubectl get events --field-selector reason=CannotObserveExternalResource"
warn "──────────────────────────────────────────────"
wait_for_user

fix "Fixing: Patch the bucket to use the working 'localstack' ProviderConfig..."
kubectl patch bucket.s3.aws.upbound.io broken-endpoint-bucket \
    --type merge -p '{"spec":{"providerConfigRef":{"name":"localstack"}}}' 2>/dev/null || true
echo ""
info "Waiting 15 seconds for recovery..."
sleep 15
echo ""
info "Bucket status after fix:"
kubectl get bucket.s3.aws.upbound.io broken-endpoint-bucket 2>/dev/null || true
echo ""
info "Cleaning up..."
kubectl delete bucket.s3.aws.upbound.io broken-endpoint-bucket 2>/dev/null || true
kubectl delete providerconfig wrong-endpoint 2>/dev/null || true
kubectl delete secret wrong-endpoint-creds -n crossplane-system 2>/dev/null || true
wait_for_user

# ═══════════════════════════════════════════════════════════
# 🔥 BREAK IT — Scenario 7: Missing ProviderConfig
# ═══════════════════════════════════════════════════════════
break_header "Scenario 7: BREAK IT — Missing ProviderConfig Reference"
err "Real-world problem: A bucket references ProviderConfig 'production'"
err "but that config was never created. This is the most common Crossplane"
err "mistake — a typo in providerConfigRef or deploying to a new cluster"
err "where the ProviderConfig hasn't been set up yet."
echo ""
info "Applying a bucket that references non-existent ProviderConfig 'production'..."
kubectl apply -f "$PROJECT_DIR/crossplane/broken-missing-providerconfig.yaml"
echo ""
info "Waiting 10 seconds..."
sleep 10
echo ""
err "Let's investigate:"
echo ""
info "Bucket status — stuck at SYNCED=False:"
kubectl get bucket.s3.aws.upbound.io orphan-bucket 2>/dev/null || true
echo ""
info "Describe for the error message:"
kubectl describe bucket.s3.aws.upbound.io orphan-bucket 2>/dev/null | tail -15 || true
echo ""
info "What ProviderConfigs actually exist?"
kubectl get providerconfig 2>/dev/null || kubectl get providerconfigs.aws.upbound.io 2>/dev/null || true
echo ""
warn "──────────────────────────────────────────────"
warn "DIAGNOSIS: 'cannot get referenced ProviderConfig'"
warn "The bucket wants 'production' but only 'localstack' exists."
warn ""
warn "In production, this happens when:"
warn "  - ProviderConfigs are managed by a different team"
warn "  - You deployed to the wrong cluster"
warn "  - The ProviderConfig name changed but consumers weren't updated"
warn "──────────────────────────────────────────────"
wait_for_user

fix "Fixing: Patch the bucket to use the existing 'localstack' ProviderConfig..."
kubectl patch bucket.s3.aws.upbound.io orphan-bucket \
    --type merge -p '{"spec":{"providerConfigRef":{"name":"localstack"}}}' 2>/dev/null || true
echo ""
info "Waiting 15 seconds for reconciliation..."
sleep 15
echo ""
info "Bucket status after fix:"
kubectl get bucket.s3.aws.upbound.io orphan-bucket 2>/dev/null || true
echo ""
info "Cleaning up..."
kubectl delete bucket.s3.aws.upbound.io orphan-bucket 2>/dev/null || true
wait_for_user

# ═══════════════════════════════════════════════════════════
# HAPPY PATH — Scenario 8: Bucket with Versioning
# ═══════════════════════════════════════════════════════════
header "Scenario 8: Bucket with Versioning"
info "Applying bucket + versioning configuration..."
kubectl apply -f "$PROJECT_DIR/crossplane/bucket-with-versioning.yaml"
echo ""
info "Managed resources after adding versioning:"
kubectl get managed 2>/dev/null || true
wait_for_user

# ═══════════════════════════════════════════════════════════
# HAPPY PATH — Scenario 9: Compositions + XRDs
# ═══════════════════════════════════════════════════════════
header "Scenario 9: Platform Abstraction with XRD + Composition"
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

# ═══════════════════════════════════════════════════════════
# HAPPY PATH — Scenario 10: Drift Detection
# ═══════════════════════════════════════════════════════════
header "Scenario 10: Drift Detection — Delete the Bucket, Watch Crossplane Recreate It"
info "Deleting the bucket directly in LocalStack..."
kubectl exec deployment/localstack -n crossplane-demo -- \
    awslocal s3 rb s3://crossplane-demo-bucket --force 2>/dev/null || true
echo ""
info "Bucket deleted manually. Crossplane will detect the drift and recreate it."
info "Watch with: kubectl get bucket.s3.aws.upbound.io -w"
info "The SYNCED and READY columns will temporarily show False, then recover."
wait_for_user

# ═══════════════════════════════════════════════════════════
# 🔥 BREAK IT — Scenario 11: Stuck Finalizer on Delete
# ═══════════════════════════════════════════════════════════
break_header "Scenario 11: BREAK IT — Stuck Finalizer (Can't Delete a Resource)"
err "Real-world problem: You need to delete a Crossplane-managed resource,"
err "but the provider can't reach the backend to confirm deletion."
err "The K8s object gets stuck in 'Terminating' forever because the"
err "finalizer can't be released."
echo ""
info "Setting up: creating broken ProviderConfig + Bucket tied to dead endpoint..."
kubectl apply -f "$PROJECT_DIR/crossplane/broken-wrong-endpoint.yaml"
echo ""
info "Waiting 10 seconds for the resource to exist..."
sleep 10
echo ""
info "Now applying the finalizer-test bucket on the broken endpoint..."
kubectl apply -f "$PROJECT_DIR/crossplane/broken-stuck-finalizer.yaml"
sleep 5
echo ""

err "Attempting to delete the bucket (this will hang because provider can't reach backend)..."
kubectl delete bucket.s3.aws.upbound.io finalizer-test-bucket --wait=false 2>/dev/null || true
echo ""
info "Waiting 10 seconds..."
sleep 10
echo ""
err "Let's check — the resource should be stuck in 'Terminating':"
kubectl get bucket.s3.aws.upbound.io finalizer-test-bucket 2>/dev/null || true
echo ""
info "Check the finalizers blocking deletion:"
kubectl get bucket.s3.aws.upbound.io finalizer-test-bucket -o jsonpath='{.metadata.finalizers}' 2>/dev/null || true
echo ""
echo ""
warn "──────────────────────────────────────────────"
warn "DIAGNOSIS: The object has a finalizer that the provider"
warn "can't release because it can't connect to the backend."
warn ""
warn "This is dangerous in production:"
warn "  - Can't delete the namespace (namespace stuck in Terminating)"
warn "  - Can't uninstall the provider (resources still reference it)"
warn "  - Blocks cluster cleanup and terraform destroy"
warn ""
warn "Nuclear option: manually remove the finalizer."
warn "Only do this if you're sure the external resource is already gone."
warn "──────────────────────────────────────────────"
wait_for_user

fix "Force-removing the finalizer to unstick the deletion..."
kubectl patch bucket.s3.aws.upbound.io finalizer-test-bucket \
    --type json -p '[{"op":"remove","path":"/metadata/finalizers"}]' 2>/dev/null || true
echo ""
info "Waiting 5 seconds..."
sleep 5
echo ""
info "Bucket should now be gone:"
kubectl get bucket.s3.aws.upbound.io finalizer-test-bucket 2>/dev/null && err "Still exists!" || info "Successfully deleted!"
echo ""
info "Cleaning up remaining broken resources..."
kubectl delete bucket.s3.aws.upbound.io broken-endpoint-bucket --wait=false 2>/dev/null || true
kubectl patch bucket.s3.aws.upbound.io broken-endpoint-bucket \
    --type json -p '[{"op":"remove","path":"/metadata/finalizers"}]' 2>/dev/null || true
kubectl delete providerconfig wrong-endpoint 2>/dev/null || true
kubectl delete secret wrong-endpoint-creds -n crossplane-system 2>/dev/null || true
wait_for_user

echo ""
echo "============================================"
echo "  Demo Complete!"
echo "============================================"
echo ""
echo "Scenarios covered:"
echo "  ✅ 1.  App + LocalStack verification"
echo "  ✅ 2.  Provider installation"
echo "  ✅ 3.  ProviderConfig setup"
echo "  ✅ 4.  Bucket provisioning via CRD"
echo "  🔥 5.  TROUBLESHOOT: Bad credentials"
echo "  🔥 6.  TROUBLESHOOT: Wrong endpoint"
echo "  🔥 7.  TROUBLESHOOT: Missing ProviderConfig"
echo "  ✅ 8.  Bucket with versioning"
echo "  ✅ 9.  XRD + Composition (platform API)"
echo "  ✅ 10. Drift detection (self-healing)"
echo "  🔥 11. TROUBLESHOOT: Stuck finalizer on delete"
echo ""
echo "Key debugging commands to remember:"
echo "  kubectl describe <resource>                         — check Status.Conditions"
echo "  kubectl get managed                                 — overview of all resources"
echo "  kubectl logs -n crossplane-system -l pkg.crossplane.io/revision"
echo "  kubectl get events --sort-by=.metadata.creationTimestamp"
echo "  kubectl get <resource> -o yaml | grep -A5 finalizers"
echo ""
echo "Try more experiments:"
echo "  - Apply crossplane/bucket-real-aws.yaml with real AWS creds"
echo "  - Modify the Composition to add encryption or lifecycle rules"
echo "  - Create multiple claims to see how the platform API works"
echo "  - Delete a Crossplane-managed bucket and watch it self-heal"
