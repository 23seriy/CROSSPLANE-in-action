# Crossplane in Action: Provisioning AWS Resources from Kubernetes on Your Laptop

What if you could `kubectl apply` an S3 bucket the same way you deploy a Pod?

That's exactly what Crossplane does. It turns your Kubernetes cluster into a universal control plane for cloud infrastructure — no Terraform, no AWS console, no separate tooling. Just YAML and `kubectl`.

In this guide, I'll walk you through a complete hands-on demo: provisioning S3 buckets, watching drift detection self-heal deleted resources, building platform APIs with Compositions, and — most importantly — **breaking things on purpose** so you learn to troubleshoot real-world Crossplane issues. Everything runs locally on your laptop with Minikube and LocalStack. No AWS bill.

> Full source code: [github.com/23seriy/CROSSPLANE-in-action](https://github.com/23seriy/CROSSPLANE-in-action)

---

## The Architecture

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

**Components:**

- **resource-api** — A small Go microservice that reads and writes objects to S3. It proves that the Crossplane-provisioned bucket actually works.
- **LocalStack** — A local AWS simulator. Same S3 API, zero cost. Crossplane talks to it exactly like it would talk to real AWS.
- **Crossplane** — Installed via Helm. Watches for Bucket CRDs and reconciles them against the cloud provider.
- **Provider AWS S3** — A Crossplane provider package from Upbound's marketplace that knows how to manage S3 resources.

---

## Step 1: Prerequisites

You need macOS with Docker Desktop running, Homebrew, and about 8 GB of free RAM.

```bash
git clone https://github.com/23seriy/CROSSPLANE-in-action.git
cd crossplane-in-action
chmod +x scripts/*.sh
```

Run the prerequisites installer:

```bash
./scripts/01-install-prerequisites.sh
```

This checks for (and installs if missing) `minikube`, `kubectl`, `helm`, and `docker`. It also checks if any of these tools have newer versions available via `brew outdated`.

---

## Step 2: Start the Cluster and Install Crossplane

```bash
./scripts/02-start-cluster.sh
```

This does three things:

1. Creates a Minikube cluster (`crossplane-demo` profile) with 4 CPUs and 8 GB RAM
2. Adds the Crossplane Helm repo and installs Crossplane into the `crossplane-system` namespace
3. Waits for the Crossplane operator and RBAC manager to become ready

Verify it's running:

```bash
kubectl get pods -n crossplane-system
```

You should see `crossplane` and `crossplane-rbac-manager` pods in `Running` state.

---

## Step 3: Deploy the Demo Application

```bash
./scripts/03-deploy-app.sh
```

This script:

1. Configures Docker to use Minikube's daemon (so images are built directly inside the cluster)
2. Builds the Go `resource-api` image
3. Deploys LocalStack as a local S3 simulator
4. Creates the `crossplane-demo-bucket` in LocalStack
5. Creates the `aws-credentials` Secret with LocalStack's dummy credentials (`test`/`test`)
6. Deploys the `resource-api` Deployment, Service, ConfigMap, and ServiceAccount

---

## Step 4: Verify the App Works

Open a port-forward in a separate terminal:

```bash
kubectl port-forward svc/resource-api 9090:8080 -n crossplane-demo
```

Test the API:

```bash
# Health check
curl http://localhost:9090/health
```

```json
{"status":"healthy","version":"v1","bucket":"crossplane-demo-bucket","region":"us-east-1"}
```

```bash
# Write an object
curl -X POST http://localhost:9090/api/object/put \
  -H "Content-Type: application/json" \
  -d '{"key":"hello.txt","content":"Hello from Crossplane in Action!"}'
```

```json
{"message":"object 'hello.txt' created in bucket 'crossplane-demo-bucket'"}
```

```bash
# List objects
curl http://localhost:9090/api/objects
```

```json
{"bucket":"crossplane-demo-bucket","objects":["hello.txt"],"count":1}
```

```bash
# Read it back
curl "http://localhost:9090/api/object?key=hello.txt"
```

```json
{"bucket":"crossplane-demo-bucket","key":"hello.txt","content":"Hello from Crossplane in Action!"}
```

The app is working against LocalStack. Now let's bring in Crossplane.

---

## Step 5: Install the AWS S3 Provider

Crossplane needs a **Provider** to know how to talk to AWS. Think of it like a Terraform provider, but it runs as a pod in your cluster.

```bash
kubectl apply -f crossplane/provider-aws.yaml
```

The provider manifest:

```yaml
apiVersion: pkg.crossplane.io/v1
kind: Provider
metadata:
  name: provider-aws-s3
spec:
  package: xpkg.upbound.io/upbound/provider-aws-s3:v1.7.0
  runtimeConfigRef:
    name: default
```

Wait for it to become healthy (takes 1–2 minutes as it downloads the package):

```bash
kubectl wait --for=condition=healthy provider.pkg/provider-aws-s3 --timeout=300s
kubectl get providers
```

You should see `INSTALLED=True` and `HEALTHY=True`.

---

## Step 6: Configure ProviderConfig for LocalStack

The provider knows *how* to manage S3, but it doesn't know *where* to connect or *what credentials* to use. That's what ProviderConfig is for.

```bash
kubectl apply -f crossplane/provider-config-localstack.yaml
```

This creates two things:

1. A **Secret** in `crossplane-system` with dummy AWS credentials (`test`/`test`)
2. A **ProviderConfig** named `localstack` that points to `http://localstack.crossplane-demo.svc.cluster.local:4566`

```yaml
apiVersion: aws.upbound.io/v1beta1
kind: ProviderConfig
metadata:
  name: localstack
spec:
  credentials:
    source: Secret
    secretRef:
      namespace: crossplane-system
      name: localstack-aws-creds
      key: credentials
  endpoint:
    url:
      type: Static
      static: http://localstack.crossplane-demo.svc.cluster.local:4566
    hostnameImmutable: true
```

Verify:

```bash
kubectl get providerconfig
```

---

## Step 7: Your First Managed Resource — Create an S3 Bucket with kubectl

This is the "aha moment." You're about to create an S3 bucket by applying a YAML file:

```bash
kubectl apply -f crossplane/bucket-claim.yaml
```

The manifest:

```yaml
apiVersion: s3.aws.upbound.io/v1beta2
kind: Bucket
metadata:
  name: crossplane-demo-bucket
spec:
  forProvider:
    region: us-east-1
    tags:
      Project: crossplane-in-action
      ManagedBy: crossplane
  providerConfigRef:
    name: localstack
```

Watch it get provisioned:

```bash
kubectl get bucket.s3.aws.upbound.io -w
```

You'll see it transition from `SYNCED=False` / `READY=False` to `SYNCED=True` / `READY=True`. Crossplane just created an S3 bucket by reconciling a Kubernetes CRD against the AWS API.

Compare this to Terraform:

| | Crossplane | Terraform |
|---|---|---|
| **Create** | `kubectl apply -f bucket.yaml` | `terraform apply` |
| **Check state** | `kubectl get bucket` | `terraform show` |
| **Drift detection** | Automatic, continuous | `terraform plan` (manual) |
| **Delete** | `kubectl delete bucket` | `terraform destroy` |

---

## Step 8: Bucket with Versioning

Crossplane can manage multiple related resources declaratively:

```bash
kubectl apply -f crossplane/bucket-with-versioning.yaml
```

This creates both a `Bucket` and a `BucketVersioning` resource that references it:

```yaml
apiVersion: s3.aws.upbound.io/v1beta1
kind: BucketVersioning
metadata:
  name: crossplane-versioned-bucket-versioning
spec:
  forProvider:
    region: us-east-1
    bucketRef:
      name: crossplane-versioned-bucket
    versioningConfiguration:
      - status: Enabled
  providerConfigRef:
    name: localstack
```

Check all managed resources:

```bash
kubectl get managed
```

---

## Step 9: Drift Detection — The Self-Healing Superpower

This is Crossplane's killer feature. Delete the bucket directly in LocalStack (bypassing Crossplane):

```bash
kubectl exec deployment/localstack -n crossplane-demo -- \
  awslocal s3 rb s3://crossplane-demo-bucket --force
```

Now watch Crossplane detect the drift and recreate it:

```bash
kubectl get bucket.s3.aws.upbound.io -w
```

The `SYNCED` and `READY` columns will temporarily show `False`, then recover back to `True` as Crossplane recreates the bucket. This is continuous reconciliation — just like Kubernetes recreates a Pod if you delete it.

No `terraform plan`. No manual intervention. No surprises.

---

## Step 10: When Things Go Wrong — Real-World Troubleshooting

Most Crossplane tutorials only show the happy path. But in production, things break. This section covers the 4 most common failure modes and how to diagnose and fix them.

### 🔥 Break #1: Bad Credentials

Someone deploys a ProviderConfig that references a Secret that doesn't exist:

```bash
kubectl apply -f crossplane/broken-bad-credentials.yaml
```

Wait 15 seconds, then check:

```bash
kubectl get managed
```

The `broken-creds-bucket` is stuck at `SYNCED=False` / `READY=False`.

**Diagnose:**

```bash
kubectl describe bucket.s3.aws.upbound.io broken-creds-bucket
```

Look at the `Status.Conditions` and `Events` sections. You'll see `cannot get credentials` or `secret not found`.

**Fix:**

```bash
kubectl patch bucket.s3.aws.upbound.io broken-creds-bucket \
  --type merge -p '{"spec":{"providerConfigRef":{"name":"localstack"}}}'
```

Wait 15 seconds — the bucket should transition to `SYNCED=True` / `READY=True`.

**Clean up:**

```bash
kubectl delete providerconfig bad-creds
kubectl delete bucket.s3.aws.upbound.io broken-creds-bucket
```

### 🔥 Break #2: Wrong Endpoint

Credentials are fine, but the ProviderConfig points to a dead URL (`localstack-typo:9999`):

```bash
kubectl apply -f crossplane/broken-wrong-endpoint.yaml
```

Wait 20 seconds:

```bash
kubectl describe bucket.s3.aws.upbound.io broken-endpoint-bucket
```

You'll see `no such host` or `connection refused` in the conditions.

Check the provider pod logs:

```bash
kubectl logs -n crossplane-system -l pkg.crossplane.io/revision --tail=10
```

**Fix:**

```bash
kubectl patch bucket.s3.aws.upbound.io broken-endpoint-bucket \
  --type merge -p '{"spec":{"providerConfigRef":{"name":"localstack"}}}'
```

**Clean up:**

```bash
kubectl delete bucket.s3.aws.upbound.io broken-endpoint-bucket
kubectl delete providerconfig wrong-endpoint
kubectl delete secret wrong-endpoint-creds -n crossplane-system
```

### 🔥 Break #3: Missing ProviderConfig Reference

This is the #1 most common Crossplane mistake. A bucket references ProviderConfig `production` — which was never created:

```bash
kubectl apply -f crossplane/broken-missing-providerconfig.yaml
```

```bash
kubectl describe bucket.s3.aws.upbound.io orphan-bucket
```

You'll see: `cannot get referenced ProviderConfig`.

Compare what exists vs. what's referenced:

```bash
kubectl get providerconfig
```

Only `localstack` exists. The bucket wants `production`.

**Fix:**

```bash
kubectl patch bucket.s3.aws.upbound.io orphan-bucket \
  --type merge -p '{"spec":{"providerConfigRef":{"name":"localstack"}}}'
```

**Clean up:**

```bash
kubectl delete bucket.s3.aws.upbound.io orphan-bucket
```

### 🔥 Break #4: Stuck Finalizer on Delete

When you `kubectl delete` a Crossplane resource, the provider must confirm the external resource is deleted before removing the Kubernetes object. If the provider can't reach the backend, the object gets stuck in `Terminating` forever.

```bash
# Create a bucket tied to the dead endpoint
kubectl apply -f crossplane/broken-wrong-endpoint.yaml
kubectl apply -f crossplane/broken-stuck-finalizer.yaml
sleep 10

# Try to delete it
kubectl delete bucket.s3.aws.upbound.io finalizer-test-bucket --wait=false
sleep 10

# It's stuck
kubectl get bucket.s3.aws.upbound.io finalizer-test-bucket
```

The object shows `Terminating` but never disappears.

Check the finalizers:

```bash
kubectl get bucket.s3.aws.upbound.io finalizer-test-bucket -o yaml | grep -A5 finalizers
```

**Fix (nuclear option — only if you're sure the external resource is already gone):**

```bash
kubectl patch bucket.s3.aws.upbound.io finalizer-test-bucket \
  --type json -p '[{"op":"remove","path":"/metadata/finalizers"}]'
```

The object disappears immediately.

> ⚠️ **Warning:** Removing finalizers skips the external cleanup. Only do this if the external resource no longer exists or you'll have orphaned infrastructure.

### Troubleshooting Cheat Sheet

| Symptom | Likely Cause | Debug Command |
|---|---|---|
| `SYNCED=False` / `READY=False` | Bad creds, wrong endpoint, missing config | `kubectl describe <resource>` |
| `cannot get credentials` | Secret doesn't exist or wrong key | `kubectl get secret -n crossplane-system` |
| `no such host` / `connection refused` | Wrong endpoint URL | `kubectl logs -n crossplane-system -l pkg.crossplane.io/revision` |
| `cannot get referenced ProviderConfig` | Typo in `providerConfigRef.name` | `kubectl get providerconfig` |
| Stuck in `Terminating` | Finalizer can't be released | `kubectl get <resource> -o yaml \| grep finalizers` |

---

## Step 11: Platform Engineering — XRD + Composition

This is where Crossplane goes beyond "Terraform in Kubernetes" and becomes a platform engineering tool.

**The problem:** You don't want every developer to know about S3 bucket configurations, regions, versioning settings, and ProviderConfig names. You want them to say: "I need object storage in us-east-1."

**The solution:** Define a custom API.

### Create the CompositeResourceDefinition (XRD)

This defines *what* your platform API looks like:

```bash
kubectl apply -f crossplane/xrd-objectstorage.yaml
```

```yaml
apiVersion: apiextensions.crossplane.io/v1
kind: CompositeResourceDefinition
metadata:
  name: xobjectstorages.demo.crossplane.io
spec:
  group: demo.crossplane.io
  names:
    kind: XObjectStorage
    plural: xobjectstorages
  claimNames:
    kind: ObjectStorage
    plural: objectstorages
  versions:
    - name: v1alpha1
      served: true
      referenceable: true
      schema:
        openAPIV3Schema:
          type: object
          properties:
            spec:
              type: object
              properties:
                parameters:
                  type: object
                  properties:
                    region:
                      type: string
                      default: us-east-1
                    versioning:
                      type: boolean
                      default: false
```

### Create the Composition

This defines *how* the API is implemented — mapping the simple parameters to real AWS resources:

```bash
kubectl apply -f crossplane/composition-objectstorage.yaml
```

```yaml
apiVersion: apiextensions.crossplane.io/v1
kind: Composition
metadata:
  name: objectstorage-s3
spec:
  compositeTypeRef:
    apiVersion: demo.crossplane.io/v1alpha1
    kind: XObjectStorage
  resources:
    - name: s3-bucket
      base:
        apiVersion: s3.aws.upbound.io/v1beta2
        kind: Bucket
        spec:
          forProvider:
            region: us-east-1
            tags:
              ManagedBy: crossplane-composition
          providerConfigRef:
            name: localstack
      patches:
        - fromFieldPath: spec.parameters.region
          toFieldPath: spec.forProvider.region
```

### Create a Claim

Now a developer can request storage without knowing anything about S3:

```bash
kubectl apply -f crossplane/claim-objectstorage.yaml
```

```yaml
apiVersion: demo.crossplane.io/v1alpha1
kind: ObjectStorage
metadata:
  name: team-highlights
  namespace: crossplane-demo
spec:
  parameters:
    region: us-east-1
    versioning: false
```

Verify the chain:

```bash
# The claim
kubectl get objectstorages -n crossplane-demo

# The composite resource (cluster-scoped)
kubectl get xobjectstorages

# The actual S3 bucket (managed by the composition)
kubectl get bucket.s3.aws.upbound.io
```

The developer sees `ObjectStorage`. The platform team controls the implementation. The cloud team manages the ProviderConfig. Clean separation of concerns.

---

## Going Real — Switch to AWS

Everything above uses LocalStack. To switch to real AWS:

1. Create an AWS IAM user with S3 permissions
2. Update `crossplane/provider-config-aws.yaml` with real credentials
3. Apply it: `kubectl apply -f crossplane/provider-config-aws.yaml`
4. Change `providerConfigRef.name` from `localstack` to `aws-real` in your bucket manifests

Same CRDs, same workflow, real infrastructure. Costs apply.

---

## Teardown

```bash
./scripts/05-teardown.sh
```

This deletes all Crossplane resources, uninstalls providers and Crossplane, and removes the Minikube cluster.

---

## Key Takeaways

1. **Infrastructure as Kubernetes resources** — `kubectl apply` an S3 bucket the same way you deploy a Pod.
2. **Drift detection is automatic** — Crossplane continuously reconciles desired state with actual state. No more `terraform plan` surprises.
3. **XRDs + Compositions = platform APIs** — Dev teams self-serve without cloud console access.
4. **LocalStack makes it free** — Experiment without any AWS bill. Switch to real AWS when ready.
5. **Kubernetes skills transfer** — If you know `kubectl`, you know Crossplane.
6. **Troubleshooting is a skill** — Bad credentials, wrong endpoints, missing configs, and stuck finalizers are the real production issues. Most tutorials skip them.

---

## Resources

- [Crossplane Documentation](https://docs.crossplane.io/)
- [Upbound Marketplace — AWS Providers](https://marketplace.upbound.io/providers/upbound/provider-aws-s3/)
- [Crossplane Compositions Guide](https://docs.crossplane.io/latest/concepts/compositions/)
- [LocalStack Documentation](https://docs.localstack.cloud/)
- [Full source code on GitHub](https://github.com/23seriy/CROSSPLANE-in-action)

---

*If this helped you get started with Crossplane, give the repo a ⭐ and let me know in the comments — what infrastructure would you manage with Crossplane?*

## Tags
crossplane, kubernetes, infrastructure-as-code, aws, s3, platform-engineering, devops, cloud-native, minikube, localstack, troubleshooting
