# Contributing to Pi-Swarm

Thank you for your interest in contributing!

## How to Contribute

- **Fork the repository** and create your branch from `main`.
- **Test your changes** using `bash scripts/testing/comprehensive-test.sh`.
- **Run shellcheck** on all scripts: `shellcheck lib/**/*.sh core/*.sh scripts/**/*.sh`
- **Document your changes** in `docs/CHANGELOG.md`.
- **Open a pull request** with a clear description of your changes.

## Code Style
- Use `set -euo pipefail` in all bash scripts.
- Use functions and scope-based organization (see `lib/`).
- Keep documentation up to date.

## Reporting Issues
- Use GitHub Issues for bugs or feature requests.

## Community
- Be respectful and constructive in all communications.
