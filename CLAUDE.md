# CLAUDE.md — Crossplane in Action

## Project Overview

Hands-on demo of **Crossplane** — Kubernetes-native cloud infrastructure provisioning. Uses a Go microservice that reads/writes objects to an S3 bucket provisioned entirely by Crossplane. **LocalStack** simulates AWS locally for zero-cost experimentation.

## Tech Stack

- **App**: Go 1.24 (resource-api)
- **Platform**: Minikube (profile: `crossplane-demo`, Kubernetes v1.32.0)
- **Tool**: Crossplane v2.3 + Upbound AWS S3 Provider v1.7.0
- **Cloud Sim**: LocalStack (local AWS emulation)
- **Container**: Docker (multi-stage Go build inside Minikube, non-root user)
- **CI/CD**: GitHub Actions (shellcheck, yamllint, go vet, hadolint, markdown lint)

## Project Structure

```
.github/               # GitHub community and CI/CD
  workflows/validate.yml         # CI pipeline
  ISSUE_TEMPLATE/                # Bug report and feature request templates
  PULL_REQUEST_TEMPLATE.md       # PR checklist
  GOVERNANCE.md                  # Project governance
  dependabot.yml                 # Automated dependency updates
apps/                  # Application source code
  resource-api/        # Go microservice (reads/writes S3 objects)
    main.go            # Uses AWS SDK v2
    Dockerfile         # Multi-stage build, non-root user (UID 10001)
crossplane/            # Crossplane resources
  provider-aws.yaml              # AWS provider installation
  provider-config-localstack.yaml # Points to LocalStack
  provider-config-aws.yaml       # Points to real AWS (swap when ready)
  bucket-claim.yaml              # Basic S3 bucket claim
  bucket-with-versioning.yaml    # Versioned bucket
  bucket-real-aws.yaml           # Real AWS bucket
  xrd-objectstorage.yaml         # CompositeResourceDefinition
  composition-objectstorage.yaml # Composition (pipeline mode)
  claim-objectstorage.yaml       # Claim using XRD
  function-patch-and-transform.yaml # Composition function
  broken-*.yaml                  # Intentionally broken resources for debugging demos
k8s/                   # Base Kubernetes manifests (with security contexts)
scripts/               # Numbered automation scripts (01–05)
```

## Documentation

- `README.md` — Full project overview, quick start, and scenarios
- `CONTRIBUTING.md` — How to contribute, code standards, PR process
- `TESTING.md` — Manual and automated testing procedures
- `TROUBLESHOOTING.md` — Debug guide for common Crossplane issues
- `SECURITY.md` — Security policy and responsible disclosure
- `CODE_OF_CONDUCT.md` — Community standards
- `CHANGELOG.md` — Release history (Keep a Changelog format)

## Scripts Convention

All scripts are in `scripts/` and numbered sequentially:
- `01-install-prerequisites.sh` — Installs minikube, kubectl, helm via Homebrew
- `02-start-cluster.sh` — Creates Minikube cluster and installs Crossplane
- `03-deploy-app.sh` — Deploys LocalStack, configures provider, deploys resource-api
- `04-demo-scenarios.sh` — Interactive walkthrough (7 happy-path + 4 troubleshooting)
- `05-teardown.sh` — Destroys cluster (has confirmation prompt)

Scripts use `#!/usr/bin/env bash` and `set -euo pipefail`.

## Key Concepts

- **Compositions/XRDs** define platform abstractions over raw AWS resources
- **LocalStack** runs as a pod in-cluster, simulating S3
- **ProviderConfig** determines target: swap `provider-config-localstack.yaml` for `provider-config-aws.yaml` to hit real AWS
- `broken-*.yaml` files demonstrate common Crossplane failure modes (bad credentials, missing config, stuck finalizers, wrong endpoint)
- The Go app uses AWS SDK v2 with a custom endpoint resolver for LocalStack

## Security Practices

- Container runs as non-root user (UID 10001)
- Read-only root filesystem
- All capabilities dropped
- Resource requests and limits defined
- Pod security context enforces `runAsNonRoot`
- No real AWS credentials in the repository

## Conventions

- All Kubernetes resources use the `crossplane-demo` namespace
- Crossplane system components run in `crossplane-system` namespace
- Color-coded script output: GREEN=info, YELLOW=warn, RED=break, MAGENTA=fix, CYAN=header
- Docker images are built locally in Minikube's Docker daemon (no registry push)
- Commit messages follow `[type] description` convention
- All shell scripts must pass `shellcheck`
