# ScanTailor Advanced for macOS

macOS packaging, Homebrew tap, and native App bundler for [ScanTailor Advanced](https://github.com/ScanTailor-Advanced/scantailor-advanced) (v1.2.1).

Built natively for **Apple Silicon (ARM64)** and **Intel (x86_64)** with the **Qt 6** framework.

---

## What is ScanTailor Advanced?

ScanTailor Advanced merges the best features of ScanTailor Featured and ScanTailor Enhanced versions, bringing performance improvements, high-DPI / Retina display support, modern Qt 6 integration, enhanced dewarping, and numerous bug fixes.

---

## Quick Installation

### Option 1: Homebrew (Recommended)

1. Make sure you have [Homebrew](https://brew.sh) installed.
2. Tap this repository and install `scantailor-advanced`:

```bash
brew tap AthanasiusOfAlex/scantailor-advanced-osx
brew install scantailor-advanced
```

3. Launch ScanTailor:

```bash
scantailor-advanced &

# Or using the 'scantailor' alias:
scantailor &
```

---

### Option 2: Automated Install Script

Run this single command in your Terminal:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/AthanasiusOfAlex/scantailor-advanced-osx/HEAD/install.sh)"
```

The script verifies prerequisites, sets up Homebrew environment paths if needed, taps the repository, and installs the latest version.

---

### Option 3: Pre-built App Bundle (.dmg)

Download the `.dmg` installer from the [Releases](https://github.com/AthanasiusOfAlex/scantailor-advanced-osx/releases) page and drag **ScanTailor (Advanced)** to your `/Applications` folder.

> [!NOTE]
> **macOS Gatekeeper Note for Downloaded Apps:**
> If macOS warns that the app "cannot be opened because Apple cannot check it for malicious software" or "is damaged", remove the quarantine attribute in Terminal:
> ```bash
> xattr -cr "/Applications/ScanTailor (Advanced).app"
> ```
> (or right-click the app in Finder and choose **Open**).

---

## Building a Standalone App Bundle & DMG

This repository includes a standalone bundler that creates a self-contained `.app` bundle and a compressed `.dmg` disk image.

The bundler:
- Automatically locates the installed `scantailor-advanced` binary.
- Deploys Qt 6 frameworks and plugins via `macdeployqt`.
- Automatically copies and relocates all third-party dynamic libraries (`boost`, `libtiff`, `libpng`, `jpeg-turbo`, etc.) into `Contents/Frameworks`.
- Applies mandatory ad-hoc code signing (`codesign`) required for Apple Silicon AMFI security.
- Packages a compressed `.dmg` installer with an `/Applications` shortcut.

### Steps to Bundle:

1. Install prerequisites:
   ```bash
   brew tap AthanasiusOfAlex/scantailor-advanced-osx
   brew install scantailor-advanced
   ```

2. Run the bundler:
   ```bash
   cd bundler
   ./bundle.sh
   ```
   *(Or double-click `scantailor_bundler.command` in Finder.)*

3. Verify the bundle integrity:
   ```bash
   ./sanity_check.command
   ```

The output bundle `ScanTailor (Advanced).app` and disk image `ScanTailor-Advanced-1.2.1-arm64.dmg` will be ready in the `bundler/` directory.

---

## Manual Build from Source

If you prefer building directly with CMake without Homebrew's formula runner:

```bash
# 1. Install dependencies
brew install cmake boost qt libpng libtiff jpeg-turbo

# 2. Clone upstream ScanTailor Advanced
git clone https://github.com/ScanTailor-Advanced/scantailor-advanced.git
cd scantailor-advanced

# 3. Configure and build
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTS=OFF
cmake --build build -j$(sysctl -n hw.ncpu)

# 4. Install
sudo cmake --install build
```

---

## Credits & Upstream

- Upstream Project: [ScanTailor-Advanced/scantailor-advanced](https://github.com/ScanTailor-Advanced/scantailor-advanced)
- Original ScanTailor by Joseph Artsimovich.
- macOS Packaging and App Bundler by [AthanasiusOfAlex](https://github.com/AthanasiusOfAlex/scantailor-advanced-osx) (originally maintained by [yb85](https://github.com/yb85/scantailor-advanced-osx)).
