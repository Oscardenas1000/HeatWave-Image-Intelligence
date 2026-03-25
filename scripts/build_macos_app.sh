#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
BUILD_ARCH="${HEATWAVE_MACOS_BUILD_ARCH:-$(uname -m)}"
DEFAULT_TMPDIR="${TMPDIR:-/tmp}"
DEFAULT_TMPDIR="${DEFAULT_TMPDIR%/}"
DERIVED_DATA_PATH="${HEATWAVE_XCODE_DERIVED_DATA_PATH:-${DEFAULT_TMPDIR}/HeatWaveImageIntelligenceMacApp-Release-${BUILD_ARCH}}"
PRODUCTS_PATH="${DERIVED_DATA_PATH}/Build/Products/Release"
SOURCE_APP_PATH="${PRODUCTS_PATH}/HeatWaveImageIntelligenceMacApp.app"
OUTPUT_DIR="${REPO_ROOT}/dist"
OUTPUT_APP_PATH="${OUTPUT_DIR}/HeatWave Image Intelligence.app"

OPEN_APP=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --open)
      OPEN_APP=1
      ;;
    --help|-h)
      cat <<'EOF'
Usage: scripts/build_macos_app.sh [--open]

Builds the Release macOS app bundle with Xcode and copies it to:
  dist/HeatWave Image Intelligence.app

The build targets the current host architecture by default. Override with:
  HEATWAVE_MACOS_BUILD_ARCH=arm64
  HEATWAVE_MACOS_BUILD_ARCH=x86_64

Optional:
  HEATWAVE_XCODE_DERIVED_DATA_PATH=/custom/path

Options:
  --open    Open the built app after the copy succeeds.
EOF
      exit 0
      ;;
    *)
      echo "Unknown argument: $1"
      exit 1
      ;;
  esac
  shift
done

cd "${REPO_ROOT}"

mkdir -p "${OUTPUT_DIR}"
rm -rf "${OUTPUT_APP_PATH}"

xcodebuild \
  -project HeatWaveImageIntelligenceMacApp.xcodeproj \
  -scheme HeatWaveImageIntelligenceMacApp \
  -configuration Release \
  -destination "platform=macOS,arch=${BUILD_ARCH}" \
  -derivedDataPath "${DERIVED_DATA_PATH}" \
  ONLY_ACTIVE_ARCH=YES \
  build

if [[ ! -d "${SOURCE_APP_PATH}" ]]; then
  echo "Expected build product not found: ${SOURCE_APP_PATH}"
  exit 1
fi

cp -R "${SOURCE_APP_PATH}" "${OUTPUT_APP_PATH}"

echo "Built app bundle:"
echo "  ${OUTPUT_APP_PATH}"
echo "Built architecture:"
echo "  ${BUILD_ARCH}"
echo
echo "Launcher workflow:"
echo "  ./run_heatwave_image_intelligence.command --built-app"
echo "  ./run_heatwave_image_intelligence.command --mock-backend --built-app"

if [[ "${OPEN_APP}" == "1" ]]; then
  open "${OUTPUT_APP_PATH}"
fi
