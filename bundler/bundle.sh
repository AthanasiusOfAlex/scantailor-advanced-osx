#!/usr/bin/env bash
# ==============================================================================
# ScanTailor Advanced macOS App Bundler
# Creates a standalone, self-contained ScanTailor (Advanced).app
# and optional .dmg disk image for Apple Silicon & Intel macOS.
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

NAME="ScanTailor (Advanced)"
APP_TARGET="${SCRIPT_DIR}/${NAME}.app"
TEMPLATE="${SCRIPT_DIR}/scantailor_bundle_template.app"

CREATE_DMG=1
BIN_PATH=""

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    -b|--binary)
      BIN_PATH="$2"
      shift 2
      ;;
    --no-dmg)
      CREATE_DMG=0
      shift
      ;;
    --dmg)
      CREATE_DMG=1
      shift
      ;;
    -h|--help)
      echo "Usage: $0 [options]"
      echo ""
      echo "Options:"
      echo "  -b, --binary <path>  Specify path to scantailor-advanced binary"
      echo "      --dmg            Generate compressed .dmg installer (default)"
      echo "      --no-dmg         Skip .dmg creation"
      echo "  -h, --help           Show this help message"
      exit 0
      ;;
    *)
      if [[ -z "${BIN_PATH}" && -f "$1" ]]; then
        BIN_PATH="$1"
        shift
      else
        echo "Error: Unknown argument '$1'" >&2
        exit 1
      fi
      ;;
  esac
done

# Detect binary if not specified
if [[ -z "${BIN_PATH}" ]]; then
  if command -v scantailor-advanced &>/dev/null; then
    BIN_PATH="$(command -v scantailor-advanced)"
  elif command -v scantailor &>/dev/null; then
    BIN_PATH="$(command -v scantailor)"
  elif [[ -x "/opt/homebrew/bin/scantailor-advanced" ]]; then
    BIN_PATH="/opt/homebrew/bin/scantailor-advanced"
  elif [[ -x "/usr/local/bin/scantailor-advanced" ]]; then
    BIN_PATH="/usr/local/bin/scantailor-advanced"
  else
    echo "Error: scantailor-advanced binary not found in PATH or standard Homebrew locations." >&2
    echo "Please build or install it first (e.g., brew install scantailor-advanced)" >&2
    echo "or pass the path via: $0 --binary /path/to/scantailor-advanced" >&2
    exit 1
  fi
fi

echo "==> Using ScanTailor binary: ${BIN_PATH}"

# Detect version
VERSION="1.2.1"
BUILD_DATE="$(date +%Y%m%d)"
DETECTED_VER="$(strings "${BIN_PATH}" | grep -Eo '1\.[0-9]+\.[0-9]+' | head -n 1 || true)"
if [[ -n "${DETECTED_VER}" ]]; then
  VERSION="${DETECTED_VER}"
fi
BUNDLE_VERSION="${VERSION} (build ${BUILD_DATE})"

echo "==> Target bundle: ${APP_TARGET}"
echo "==> Version: ${VERSION}, Bundle Version: ${BUNDLE_VERSION}"

# Check template
if [[ ! -d "${TEMPLATE}" ]]; then
  echo "Error: Template ${TEMPLATE} not found!" >&2
  exit 1
fi

# Clean previous build
rm -rf "${APP_TARGET}"
cp -R "${TEMPLATE}" "${APP_TARGET}"

# Update Info.plist
echo "==> Updating Info.plist..."
PLIST="${APP_TARGET}/Contents/Info.plist"
sed -i '' \
  -e "s/\${Name}/${NAME}/g" \
  -e "s/\${Version}/${VERSION}/g" \
  -e "s/\${BundleVersion}/${BUNDLE_VERSION}/g" \
  "${PLIST}"
plutil -convert binary1 "${PLIST}"

