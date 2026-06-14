# Testing Guide

This document describes how to test crossplane-in-action and validate changes before submitting a pull request.

## Automated Testing

### Local Validation

Before pushing, run the validation suite locally:

```bash
# Check shell scripts
shellcheck -x scripts/*.sh

# Validate YAML
for file in k8s/*.yaml crossplane/*.yaml; do
  kubectl apply -f "$file" --dry-run=client -o yaml > /dev/null 2>&1 && echo "✓ $file" || echo "✗ $file"
done

# Check Go code
cd apps/resource-api && go vet ./... && go build -o /dev/null . && cd ../..

# Lint Dockerfiles (if hadolint installed)
hadolint apps/resource-api/Dockerfile
```

### GitHub Actions

The repository includes automated validation via GitHub Actions (`.github/workflows/validate.yml`). Checks run on every push and pull request:

- **Shell linting** — `shellcheck` validates all scripts
- **YAML validation** — `yamllint` checks Kubernetes manifests and Crossplane resources
- **Crossplane resource syntax** — Python-based YAML structure validation
- **Go build and vet** — Ensures `resource-api` compiles and passes `go vet`
- **Dockerfile linting** — `hadolint` checks Dockerfiles
- **Documentation completeness** — Ensures all required files exist
- **Markdown linting** — Checks documentation formatting

## Manual Testing

### Full Demo Run

The most comprehensive test is running the full demo:

```bash
./scripts/01-install-prerequisites.sh
./scripts/02-start-cluster.sh
./scripts/03-deploy-app.sh
./scripts/04-demo-scenarios.sh
./scripts/05-teardown.sh
```

**Expected output:** All 11 scenarios complete with ✅ checks passing.

**Time:** ~25 minutes (depends on network speed for image downloads and provider installation)

### Single Resource Test

Test a Crossplane resource in isolation:

```bash
# Validate YAML syntax without applying
kubectl apply -f crossplane/bucket-claim.yaml --dry-run=client -o yaml

# Apply and watch status
kubectl apply -f crossplane/bucket-claim.yaml
kubectl get bucket.s3.aws.upbound.io -w
```

### Scenario-Level Testing

Test a specific scenario by running just that section:

```bash
# Set up cluster (if not already done)
./scripts/02-start-cluster.sh
./scripts/03-deploy-app.sh

# Manually run scenario 4 (Provision a Bucket)
kubectl apply -f crossplane/provider-config-localstack.yaml
kubectl apply -f crossplane/bucket-claim.yaml
kubectl get bucket.s3.aws.upbound.io -w
```

### Component-Level Testing

#### Test the Go API

```bash
# Port-forward to the API
kubectl port-forward svc/resource-api 9090:8080 -n crossplane-demo &

# Health check
curl -s http://localhost:9090/health | python3 -m json.tool

# Put an object
curl -s -X POST http://localhost:9090/api/object/put \
  -H "Content-Type: application/json" \
  -d '{"key":"test.txt","content":"Hello!"}'

# List objects
curl -s http://localhost:9090/api/objects | python3 -m json.tool

# Get an object
curl -s "http://localhost:9090/api/object?key=test.txt" | python3 -m json.tool
```

#### Test LocalStack S3

```bash
# Verify LocalStack is running
kubectl exec deployment/localstack -n crossplane-demo -- awslocal s3 ls

# Create a test bucket
kubectl exec deployment/localstack -n crossplane-demo -- awslocal s3 mb s3://test-bucket

# List buckets
kubectl exec deployment/localstack -n crossplane-demo -- awslocal s3 ls
```

#### Test Crossplane Provider

```bash
# Check provider health
kubectl get providers

# Check provider pods
kubectl get pods -n crossplane-system

# Check provider logs
kubectl logs -n crossplane-system -l pkg.crossplane.io/revision --tail=20
```

#### Test ProviderConfig

```bash
# Verify ProviderConfig exists
kubectl get providerconfig

# Verify credentials Secret exists
kubectl get secret -n crossplane-system | grep creds
```

## Test Cases

### Core Functionality

