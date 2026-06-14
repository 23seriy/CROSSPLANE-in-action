# Troubleshooting Guide

## Installation & Prerequisites

### "command not found: minikube" or "command not found: kubectl"

The `01-install-prerequisites.sh` script installs tools via Homebrew. If it failed:

```bash
chmod +x scripts/01-install-prerequisites.sh
./scripts/01-install-prerequisites.sh
```

Or manually install:
```bash
brew install minikube kubectl helm
```

### "Docker Desktop is not running"

Start Docker Desktop before running the cluster setup:
```bash
open /Applications/Docker.app
```

Wait for the "Docker Desktop is running" message in the menu bar.

### "Minikube failed to start" or "Error allocating requested resources"

Minikube needs ~8GB RAM for Crossplane (providers are heavier than typical workloads). Check your available memory:

```bash
vm_memory=$(sysctl hw.memsize | awk '{print $2 / 1024 / 1024 / 1024}')
echo "Available memory: ${vm_memory}GB"
```

If under 10GB total, try:
- Closing unused applications
- Reducing Docker Desktop's memory limit in **Preferences → Resources → Memory**
- Running `./scripts/05-teardown.sh` to free the previous cluster's memory

### "Homebrew: command not found"

Install Homebrew first:
```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

---

## Cluster Setup Issues

### "Crossplane Helm chart failed to install"

If the Crossplane installation fails:

```bash
# Check if the Helm repo is accessible
helm repo list | grep crossplane
helm repo update

# Check cluster resources
kubectl top nodes 2>/dev/null || echo "metrics-server not available"
kubectl get pods -n crossplane-system
```

Common causes:
- **Insufficient memory** — Crossplane + RBAC manager need ~1GB
- **Helm repo not found** — run `helm repo add crossplane-stable https://charts.crossplane.io/stable`

**Fix:** Delete and reinstall:
```bash
helm uninstall crossplane -n crossplane-system
./scripts/02-start-cluster.sh
```

### "Crossplane deployment not ready"

```bash
kubectl get deployments -n crossplane-system
kubectl get pods -n crossplane-system -o wide
kubectl get events -n crossplane-system --sort-by=.metadata.creationTimestamp | tail -20
```

If pods are in `Pending` state, you likely need more resources:
```bash
minikube delete -p crossplane-demo
minikube start --profile=crossplane-demo --cpus=4 --memory=8192 --driver=docker --kubernetes-version=v1.32.0
```

---

## Provider Issues

### "Provider stuck at Installed=True / Healthy=False"

After applying `provider-aws.yaml`, the provider may take 3-5 minutes to become healthy:

```bash
kubectl get providers
kubectl describe provider provider-aws-s3
kubectl get pods -n crossplane-system
```

Common causes:
- **Still downloading** — provider images are ~200MB
- **Insufficient RBAC** — check if RBAC manager is running
- **Resource limits** — provider pods need ~256MB RAM each

```bash
# Watch provider pods
kubectl get pods -n crossplane-system -w

# Check provider logs
kubectl logs -n crossplane-system -l pkg.crossplane.io/revision --tail=30
```

### "Provider pod is in CrashLoopBackOff"

```bash
kubectl logs -n crossplane-system -l pkg.crossplane.io/revision --previous --tail=50
```

**Fix:** Delete the provider and reinstall:
```bash
kubectl delete provider provider-aws-s3
kubectl apply -f crossplane/provider-aws.yaml
kubectl wait --for=condition=healthy provider.pkg/provider-aws-s3 --timeout=300s
```

---

## Managed Resource Issues

### "Bucket stuck at SYNCED=False / READY=False"

This is the most common issue. Check the resource conditions:

```bash
kubectl describe bucket.s3.aws.upbound.io <bucket-name>
```

Look for the `Status.Conditions` section. Common causes:

| Condition Message | Cause | Fix |
|---|---|---|
| `cannot get credentials` | Secret doesn't exist or wrong key | Check `kubectl get secret -n crossplane-system` |
| `no such host` | Wrong endpoint URL in ProviderConfig | Fix the endpoint URL |
| `connection refused` | Backend not reachable | Check LocalStack is running |
| `cannot get referenced ProviderConfig` | Typo in `providerConfigRef.name` | Compare with `kubectl get providerconfig` |

### "Bucket provisioned but API can't access it"

The resource-api connects to LocalStack directly, while Crossplane provisions via the provider. Check:

```bash
# Verify bucket exists in LocalStack
kubectl exec deployment/localstack -n crossplane-demo -- awslocal s3 ls

# Check resource-api config
kubectl get configmap resource-api-config -n crossplane-demo -o yaml

# Verify S3 endpoint matches
kubectl logs deployment/resource-api -n crossplane-demo --tail=10
```

### "Drift detection not working"

Crossplane's poll interval is typically 1-10 minutes. After deleting a resource directly:

```bash
# Delete bucket directly in LocalStack
kubectl exec deployment/localstack -n crossplane-demo -- awslocal s3 rb s3://crossplane-demo-bucket --force

# Wait and watch
kubectl get bucket.s3.aws.upbound.io -w
```

If the bucket doesn't reappear after 5 minutes, check:
```bash
kubectl describe bucket.s3.aws.upbound.io crossplane-demo-bucket
kubectl logs -n crossplane-system -l pkg.crossplane.io/revision --tail=30
```

---

## Composition & XRD Issues

### "XRD not creating CRDs"

After applying the XRD:
```bash
kubectl get xrd
kubectl get crd | grep objectstorage
```

If the CRD isn't created:
```bash
kubectl describe xrd xobjectstorages.demo.crossplane.io
```

### "Composition not creating resources"

