#!/usr/bin/env bash
# ==============================================================================
# ScanTailor Advanced Automated Installer for macOS
# Configures Homebrew (if needed), taps the repository, and installs
# ScanTailor Advanced natively for Apple Silicon (ARM64) or Intel (x86_64).
# ==============================================================================

set -euo pipefail

CYAN="$(tput setaf 6 2>/dev/null || true)"
GREEN="$(tput setaf 2 2>/dev/null || true)"
RESET="$(tput sgr0 2>/dev/null || true)"
PREF="${CYAN}[SCANTAILOR INSTALLER]${RESET}"

echo "${PREF} Checking prerequisites..."

# Check Homebrew
if ! command -v brew &>/dev/null; then
  echo "${PREF} Homebrew package manager was not found."
  read -r -p "${PREF} Do you want to install Homebrew now? [y/N] " yn
  case "$yn" in
    [Yy]*)
      /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
      if [[ "$(uname -m)" == "arm64" ]]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
        PROFILE="$HOME/.zprofile"
        [[ "${SHELL:-}" == *"bash"* ]] && PROFILE="$HOME/.bash_profile"
        echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> "${PROFILE}"
      fi
      ;;
    *)
      echo "${PREF} Installation aborted. Homebrew is required."
      exit 1
      ;;
  esac
fi

# Ensure brew environment is active
if [[ "$(uname -m)" == "arm64" && -x "/opt/homebrew/bin/brew" ]]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
fi

echo "${PREF} Adding ScanTailor Advanced tap..."
brew tap AthanasiusOfAlex/scantailor-advanced-osx

echo "${PREF} Installing ScanTailor Advanced..."
brew install athanasiusofalex/scantailor-advanced-osx/scantailor-advanced "$@"

echo ""
echo "${GREEN}✔ ScanTailor Advanced has been successfully installed!${RESET}"
echo ""
echo "To run it from the command line:"
echo "  scantailor-advanced &"
echo "or"
echo "  scantailor &"
echo ""
echo "To create a standalone macOS .app bundle and .dmg installer:"
echo "  cd /path/to/scantailor-advanced-osx/bundler && ./bundle.sh"
