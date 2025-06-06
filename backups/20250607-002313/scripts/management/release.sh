#!/bin/bash
set -euo pipefail

VERSION=${1:-}

if [[ -z "$VERSION" ]]; then
  echo "Usage: $0 <version-tag>"
  exit 1
fi

# Validate semantic version format
if ! [[ "$VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "ERROR: Version must follow semantic versioning, e.g., v1.2.3"
  exit 1
fi

echo "Releasing version $VERSION..."

# Auto-commit changelog section if not committed
git diff --quiet CHANGELOG.md || {
  git add CHANGELOG.md
  git commit -m "Update changelog for $VERSION"
}

# Tag and push
git tag -a "$VERSION" -m "Release $VERSION"
git push origin "$VERSION"

# Run build pipeline
make clean init test package
mkdir -p dist
tarball=$(ls piswarm-*.tar.gz)
mv "$tarball" dist/

# Extract changelog section for GitHub release
awk "/## \[$VERSION\]/ {flag=1; print; next} /^## \\[/ && flag {exit} flag" CHANGELOG.md > dist/CHANGELOG-$VERSION.md

# Create GitHub release with notes and artifact
gh release create "$VERSION" \
  "dist/$tarball" \
  --title "$VERSION" \
  --notes-file "dist/CHANGELOG-$VERSION.md"

# Optional GitHub release template
if [[ ! -f ".github/RELEASE_TEMPLATE.md" ]]; then
  mkdir -p .github
  cat <<EOF > .github/RELEASE_TEMPLATE.md
## What's Changed
- Feature summary...
- Bugfix summary...

## Contributors
- @bubustein
EOF
fi

# Add README badges
README=README.md
if ! grep -q "badge.svg" "$README"; then
  sed -i "1i![release](https://img.shields.io/github/v/release/bubustein/PI-Swarm) ![ci](https://github.com/bubustein/PI-Swarm/actions/workflows/ci.yml/badge.svg)" "$README"
  git add "$README"
  git commit -m "docs: add CI and release badges"
  git push origin HEAD
fi

echo "✅ Release $VERSION complete. Files and GitHub release created in ./dist"
