# ☁️ Crossplane in Action

A hands-on project for learning **Crossplane** — the Kubernetes-native way to provision and manage cloud infrastructure. Instead of writing Terraform or clicking through the AWS console, you define S3 buckets (and more) as Kubernetes CRDs and let Crossplane reconcile them into reality.

The demo uses a Go microservice that reads and writes objects to an S3 bucket provisioned entirely by Crossplane. During development, **LocalStack** simulates AWS locally so you can experiment without any cloud bill. When you're ready, swap one line in the ProviderConfig to target real AWS.

![Crossplane](https://img.shields.io/badge/Crossplane-1.16-7B61FF?logo=crossplane&logoColor=white)
![Kubernetes](https://img.shields.io/badge/Kubernetes-1.32-326CE5?logo=kubernetes&logoColor=white)
![Minikube](https://img.shields.io/badge/Minikube-local-F7B93E?logo=kubernetes&logoColor=white)
![Go](https://img.shields.io/badge/Go-1.22-00ADD8?logo=go&logoColor=white)
![CI](https://github.com/23seriy/crossplane-in-action/actions/workflows/validate.yml/badge.svg)
![License](https://img.shields.io/badge/License-MIT-green.svg)

> 📝 **Published article:** [Crossplane in Action: Provisioning AWS Resources from Kubernetes on Your Laptop](https://medium.com/@sergeiolshanetski/crossplane-in-action-provisioning-aws-resources-from-kubernetes-on-your-laptop-692d3aa35c6a)

## 🏗️ Architecture

```text
                 ┌──────────────────────────────────────────────────┐
                 │                 Minikube Cluster                  │
                 │                                                  │
 User ────────►  │  resource-api ──────────► S3 Bucket              │
 localhost:9090 │  (Go, port 8080)         (LocalStack / AWS)      │
                 │       │                                          │
                 │       └── PUT / GET / LIST objects                │
                 │                                                  │
                 │         Crossplane watches Bucket CRDs           │
                 │                     │                             │
                 │                     ▼                             │
                 │    Provider AWS S3 ────► LocalStack:4566          │
                 │    (or real AWS)         (local S3 simulator)     │
                 │                                                  │
                 │    XRD + Composition ── Platform API              │
                 │    "ObjectStorage" claim → Bucket + Versioning   │
                 └──────────────────────────────────────────────────┘
```

## 📋 What You'll Learn

| Crossplane Concept | What It Does | Demo Scenario |
|---|---|---|
| **Managed Resources** | Declare cloud resources as K8s CRDs | Create an S3 Bucket with `kubectl apply` |
| **Providers** | Connect Crossplane to a cloud API | Install `provider-aws-s3` |
| **ProviderConfig** | Supply credentials and endpoint | LocalStack for dev, real AWS for prod |
| **Drift Detection** | Self-heal when reality diverges from desired state | Delete a bucket manually, watch it reappear |
| **CompositeResourceDefinition (XRD)** | Define your own platform API | `ObjectStorage` kind with region + versioning params |
| **Composition** | Implement the platform API with real resources | Map `ObjectStorage` → S3 Bucket + BucketVersioning |
| **Claims** | Namespace-scoped requests for composite resources | Dev team requests storage without knowing S3 internals |
| 🔥 **Bad Credentials** | Secret doesn't exist or has wrong keys | Bucket stuck at SYNCED=False — diagnose and fix |
| 🔥 **Wrong Endpoint** | Provider can't reach the cloud API | Connection refused — read provider logs to find the cause |
| 🔥 **Missing ProviderConfig** | Resource references a config that doesn't exist | Most common Crossplane mistake — compare names and patch |
| 🔥 **Stuck Finalizer** | Can't delete a resource because provider is unreachable | Force-remove finalizer to unstick Terminating objects |

## 🚀 Quick Start

### Step 0: Clone the Repository

```bash
git clone https://github.com/23seriy/crossplane-in-action.git
cd crossplane-in-action
```

### Prerequisites

- **macOS**
- **Docker Desktop** running
- **Homebrew** installed
- ~8 GB RAM available for Minikube (Crossplane + provider pods are heavier than KEDA/Istio)

### Step 1: Install Tools

```bash
chmod +x scripts/*.sh
./scripts/01-install-prerequisites.sh
```

This installs or verifies `minikube`, `kubectl`, `helm`, and `docker`.

### Step 2: Start Cluster + Install Crossplane

```bash
./scripts/02-start-cluster.sh
```

Creates a Minikube profile called `crossplane-demo` on **Kubernetes `v1.32.0`**, installs Crossplane with Helm, and waits for the operator and RBAC manager to be ready.

### Step 3: Build & Deploy the Demo

```bash
./scripts/03-deploy-app.sh
```

Builds the Go `resource-api` image inside Minikube's Docker daemon, deploys LocalStack as a local S3 simulator, creates the demo bucket, and starts the API service.

### Step 4: Access the Resource API

In a separate terminal:

```bash
kubectl port-forward svc/resource-api 9090:8080 -n crossplane-demo
```

Then try:

```bash
# Health check
curl http://localhost:9090/health

# Put an object
curl -X POST http://localhost:9090/api/object/put \
  -H "Content-Type: application/json" \
  -d '{"key":"hello.txt","content":"Hello from Crossplane!"}'

# List objects
curl http://localhost:9090/api/objects

# Get an object
curl "http://localhost:9090/api/object?key=hello.txt"
```

### Step 5: Run Guided Scenarios

```bash
./scripts/04-demo-scenarios.sh
```

## 🎮 Demo Scenarios

The demo includes **7 happy-path scenarios** and **4 troubleshooting scenarios** (marked with 🔥). Troubleshooting scenarios intentionally break things, teach you how to diagnose them, then fix them — just like real on-call work.

### 1. Verify the App + LocalStack S3

Test the resource-api against LocalStack. Confirm read/write operations work before introducing Crossplane.

### 2. Install the AWS S3 Provider

```bash
kubectl apply -f crossplane/provider-aws.yaml
kubectl get providers
```

Installs `provider-aws-s3` from Upbound's marketplace. Takes 4-5 minutes to become healthy.

### 3. Configure ProviderConfig for LocalStack

```bash
kubectl apply -f crossplane/provider-config-localstack.yaml
```

Points Crossplane at `localstack:4566` instead of real AWS. Uses dummy credentials (`test`/`test`).

### 4. Provision an S3 Bucket via Crossplane

```bash
kubectl apply -f crossplane/bucket-claim.yaml
kubectl get bucket.s3.aws.upbound.io -w
```

Watch the bucket transition from `False`/`False` to `True`/`True` as Crossplane provisions it. This is the "aha moment" — you just created an S3 bucket with `kubectl apply`.

### 🔥 5. BREAK IT — Bad Credentials

```bash
kubectl apply -f crossplane/broken-bad-credentials.yaml
kubectl describe bucket.s3.aws.upbound.io broken-creds-bucket
```

A ProviderConfig references a Secret that doesn't exist. The bucket gets stuck at `SYNCED=False` / `READY=False`. Learn to read the `Status.Conditions` and Events to find "cannot get credentials."

**Fix and cleanup:**

```bash
kubectl patch bucket.s3.aws.upbound.io broken-creds-bucket \
  --type merge -p '{"spec":{"providerConfigRef":{"name":"localstack"}}}'
kubectl delete providerconfigs.aws.upbound.io bad-creds
kubectl delete bucket.s3.aws.upbound.io broken-creds-bucket
```

### 🔥 6. BREAK IT — Wrong Endpoint

```bash
kubectl apply -f crossplane/broken-wrong-endpoint.yaml
kubectl describe bucket.s3.aws.upbound.io broken-endpoint-bucket
kubectl logs -n crossplane-system -l pkg.crossplane.io/revision --tail=10
```

Credentials are correct but the endpoint URL is wrong (`localstack-typo:9999`). The provider can't connect. Learn to read provider pod logs for "no such host" and "connection refused" errors.

**Fix and cleanup:**

```bash
kubectl patch bucket.s3.aws.upbound.io broken-endpoint-bucket \
  --type merge -p '{"spec":{"providerConfigRef":{"name":"localstack"}}}'
kubectl delete bucket.s3.aws.upbound.io broken-endpoint-bucket
kubectl delete providerconfigs.aws.upbound.io wrong-endpoint
kubectl delete secret wrong-endpoint-creds -n crossplane-system
```

### 🔥 7. BREAK IT — Missing ProviderConfig Reference

```bash
kubectl apply -f crossplane/broken-missing-providerconfig.yaml
kubectl describe bucket.s3.aws.upbound.io orphan-bucket
kubectl get providerconfig
```

The #1 most common Crossplane mistake: a bucket references ProviderConfig `production` that was never created. Learn to compare what exists vs. what's referenced, and patch the reference to fix it.

**Fix and cleanup:**

```bash
kubectl patch bucket.s3.aws.upbound.io orphan-bucket \
  --type merge -p '{"spec":{"providerConfigRef":{"name":"localstack"}}}'
kubectl delete bucket.s3.aws.upbound.io orphan-bucket
```

### 8. Bucket with Versioning

```bash
kubectl apply -f crossplane/bucket-with-versioning.yaml
kubectl get bucket.s3.aws.upbound.io,bucketversioning.s3.aws.upbound.io
```

Shows how Crossplane manages multiple related resources (Bucket + BucketVersioning) declaratively.

### 9. Platform Abstraction — XRD + Composition

```bash
kubectl apply -f crossplane/function-patch-and-transform.yaml
kubectl wait --for=condition=healthy function.pkg/function-patch-and-transform --timeout=300s
kubectl apply -f crossplane/xrd-objectstorage.yaml
kubectl apply -f crossplane/composition-objectstorage.yaml
kubectl apply -f crossplane/claim-objectstorage.yaml
```

Creates a custom `XObjectStorage` API using pipeline-mode Compositions. Dev teams request storage with simple parameters (region, versioning) — the Composition handles the S3 details.

### 10. Drift Detection — Self-Healing Infrastructure

```bash
# Delete the bucket directly in LocalStack
kubectl exec deployment/localstack -n crossplane-demo -- awslocal s3 rb s3://crossplane-demo-bucket --force

# Watch Crossplane recreate it
kubectl get bucket.s3.aws.upbound.io -w
```

This is Crossplane's killer feature: continuous reconciliation. If someone deletes a bucket manually, Crossplane detects the drift and recreates it — just like Kubernetes recreates a deleted Pod.

### 🔥 11. BREAK IT — Stuck Finalizer on Delete

```bash
# Step 1: Create a bucket on the working config (so it gets a finalizer)
kubectl apply -f crossplane/broken-stuck-finalizer.yaml
kubectl wait --for=condition=ready bucket.s3.aws.upbound.io/finalizer-test-bucket --timeout=60s

# Step 2: Switch it to a dead endpoint
kubectl apply -f crossplane/broken-wrong-endpoint.yaml
kubectl patch bucket.s3.aws.upbound.io finalizer-test-bucket \
  --type merge -p '{"spec":{"providerConfigRef":{"name":"wrong-endpoint"}}}'

# Step 3: Try to delete — it will hang
kubectl delete bucket.s3.aws.upbound.io finalizer-test-bucket --wait=false
sleep 15
kubectl get bucket.s3.aws.upbound.io finalizer-test-bucket
# Shows "Terminating" but never disappears

# Check the finalizers blocking deletion
kubectl get bucket.s3.aws.upbound.io finalizer-test-bucket -o yaml | grep -A5 finalizers

# Nuclear option: force-remove the finalizer
kubectl patch bucket.s3.aws.upbound.io finalizer-test-bucket \
  --type json -p '[{"op":"remove","path":"/metadata/finalizers"}]'
```

The bucket must be created on a working config first so the provider adds a finalizer. Then switching to a dead endpoint and deleting simulates the real-world scenario: the provider can't confirm the external resource was deleted, so the finalizer blocks `kubectl delete` forever. Learn when and how to safely force-remove finalizers.

## 🔧 Troubleshooting Cheat Sheet

| Symptom | Likely Cause | Debug Command |
|---|---|---|
| `SYNCED=False` / `READY=False` | Bad credentials, wrong endpoint, or missing ProviderConfig | `kubectl describe <resource>` → check Conditions |
| `cannot get credentials` | Secret doesn't exist or wrong key | `kubectl get secret -n crossplane-system` |
| `no such host` / `connection refused` | Wrong endpoint URL in ProviderConfig | `kubectl logs -n crossplane-system -l pkg.crossplane.io/revision` |
| `cannot get referenced ProviderConfig` | Typo in `providerConfigRef.name` | `kubectl get providerconfig` → compare names |
| Resource stuck in `Terminating` | Finalizer can't be released (provider unreachable) | `kubectl get <resource> -o yaml \| grep finalizers` |
| Provider stuck at `Installed=True` / `Healthy=False` | Insufficient RBAC or cluster resources | `kubectl describe provider` + `kubectl get pods -n crossplane-system` |

## 📁 Project Structure

```text
crossplane-in-action/
├── .github/                  # GitHub community and CI/CD
│   ├── workflows/validate.yml         # CI pipeline
│   ├── ISSUE_TEMPLATE/                # Bug report and feature request templates
│   ├── PULL_REQUEST_TEMPLATE.md       # PR checklist
│   ├── GOVERNANCE.md                  # Project governance
│   └── dependabot.yml                 # Automated dependency updates
├── apps/
│   └── resource-api/         # Go microservice — reads/writes S3 objects
│       ├── main.go
│       ├── go.mod
│       └── Dockerfile        # Multi-stage build, non-root user (UID 10001)
├── k8s/                      # Kubernetes manifests (with security contexts)
│   ├── namespace.yaml
│   ├── localstack.yaml       # Local AWS simulator
│   ├── resource-api.yaml     # API deployment (resource limits, security context)
│   ├── resource-api-service.yaml
│   ├── resource-api-config.yaml
│   ├── resource-api-sa.yaml
│   └── aws-credentials.yaml  # LocalStack dummy credentials
├── crossplane/               # Crossplane CRDs and configurations
│   ├── provider-aws.yaml                  # AWS S3 provider installation
│   ├── provider-config-localstack.yaml    # ProviderConfig → LocalStack
│   ├── provider-config-aws.yaml           # ProviderConfig → real AWS
│   ├── bucket-claim.yaml                  # Simple S3 bucket
│   ├── bucket-with-versioning.yaml        # Bucket + versioning
│   ├── bucket-real-aws.yaml               # Bucket on real AWS
│   ├── xrd-objectstorage.yaml             # CompositeResourceDefinition
│   ├── composition-objectstorage.yaml     # Composition (pipeline mode)
│   ├── claim-objectstorage.yaml           # XObjectStorage composite resource
│   ├── function-patch-and-transform.yaml  # Crossplane function for compositions
│   ├── broken-bad-credentials.yaml        # 🔥 Missing Secret → stuck bucket
│   ├── broken-wrong-endpoint.yaml         # 🔥 Dead endpoint → connection refused
│   ├── broken-missing-providerconfig.yaml # 🔥 Typo in providerConfigRef
│   └── broken-stuck-finalizer.yaml        # 🔥 Finalizer blocks deletion
├── scripts/                  # Automation scripts
│   ├── 01-install-prerequisites.sh
│   ├── 02-start-cluster.sh
│   ├── 03-deploy-app.sh
│   ├── 04-demo-scenarios.sh
│   └── 05-teardown.sh
├── CONTRIBUTING.md            # How to contribute
├── TESTING.md                 # Testing procedures
├── TROUBLESHOOTING.md         # Debug guide
├── SECURITY.md                # Security policy
├── CODE_OF_CONDUCT.md         # Community standards
├── CHANGELOG.md               # Release history
└── CLAUDE.md                  # Developer guide
```

## 🧹 Teardown

```bash
./scripts/05-teardown.sh
```

Deletes all Crossplane resources, uninstalls providers and Crossplane, and removes the Minikube cluster.

## 💡 Key Takeaways

1. **Infrastructure as Kubernetes resources** — `kubectl apply` an S3 bucket the same way you deploy a Pod. No separate IaC tool needed.

2. **Drift detection is automatic** — Crossplane continuously reconciles desired state with actual state. Delete a bucket manually and it comes back.

3. **Platform APIs with XRDs** — Define custom resource types like `ObjectStorage` so dev teams can self-serve without knowing cloud-provider specifics.

4. **LocalStack makes it free** — Experiment with Crossplane → AWS workflows without any cloud bill. Switch to real AWS when ready.

5. **Composable and extensible** — Start with S3, add RDS, IAM roles, or any AWS service. The same pattern applies to GCP and Azure providers.

6. **Troubleshooting is a skill** — Bad credentials, wrong endpoints, missing configs, and stuck finalizers are the real-world issues you'll hit. This project teaches you to diagnose them with `kubectl describe`, provider logs, and managed resource conditions before they become production incidents.

## 📖 Additional Documentation

| Document | Description |
|---|---|
| [CONTRIBUTING.md](CONTRIBUTING.md) | How to contribute, code standards, PR process |
| [TESTING.md](TESTING.md) | Manual and automated testing procedures |
| [TROUBLESHOOTING.md](TROUBLESHOOTING.md) | Debug guide for common Crossplane issues |
| [SECURITY.md](SECURITY.md) | Security policy and responsible disclosure |
| [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) | Community standards |
| [CHANGELOG.md](CHANGELOG.md) | Release history |
| [CLAUDE.md](CLAUDE.md) | Developer guide and architecture |

## 📚 Resources

- [Crossplane Documentation](https://docs.crossplane.io/)
- [Upbound Marketplace — AWS Providers](https://marketplace.upbound.io/providers/upbound/provider-aws-s3/)
- [Crossplane Compositions Guide](https://docs.crossplane.io/latest/concepts/compositions/)
- [LocalStack Documentation](https://docs.localstack.cloud/)
- [Minikube Documentation](https://minikube.sigs.k8s.io/docs/)

## 📝 License

MIT — Use freely for learning, demos, and presentations.