| Test | Command | Expected Result |
|------|---------|-----------------|
| Install tools | `./scripts/01-install-prerequisites.sh` | All tools installed, versions printed |
| Start cluster | `./scripts/02-start-cluster.sh` | Minikube running, Crossplane deployed |
| Deploy app | `./scripts/03-deploy-app.sh` | resource-api running, LocalStack ready |
| Run demo | `./scripts/04-demo-scenarios.sh` | All 11 scenarios pass |
| Cleanup | `./scripts/05-teardown.sh` | Cluster deleted |

### Crossplane Resources

| Resource | Manifest | Expected |
|----------|----------|----------|
| Provider | `provider-aws.yaml` | Installed=True, Healthy=True |
| ProviderConfig | `provider-config-localstack.yaml` | Created, pointing to LocalStack |
| Bucket | `bucket-claim.yaml` | SYNCED=True, READY=True |
| Versioning | `bucket-with-versioning.yaml` | Bucket + BucketVersioning both Ready |
| XRD | `xrd-objectstorage.yaml` | CRD created for ObjectStorage |
| Composition | `composition-objectstorage.yaml` | Composition applied |
| Claim | `claim-objectstorage.yaml` | Composite resource created, bucket provisioned |

### Troubleshooting Scenarios

| Scenario | Manifest | Expected Failure | Fix |
|----------|----------|------------------|-----|
| Bad Credentials | `broken-bad-credentials.yaml` | SYNCED=False, "cannot get credentials" | Patch providerConfigRef to `localstack` |
| Wrong Endpoint | `broken-wrong-endpoint.yaml` | SYNCED=False, "no such host" | Patch providerConfigRef to `localstack` |
| Missing ProviderConfig | `broken-missing-providerconfig.yaml` | SYNCED=False, "cannot get referenced ProviderConfig" | Patch providerConfigRef to `localstack` |
| Stuck Finalizer | `broken-stuck-finalizer.yaml` | Stuck in Terminating | Force-remove finalizer |

## Regression Testing

When adding new features, test that existing functionality still works:

1. Run the full `04-demo-scenarios.sh` to ensure all scenarios pass
2. Verify each scenario produces expected resource states
3. Check all managed resources reach SYNCED=True / READY=True
4. Confirm troubleshooting scenarios fail as expected and fixes work

## Testing Checklist for Pull Requests

Before submitting a PR, ensure:

- [ ] `shellcheck -x scripts/*.sh` passes without warnings
- [ ] All YAML files validate: `kubectl apply -f <file> --dry-run=client` succeeds
- [ ] Go code compiles: `cd apps/resource-api && go vet ./... && go build -o /dev/null .`
- [ ] Dockerfiles lint: `hadolint apps/resource-api/Dockerfile` passes (if available)
- [ ] Full demo runs: `./scripts/04-demo-scenarios.sh` completes all 11 scenarios
- [ ] No regressions: all scenarios show expected results
- [ ] Documentation updated if behavior changed
- [ ] Commit messages follow convention: `[type] description`

## Debugging Failed Tests

### Scripts fail with syntax errors

```bash
bash -n scripts/04-demo-scenarios.sh  # Check syntax without running
bash -x scripts/04-demo-scenarios.sh  # Run with debug output
```

### Crossplane resource stuck

```bash
# Get detailed error
kubectl describe bucket.s3.aws.upbound.io <bucket-name>

# Check provider logs
kubectl logs -n crossplane-system -l pkg.crossplane.io/revision --tail=50

# Check events
kubectl get events --sort-by=.metadata.creationTimestamp | tail -20
```

### Go build fails

```bash
cd apps/resource-api
go mod tidy
go mod download
go vet ./...
go build -v .
```

## CI/CD

The GitHub Actions workflow in `.github/workflows/validate.yml` runs automatically on:
- Push to `main` or `develop`
- All pull requests

It checks:
1. Shell script syntax (shellcheck)
2. YAML structure (yamllint)
3. Crossplane resource syntax (Python validation)
4. Go build and vet
5. Dockerfile quality (hadolint)
6. Documentation completeness
7. Markdown formatting

Failures block merging. Check the workflow output in the PR status checks.

---

Questions about testing? See [TROUBLESHOOTING.md](TROUBLESHOOTING.md) or open an issue! ☁️