# Copy binary (Contents/MacOS should ONLY contain executable code)
BINDIR="${APP_TARGET}/Contents/MacOS"
mkdir -p "${BINDIR}"
echo "==> Copying executable to ${BINDIR}/ScanTailor..."
cp "${BIN_PATH}" "${BINDIR}/ScanTailor"
chmod 755 "${BINDIR}/ScanTailor"

# Copy translations to Resources/translations and share/scantailor-advanced/translations
echo "==> Copying translations..."
RES_TR_DIR="${APP_TARGET}/Contents/Resources/translations"
SHARE_TR_DIR="${APP_TARGET}/Contents/share/scantailor-advanced/translations"
mkdir -p "${RES_TR_DIR}" "${SHARE_TR_DIR}"

SHARE_DIR="$(cd "$(dirname "${BIN_PATH}")/.." && pwd)/share"
FOUND_QM=0

for trdir in \
  "${SHARE_DIR}/scantailor-advanced/translations" \
  "${SHARE_DIR}/scantailor/translations" \
  "/opt/homebrew/share/scantailor-advanced/translations" \
  "/usr/local/share/scantailor-advanced/translations"
do
  if [[ -d "${trdir}" && -n "$(ls "${trdir}"/*.qm 2>/dev/null || true)" ]]; then
    echo "  Found translations in ${trdir}"
    cp "${trdir}"/*.qm "${RES_TR_DIR}/"
    cp "${trdir}"/*.qm "${SHARE_TR_DIR}/"
    FOUND_QM=1
    break
  fi
done

if [[ ${FOUND_QM} -eq 0 ]]; then
  echo "  [WARN] No .qm translation files found. Translations may be missing."
fi

# Locate macdeployqt
MACDEPLOYQT=""
if command -v macdeployqt &>/dev/null; then
  MACDEPLOYQT="$(command -v macdeployqt)"
elif command -v brew &>/dev/null; then
  QT_PREFIX="$(brew --prefix qt 2>/dev/null || brew --prefix qt@6 2>/dev/null || true)"
  if [[ -n "${QT_PREFIX}" && -x "${QT_PREFIX}/bin/macdeployqt" ]]; then
    MACDEPLOYQT="${QT_PREFIX}/bin/macdeployqt"
  fi
fi

if [[ -z "${MACDEPLOYQT}" ]]; then
  echo "Error: macdeployqt not found. Please ensure Qt 6 is installed via brew (brew install qt)." >&2
  exit 1
fi

echo "==> Running macdeployqt (${MACDEPLOYQT})..."
"${MACDEPLOYQT}" "${APP_TARGET}" -verbose=1

# Resolve and bundle non-Qt dynamic libraries & sign
echo "==> Bundling third-party libraries and code signing..."
python3 "${SCRIPT_DIR}/fix_dependencies.py" "${APP_TARGET}"

echo "✔︎ Application bundle created successfully at: ${APP_TARGET}"

# Create DMG if requested
if [[ ${CREATE_DMG} -eq 1 ]]; then
  ARCH="$(uname -m)"
  DMG_NAME="ScanTailor-Advanced-${VERSION}-${ARCH}.dmg"
  DMG_PATH="${SCRIPT_DIR}/${DMG_NAME}"
  DMG_STAGING="${SCRIPT_DIR}/dmg_staging"

  echo "==> Building compressed DMG installer: ${DMG_NAME}..."
  rm -rf "${DMG_STAGING}" "${DMG_PATH}"
  mkdir -p "${DMG_STAGING}"

  cp -R "${APP_TARGET}" "${DMG_STAGING}/"
  ln -s /Applications "${DMG_STAGING}/Applications"

  hdiutil create -volname "${NAME}" \
    -srcfolder "${DMG_STAGING}" \
    -ov -format UDZO \
    "${DMG_PATH}" >/dev/null

  rm -rf "${DMG_STAGING}"
  echo "✔︎ DMG installer created successfully: ${DMG_PATH}"
fi

echo "==> Done!"
