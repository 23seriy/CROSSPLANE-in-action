# ☁️ Crossplane in Action

A hands-on project for learning **Crossplane** — the Kubernetes-native way to provision and manage cloud infrastructure. Instead of writing Terraform or clicking through the AWS console, you define S3 buckets (and more) as Kubernetes CRDs and let Crossplane reconcile them into reality.

The demo uses a Go microservice that reads and writes objects to an S3 bucket provisioned entirely by Crossplane. During development, **LocalStack** simulates AWS locally so you can experiment without any cloud bill. When you're ready, swap one line in the ProviderConfig to target real AWS.

![Crossplane](https://img.shields.io/badge/Crossplane-1.16-7B61FF?logo=crossplane&logoColor=white)
![Kubernetes](https://img.shields.io/badge/Kubernetes-1.35+-326CE5?logo=kubernetes&logoColor=white)
![Minikube](https://img.shields.io/badge/Minikube-local-F7B93E?logo=kubernetes&logoColor=white)
![Go](https://img.shields.io/badge/Go-1.22-00ADD8?logo=go&logoColor=white)

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

Creates a Minikube profile called `crossplane-demo` on **Kubernetes `v1.35.1`**, installs Crossplane with Helm, and waits for the operator and RBAC manager to be ready.

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

### 1. Verify the App + LocalStack S3

Test the resource-api against LocalStack. Confirm read/write operations work before introducing Crossplane.

### 2. Install the AWS S3 Provider

```bash
kubectl apply -f crossplane/provider-aws.yaml
kubectl get providers
```

Installs `provider-aws-s3` from Upbound's marketplace. Takes 1-2 minutes to become healthy.

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

### 5. Bucket with Versioning

```bash
kubectl apply -f crossplane/bucket-with-versioning.yaml
kubectl get managed
```

Shows how Crossplane manages multiple related resources (Bucket + BucketVersioning) declaratively.

### 6. Platform Abstraction — XRD + Composition

```bash
kubectl apply -f crossplane/xrd-objectstorage.yaml
kubectl apply -f crossplane/composition-objectstorage.yaml
kubectl apply -f crossplane/claim-objectstorage.yaml
```

Creates a custom `ObjectStorage` API. Dev teams request storage with simple parameters (region, versioning) — the Composition handles the S3 details.

### 7. Drift Detection — Self-Healing Infrastructure

```bash
# Delete the bucket directly in LocalStack
kubectl exec deployment/localstack -n crossplane-demo -- awslocal s3 rb s3://crossplane-demo-bucket --force

# Watch Crossplane recreate it
kubectl get bucket.s3.aws.upbound.io -w
```

This is Crossplane's killer feature: continuous reconciliation. If someone deletes a bucket manually, Crossplane detects the drift and recreates it — just like Kubernetes recreates a deleted Pod.

## 📁 Project Structure

```text
crossplane-in-action/
├── apps/
│   └── resource-api/         # Go microservice — reads/writes S3 objects
│       ├── main.go
│       ├── go.mod
│       └── Dockerfile
├── k8s/                      # Kubernetes manifests
│   ├── namespace.yaml
│   ├── localstack.yaml       # Local AWS simulator
│   ├── resource-api.yaml     # API deployment
│   ├── resource-api-service.yaml
│   ├── resource-api-config.yaml
│   └── resource-api-sa.yaml
├── crossplane/               # Crossplane CRDs and configurations
│   ├── provider-aws.yaml                  # AWS S3 provider installation
│   ├── provider-config-localstack.yaml    # ProviderConfig → LocalStack
│   ├── provider-config-aws.yaml           # ProviderConfig → real AWS
│   ├── bucket-claim.yaml                  # Simple S3 bucket
│   ├── bucket-with-versioning.yaml        # Bucket + versioning
│   ├── bucket-real-aws.yaml               # Bucket on real AWS
│   ├── xrd-objectstorage.yaml             # CompositeResourceDefinition
│   ├── composition-objectstorage.yaml     # Composition (XRD implementation)
│   └── claim-objectstorage.yaml           # Namespace-scoped claim
├── scripts/                  # Automation scripts
│   ├── 01-install-prerequisites.sh
│   ├── 02-start-cluster.sh
│   ├── 03-deploy-app.sh
│   ├── 04-demo-scenarios.sh
│   └── 05-teardown.sh
├── docs/
│   └── medium-story.md       # Article outline
└── .gitignore
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

## 📚 Resources

- [Crossplane Documentation](https://docs.crossplane.io/)
- [Upbound Marketplace — AWS Providers](https://marketplace.upbound.io/providers/upbound/provider-aws-s3/)
- [Crossplane Compositions Guide](https://docs.crossplane.io/latest/concepts/compositions/)
- [LocalStack Documentation](https://docs.localstack.cloud/)
- [Minikube Documentation](https://minikube.sigs.k8s.io/docs/)

## 📝 License

MIT — Use freely for learning, demos, and presentations.
