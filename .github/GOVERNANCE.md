# Project Governance

## Overview

crossplane-in-action is a community-driven educational project demonstrating Crossplane's capabilities for Kubernetes-native cloud infrastructure provisioning. This document outlines how we make decisions, manage contributions, and maintain the project.

## Project Goals

1. **Educate** — Provide clear, hands-on examples of Crossplane's features
2. **Demonstrate** — Show real provisioning workflows and troubleshooting that users can adapt
3. **Empower** — Enable users to build their own platform APIs with XRDs and Compositions
4. **Maintain Quality** — Keep code, docs, and scripts clean and consistent

## Maintainers

The project is maintained by:
- **Sergei Olshanetski** (@23seriy) — Creator and primary maintainer

Maintainers handle:
- Reviewing pull requests
- Merging approved changes
- Managing releases
- Setting project direction
- Enforcing code standards

## Contributing

We welcome contributions! See [CONTRIBUTING.md](../CONTRIBUTING.md) for:
- How to get started
- Development workflow
- Testing requirements
- PR conventions

## Decision Making

### Minor Changes (Docs, Bug Fixes, Tests)
- Open a PR with a clear description
- At least one maintainer approval needed
- CI checks must pass
- No formal review period required

### Major Changes (New Features, Architecture)
- Open an issue or discussion first
- Describe the change and motivation
- Get feedback from maintainers
- Then open a PR
- Allow 3-5 days for community feedback
- At least one maintainer approval needed

### Breaking Changes
- Only in major version bumps
- Clearly documented in CHANGELOG
- At least one maintainer approval
- Community discussion encouraged

## Release Process

### Versioning

We follow [Semantic Versioning](https://semver.org/):
- **MAJOR** — Breaking changes (major Crossplane version bump, script incompatibility)
- **MINOR** — New features (new scenarios, providers, resource types)
- **PATCH** — Bug fixes (script fixes, doc corrections)

### Release Steps

1. Update [CHANGELOG.md](../CHANGELOG.md) with all changes
2. Bump version in README.md and scripts
3. Create a git tag: `git tag v1.2.3`
4. Push tag: `git push origin v1.2.3`
5. GitHub Actions creates a release automatically
6. Announce on relevant channels

## Conflict Resolution

If there's disagreement on a change:

1. **Discussion** — Comment on the PR with your perspective
2. **Compromise** — Find middle ground where possible
3. **Escalation** — Maintainer makes final call if needed
4. **Respect** — Follow the decision, even if you disagree

All disputes are handled with respect and transparency.

## Code Standards

All contributions must:
- Pass `shellcheck` (shell scripts)
- Pass `yamllint` (YAML files)
- Build successfully with `go vet` and `go build` (Go code)
- Include comments for complex logic
- Update documentation if behavior changes
- Include clear commit messages: `[type] description`

See [.github/workflows/validate.yml](workflows/validate.yml) for all automated checks.

## Community Channels

- **Issues** — Bug reports, feature requests, questions
- **Discussions** — General conversations, ideas, feedback
- **Pull Requests** — Code review and collaboration
- **Commits** — Git history is the source of truth

## Recognition

Contributors are recognized:
- In PR merge commits (git history is authoritative)
- In CHANGELOG.md for major contributions
- Optionally in README.md (ask when submitting PR)

## Sustainability

This is an educational project. It's maintained as-is with periodic updates for:
- Crossplane version compatibility
- Kubernetes version compatibility
- AWS provider version compatibility
- Bug fixes and improvements from community

We don't commit to support timelines or SLAs, but we do our best to:
- Review PRs within a week
- Fix critical bugs promptly
- Respond to issues courteously

## Code of Conduct

All participants must follow the [CODE_OF_CONDUCT.md](../CODE_OF_CONDUCT.md). We're committed to providing a respectful, inclusive environment.

## Licensing

All contributions are licensed under [MIT](../LICENSE). By submitting a PR, you agree to this license.

---

Questions about governance? Open an issue or discussion! ☁️
