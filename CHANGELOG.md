# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/), and this project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- (Unreleased items go here)

### Changed
- (Changes go here)

### Deprecated
- (If any features are deprecated, list them here)

### Removed
- (If any features are removed, list them here)

### Fixed
- (Bug fixes go here)

### Security
- (Security fixes go here)

---

## [1.0.0] — 2026-06-14

### Added

#### Documentation
- **CONTRIBUTING.md** — Contribution guidelines and development workflow
- **TESTING.md** — Manual and automated testing procedures
- **TROUBLESHOOTING.md** — Comprehensive troubleshooting guide for common issues
- **SECURITY.md** — Security policies and responsible disclosure process
- **CODE_OF_CONDUCT.md** — Community standards and code of conduct
- **CHANGELOG.md** — This file

#### CI/CD
- **GitHub Actions workflow** (`.github/workflows/validate.yml`) with:
  - Shell script linting (shellcheck)
  - YAML validation (yamllint)
  - Crossplane resource syntax validation
  - Go build and vet
  - Dockerfile linting (hadolint)
  - Markdown linting
- **GitHub issue templates** for bug reports and feature requests
- **GitHub pull request template** with testing checklist
- **Dependabot configuration** for automated dependency updates (Go modules, GitHub Actions, Docker)
- **Project governance document** (`.github/GOVERNANCE.md`)

#### Development Tools
- **Shell configuration** (`.shellcheckrc`) for script validation
- **Markdown linting configuration** (`.markdownlint.json`)
- **Enhanced `.gitignore`** with Go, Kubernetes, and IDE patterns

#### Security Improvements
- **Non-root container** — Dockerfile runs as UID 10001
- **Resource limits** — Deployment includes CPU/memory requests and limits
- **Security context** — Pods run with `runAsNonRoot`, `readOnlyRootFilesystem`, and dropped capabilities

### Core Features (Initial Release)

#### Scripts
- `01-install-prerequisites.sh` — Install Homebrew tools (minikube, kubectl, helm)
- `02-start-cluster.sh` — Create Minikube cluster and install Crossplane
- `03-deploy-app.sh` — Deploy LocalStack, build resource-api, deploy application
- `04-demo-scenarios.sh` — 11 interactive scenarios (7 happy-path + 4 troubleshooting)
- `05-teardown.sh` — Clean up cluster (with confirmation prompt)

#### Demo Scenarios
1. **Verify App + LocalStack** — Test resource-api against LocalStack S3
2. **Install Provider** — Install `provider-aws-s3` from Upbound marketplace
3. **Configure ProviderConfig** — Point Crossplane at LocalStack
4. **Provision Bucket** — Create S3 bucket via Crossplane CRD
5. **🔥 Bad Credentials** — Missing Secret → stuck bucket diagnosis
6. **🔥 Wrong Endpoint** — Dead endpoint → connection refused diagnosis
7. **🔥 Missing ProviderConfig** — Typo in providerConfigRef diagnosis
8. **Bucket with Versioning** — Multiple related managed resources
9. **XRD + Composition** — Platform abstraction with custom APIs
10. **Drift Detection** — Self-healing infrastructure demo
11. **🔥 Stuck Finalizer** — Force-remove finalizer to unstick deletion

#### Application
- **resource-api** — Go microservice using AWS SDK v2 with:
  - S3 object CRUD operations (PUT, GET, LIST)
  - Health endpoint
  - Custom endpoint resolver for LocalStack
  - Multi-stage Docker build

#### Crossplane Resources
- `provider-aws.yaml` — AWS S3 provider installation
- `provider-config-localstack.yaml` — ProviderConfig for LocalStack
- `provider-config-aws.yaml` — ProviderConfig for real AWS
- `bucket-claim.yaml` — Simple S3 bucket
- `bucket-with-versioning.yaml` — Bucket + BucketVersioning
- `bucket-real-aws.yaml` — Bucket on real AWS
- `xrd-objectstorage.yaml` — CompositeResourceDefinition
- `composition-objectstorage.yaml` — Pipeline-mode Composition
- `claim-objectstorage.yaml` — XObjectStorage claim
- `function-patch-and-transform.yaml` — Crossplane function
- `broken-bad-credentials.yaml` — 🔥 Missing Secret
- `broken-wrong-endpoint.yaml` — 🔥 Dead endpoint
- `broken-missing-providerconfig.yaml` — 🔥 Missing ProviderConfig
- `broken-stuck-finalizer.yaml` — 🔥 Stuck finalizer

### Features

- ✅ **Educational focus** — Hands-on Crossplane learning
- ✅ **Fully automated** — Single-command setup and demo
- ✅ **Production patterns** — Real-world provisioning and troubleshooting
- ✅ **Platform APIs** — XRD + Composition for self-service infrastructure
- ✅ **Drift detection** — Continuous reconciliation demo
- ✅ **11-scenario coverage** — Happy-path and troubleshooting combined
- ✅ **Zero cloud cost** — LocalStack for local development
- ✅ **Well-documented** — Comprehensive README and docs
- ✅ **Community-ready** — Contributing guidelines, code of conduct, security policy

### Tested With

- **Kubernetes** — v1.32.0
- **Crossplane** — v2.3.2
- **Provider AWS S3** — v1.7.0
- **Minikube** — latest
- **macOS** — 13.0+
- **Docker Desktop** — latest
- **Go** — 1.24

---

## How to Use This Changelog

When contributing:
1. Add your changes to the **[Unreleased]** section
2. Use categories: Added, Changed, Deprecated, Removed, Fixed, Security
3. Keep entries brief and user-focused
4. Link to related issues/PRs: `([#123](https://github.com/23seriy/crossplane-in-action/issues/123))`

When releasing:
1. Rename **[Unreleased]** to **[VERSION] — YYYY-MM-DD**
2. Add new **[Unreleased]** section
3. Update links at bottom: `[Unreleased]: https://github.com/23seriy/crossplane-in-action/compare/v1.0.0...HEAD`

---

## Semantic Versioning

- **MAJOR** (1.x.0) — Breaking changes (incompatible script changes, major Crossplane version)
- **MINOR** (x.1.0) — New features (new scenarios, providers, resource types)
- **PATCH** (x.x.1) — Bug fixes (script fixes, documentation, typos)

---

[Unreleased]: https://github.com/23seriy/crossplane-in-action/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/23seriy/crossplane-in-action/releases/tag/v1.0.0
