#!/bin/bash

set -e

SCRIPTDIR=$(dirname "$0")
PROJECTDIR=$(realpath "${SCRIPTDIR}/../")

# Build Docker image
echo "Building Vita SDK Docker image..."
docker build -f "${SCRIPTDIR}/Dockerfile.vita.jammy" -t vitaki-vita-builder "${SCRIPTDIR}"

# Run build in container
echo "Building Vitaki for PS Vita..."
docker run --rm \
    -v "${PROJECTDIR}:/build" \
    -w /build \
    vitaki-vita-builder \
    bash -c "cd /build && ./scripts/vita/build.sh"

echo "Build completed! VPK file should be in build/vita/"
