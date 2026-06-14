# Security Policy

## Reporting a Vulnerability

If you discover a security vulnerability in crossplane-in-action, please **do not** open a public GitHub issue. Instead, please report it responsibly by emailing [23seriy@gmail.com](mailto:23seriy@gmail.com) with:

- A description of the vulnerability
- Steps to reproduce it
- Potential impact
- Any suggested fixes (if you have them)

**Please do not disclose the vulnerability publicly until we've had time to address it.**

We will:
1. Acknowledge receipt of your report within 48 hours
2. Provide a timeline for a fix
3. Work with you on the patch if needed
4. Coordinate a disclosure date with you
5. Credit you in the security advisory (unless you prefer anonymity)

## Scope

This security policy covers the crossplane-in-action repository itself. It does **not** cover:

- **Crossplane itself** — please report Crossplane vulnerabilities to the [Crossplane project](https://github.com/crossplane/crossplane/security)
- **Kubernetes** — please report Kubernetes vulnerabilities through their [security disclosure process](https://kubernetes.io/security/)
- **AWS providers** — please report provider vulnerabilities to [Upbound](https://github.com/upbound/provider-aws/security)

## What We Fix

We consider the following as potential security issues:

- **Credential leakage** (e.g., real AWS keys in git history or manifests)
- **Code injection** in scripts (shell)
- **Insecure defaults** that could lead to unintended cloud resource exposure
- **Container security** (running as root, missing security contexts)
- **Supply chain risks** in the Go application or Docker build

We do **not** consider the following as security issues (please file them as bugs instead):

- Demo scenarios that intentionally break things (the point of this project)
- Crossplane provider misconfigurations (report to Upbound)
- Kubernetes API vulnerabilities (report to Kubernetes)

## Security Best Practices When Using This Project

### For Demo/Learning Environments

- **Use Minikube, not production clusters** — this project is a demo, not a production-hardened system
- **Run in isolated networks** — don't expose the Minikube cluster to the internet
- **Use LocalStack credentials** — the `test`/`test` credentials are for LocalStack only; never use them with real AWS
- **Clean up after demos** — run `./scripts/05-teardown.sh` to delete the test cluster

### For Extending to Production

If you're using this project as a blueprint for production infrastructure:

- **Use IRSA or Pod Identity** — not static credentials in Secrets
- **Implement ProviderConfig per environment** — separate dev, staging, prod configs
- **Enable encryption** — add SSE-S3 or SSE-KMS to bucket compositions
- **Add comprehensive tagging** — include cost center, owner, and environment tags
- **Review all Compositions** — ensure they match your organization's security and compliance requirements
- **Use private endpoints** — configure VPC endpoints for S3 instead of public endpoints
- **Keep Crossplane updated** — regularly update to the latest Crossplane and provider versions

## Known Security Considerations

### LocalStack Credentials in This Project

The LocalStack ProviderConfig uses:
- Access Key: `test` / Secret Key: `test`
- These are **LocalStack default credentials** and have no access to real AWS
- The credentials are stored in a Kubernetes Secret for the demo

For production, use:
- IRSA (IAM Roles for Service Accounts)
- Pod Identity
- AWS Secrets Manager integration

### Container Security in This Project

The `resource-api` container:
- Runs as a non-root user (UID 10001)
- Uses a minimal Alpine base image
- Has a multi-stage Docker build to reduce attack surface

### ProviderConfig Endpoint in This Project

The LocalStack ProviderConfig uses an in-cluster service URL:
- `http://localstack.crossplane-demo.svc.cluster.local:4566`
- This is accessible only from within the cluster
- No TLS (fine for local demo; production must use HTTPS)

## Security Advisories

We will publish security advisories for any reported vulnerabilities that we confirm. Check the [GitHub Security Advisories](https://github.com/23seriy/crossplane-in-action/security/advisories) page.

## Questions?

If you have questions about security practices in this project, feel free to open a **private security advisory** on GitHub instead of a public issue.

---

Thank you for helping keep crossplane-in-action secure. ☁️