```bash
# Check if function-patch-and-transform is healthy
kubectl get functions
kubectl describe function function-patch-and-transform

# Check composite resource status
kubectl get xobjectstorages
kubectl describe xobjectstorages <name>
```

### "Claim stuck in pending"

```bash
kubectl get objectstorages -n crossplane-demo
kubectl describe objectstorage <name> -n crossplane-demo

# Check the composite resource it created
kubectl get xobjectstorages
kubectl describe xobjectstorages <name>
```

---

## Stuck Finalizer Issues

### "Resource stuck in Terminating"

When `kubectl delete` hangs:

```bash
# Check finalizers
kubectl get bucket.s3.aws.upbound.io <name> -o jsonpath='{.metadata.finalizers}'

# Check if provider can reach backend
kubectl logs -n crossplane-system -l pkg.crossplane.io/revision --tail=10
```

**Fix (nuclear option — only if external resource is already gone):**
```bash
kubectl patch bucket.s3.aws.upbound.io <name> \
  --type json -p '[{"op":"remove","path":"/metadata/finalizers"}]'
```

### "Namespace stuck in Terminating"

If the namespace won't delete because of Crossplane resources:

```bash
# Find resources blocking deletion
kubectl api-resources --verbs=list --namespaced -o name | xargs -n 1 kubectl get --show-kind --ignore-not-found -n crossplane-demo

# Force-remove finalizers from stuck resources
kubectl get bucket.s3.aws.upbound.io -o name | xargs -I{} kubectl patch {} --type json -p '[{"op":"remove","path":"/metadata/finalizers"}]'
```

---

## App Deployment Issues

### "Error building Docker image"

The `03-deploy-app.sh` script builds images using Minikube's Docker daemon:

```bash
# Ensure you're using Minikube's Docker daemon
eval $(minikube -p crossplane-demo docker-env)

# Build manually
docker build -t crossplane-demo/resource-api:latest apps/resource-api
```

If the build fails:
1. Check Docker Desktop is running
2. Check disk space: `docker system df`
3. Clean up: `docker system prune -a --volumes`

### "ImagePullBackOff" or "ErrImageNeverPull"

The resource-api uses `imagePullPolicy: Never` (built locally in Minikube). Ensure:
```bash
# Build in Minikube's Docker daemon (NOT host Docker)
eval $(minikube -p crossplane-demo docker-env)
docker build -t crossplane-demo/resource-api:latest apps/resource-api

# Restart the deployment
kubectl rollout restart deployment/resource-api -n crossplane-demo
```

---

## Cleanup & Removal

### "Teardown script failed"

If `05-teardown.sh` fails midway:

```bash
# Manually clean up remaining resources
kubectl delete xobjectstorages --all --timeout=30s
kubectl delete bucket.s3.aws.upbound.io --all --wait=false
kubectl delete bucketversioning.s3.aws.upbound.io --all --wait=false
kubectl delete compositions --all --timeout=30s
kubectl delete xrd --all --timeout=30s
helm uninstall crossplane -n crossplane-system

# Delete the cluster
minikube delete -p crossplane-demo
```

### "Cluster is stuck in a weird state"

Nuclear option (destroys everything):
```bash
./scripts/05-teardown.sh
minikube delete -p crossplane-demo --purge
rm -rf ~/.minikube/profiles/crossplane-demo
rm -rf ~/.minikube/machines/crossplane-demo
```

Then start fresh:
```bash
./scripts/02-start-cluster.sh
./scripts/03-deploy-app.sh
```

---

## Getting More Help

### Enable Debug Logging

For Crossplane:
```bash
# Check Crossplane core logs
kubectl logs -n crossplane-system deploy/crossplane --tail=50

# Check RBAC manager
kubectl logs -n crossplane-system deploy/crossplane-rbac-manager --tail=50

# Check provider logs (most useful for managed resource issues)
kubectl logs -n crossplane-system -l pkg.crossplane.io/revision --tail=50
```

For scripts (bash):
```bash
bash -x scripts/04-demo-scenarios.sh 2>&1 | tee debug.log
```

For Kubernetes API calls:
```bash
kubectl --v=8 get pods  # 0-10, higher = more verbose
```

### Collect Diagnostics

```bash
# Minikube status
minikube status -p crossplane-demo
minikube logs -p crossplane-demo --tail=100

# Cluster info
kubectl cluster-info dump --output-directory=./cluster-dump

# Crossplane status
kubectl get all -n crossplane-system
kubectl get providers
kubectl get managed
kubectl get events --sort-by=.metadata.creationTimestamp | tail -30
```

### Report a Bug

If you can't solve it, open an issue on GitHub with:
1. The exact command that failed
2. The error message
3. Output of the diagnostics above
4. Your system info: `uname -a`, `minikube version`, `kubectl version`

---

## Quick Reference

| Issue | Command |
|-------|---------|
| Crossplane logs | `kubectl logs -n crossplane-system deploy/crossplane --tail=50` |
| Provider logs | `kubectl logs -n crossplane-system -l pkg.crossplane.io/revision --tail=50` |
| All providers | `kubectl get providers` |
| All managed resources | `kubectl get managed` |
| All ProviderConfigs | `kubectl get providerconfig` |
| Describe a resource | `kubectl describe bucket.s3.aws.upbound.io <name>` |
| Check events | `kubectl get events --sort-by=.metadata.creationTimestamp` |
| Check finalizers | `kubectl get <resource> -o yaml \| grep -A5 finalizers` |
| Delete cluster | `minikube delete -p crossplane-demo` |

---

Still stuck? Check the [Crossplane docs](https://docs.crossplane.io/) or open an issue! ☁️
