#!/usr/bin/env bash
# ==============================================================================
# Sanity check for ScanTailor (Advanced).app bundle
# Verifies that all binaries and dynamic libraries are properly relocated
# and that no absolute Homebrew dependencies remain. Also verifies code signatures.
# ==============================================================================

set -uo pipefail

CDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP="${CDIR}/ScanTailor (Advanced).app"

if [[ ! -d "${APP}" ]]; then
  echo "Error: Bundle '${APP}' not found. Run bundle.sh first!" >&2
  exit 1
fi

RED="$(tput setaf 1 2>/dev/null || true)"
GREEN="$(tput setaf 2 2>/dev/null || true)"
YELLOW="$(tput setaf 3 2>/dev/null || true)"
BLUE="$(tput setaf 4 2>/dev/null || true)"
RESET="$(tput sgr0 2>/dev/null || true)"

echo "${BLUE}==> Inspecting bundle: ${APP}${RESET}"
echo ""

UNRESOLVED_COUNT=0
CHECKED_COUNT=0

while IFS= read -r -d '' exe; do
  if lipo -info "$exe" &>/dev/null; then
    ((CHECKED_COUNT++)) || true
    echo "${BLUE}Checking \"$(basename "$exe")\" [${exe#$APP/}]...${RESET}"

    # Get dependencies, skip header lines
    deps="$(otool -L "$exe" | tail -n +2 | awk '{print $1}')"

    while read -r dep; do
      [[ -z "$dep" ]] && continue
      # Skip self-id
      [[ "$dep" == *": "* ]] && continue

      if [[ "$dep" =~ ^/opt/homebrew || "$dep" =~ ^/usr/local ]]; then
        echo "  ${RED}✖ UNBUNDLED: ${dep}${RESET}"
        ((UNRESOLVED_COUNT++)) || true
      elif [[ "$dep" =~ ^@executable_path || "$dep" =~ ^@rpath || "$dep" =~ ^@loader_path ]]; then
        echo "  ${GREEN}✔ Relative:   ${dep}${RESET}"
      elif [[ "$dep" =~ ^/System || "$dep" =~ ^/usr/lib ]]; then
        echo "  ${YELLOW}✔ System:     ${dep}${RESET}"
      else
        echo "  ${YELLOW}? Other:      ${dep}${RESET}"
      fi
    done <<< "$deps"
  fi
done < <(find "$APP" -type f -print0)

echo ""
echo "==> Checked ${CHECKED_COUNT} binary files."

if [[ ${UNRESOLVED_COUNT} -gt 0 ]]; then
  echo "${RED}✖ FAILED: Found ${UNRESOLVED_COUNT} unbundled external dependencies!${RESET}"
else
  echo "${GREEN}✔ PASSED: All external dynamic libraries are bundled relatively!${RESET}"
fi

echo ""
echo "==> Verifying Apple Silicon code signature..."
if codesign --verify --deep --strict "${APP}" 2>&1; then
  echo "${GREEN}✔ PASSED: Code signature is valid and ready for Apple Silicon!${RESET}"
else
  echo "${RED}✖ WARNING: Code signature verification had warnings or failed.${RESET}"
fi
