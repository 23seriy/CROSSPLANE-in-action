# CLAUDE.md — Crossplane in Action

## Project Overview

Hands-on demo of **Crossplane** — Kubernetes-native cloud infrastructure provisioning. Uses a Go microservice that reads/writes objects to an S3 bucket provisioned entirely by Crossplane. **LocalStack** simulates AWS locally for zero-cost experimentation.

## Tech Stack

- **App**: Go (resource-api)
- **Platform**: Minikube (profile: `crossplane-demo`)
- **Tool**: Crossplane + AWS S3 Provider
- **Cloud Sim**: LocalStack (local AWS emulation)
- **Container**: Docker (multi-stage Go build inside Minikube)

## Project Structure

```
apps/                  # Application source code
  resource-api/        # Go microservice (reads/writes S3 objects)
    main.go            # Uses AWS SDK v2
    Dockerfile         # Multi-stage build
crossplane/            # Crossplane resources
  provider-aws.yaml              # AWS provider installation
  provider-config-localstack.yaml # Points to LocalStack
  provider-config-aws.yaml       # Points to real AWS (swap when ready)
  bucket-claim.yaml              # Basic S3 bucket claim
  bucket-with-versioning.yaml    # Versioned bucket
  bucket-real-aws.yaml           # Real AWS bucket
  xrd-objectstorage.yaml         # CompositeResourceDefinition
  composition-objectstorage.yaml # Composition
  claim-objectstorage.yaml       # Claim using XRD
  function-patch-and-transform.yaml # Composition function
  broken-*.yaml                  # Intentionally broken resources for debugging demos
k8s/                   # Base Kubernetes manifests
scripts/               # Numbered automation scripts (01–05)
```

## Scripts Convention

All scripts are in `scripts/` and numbered sequentially:
- `01-install-prerequisites.sh` — Installs minikube, kubectl, crossplane CLI via Homebrew
- `02-start-cluster.sh` — Creates Minikube cluster and installs Crossplane
- `03-deploy-app.sh` — Deploys LocalStack, configures provider, deploys resource-api
- `04-demo-scenarios.sh` — Interactive walkthrough of Crossplane features
- `05-teardown.sh` — Destroys cluster (has confirmation prompt)

Scripts use `#!/usr/bin/env bash` and `set -euo pipefail`.

## Key Concepts

- **Compositions/XRDs** define platform abstractions over raw AWS resources
- **LocalStack** runs as a pod in-cluster, simulating S3
- **ProviderConfig** determines target: swap `provider-config-localstack.yaml` for `provider-config-aws.yaml` to hit real AWS
- `broken-*.yaml` files demonstrate common Crossplane failure modes (bad credentials, missing config, stuck finalizers, wrong endpoint)
- The Go app uses AWS SDK v2 with a custom endpoint resolver for LocalStack

## Conventions

- All Kubernetes resources use the `crossplane-demo` namespace
- Crossplane system components run in `crossplane-system` namespace
- Emoji prefixes in script output for readability (☁️, ✅, 🗑️)
- Docker images are built locally in Minikube's Docker daemon (no registry push)
