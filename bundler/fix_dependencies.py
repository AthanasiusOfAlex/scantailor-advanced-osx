#!/usr/bin/env python3
"""
Dependency Resolver & Bundler for ScanTailor Advanced on macOS.
Copies non-system third-party dynamic libraries and frameworks into
Contents/Frameworks, rewrites LC_ID_DYLIB and LC_LOAD_DYLIB to @rpath,
adds fallback LC_RPATHs, creates Contents/lib compatibility symlink,
and ad-hoc signs all binaries to ensure Apple Silicon AMFI compatibility.
"""

import os
import sys
import subprocess
import shutil
from pathlib import Path

SYSTEM_PREFIXES = (
    "/usr/lib/",
    "/System/Library/",
    "@executable_path",
    "@loader_path",
    "@rpath",
)

def run_cmd(args, check=True):
    res = subprocess.run(args, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    if check and res.returncode != 0:
        print(f"Command failed ({res.returncode}): {' '.join(args)}", file=sys.stderr)
        print(res.stderr, file=sys.stderr)
        raise RuntimeError(f"Command failed: {' '.join(args)}")
    return res.stdout.strip()

def is_macho(path: Path) -> bool:
    if not path.is_file() or path.is_symlink():
        return False
    try:
        with open(path, "rb") as f:
            magic = f.read(4)
            return magic in (
                b"\xfe\xed\xfa\xce",
                b"\xce\xfa\xed\xfe",
                b"\xfe\xed\xfa\xcf",
                b"\xcf\xfa\xed\xfe",
                b"\xca\xfe\xba\xbe",
                b"\xbe\xba\xfe\xca",
            )
    except (OSError, PermissionError):
        return False

def get_dependencies(path: Path):
    out = run_cmd(["otool", "-L", str(path)], check=False)
    deps = []
    lines = out.splitlines()[1:]  # skip first line (binary path)
    for line in lines:
        line = line.strip()
        if not line:
            continue
        dep = line.split(" (compatibility version")[0].strip()
        deps.append(dep)
    return deps

def get_dylib_id(path: Path):
    out = run_cmd(["otool", "-D", str(path)], check=False)
    lines = out.splitlines()
    if len(lines) >= 2:
        return lines[1].strip()
    return ""

def bundle_dependencies(app_path: Path):
    contents_dir = app_path / "Contents"
    frameworks_dir = contents_dir / "Frameworks"
    frameworks_dir.mkdir(parents=True, exist_ok=True)

    # Symlink Contents/lib -> Frameworks for dylibs that look for @loader_path/../lib
    lib_symlink = contents_dir / "lib"
    if not lib_symlink.exists():
        try:
            lib_symlink.symlink_to("Frameworks")
        except OSError:
            pass

    print(f"==> Resolving dynamic dependencies for {app_path.name}...")

    # Ensure main executable has @rpaths set
    main_bin = contents_dir / "MacOS" / "ScanTailor"
    if main_bin.exists():
        rpaths_out = run_cmd(["otool", "-l", str(main_bin)], check=False)
        for rp in ("@executable_path/../Frameworks", "@loader_path/../Frameworks"):
            if rp not in rpaths_out:
                run_cmd(["install_name_tool", "-add_rpath", rp, str(main_bin)], check=False)

    changed = True
    iterations = 0
    max_iterations = 25

    while changed and iterations < max_iterations:
        changed = False
        iterations += 1

        all_machos = [p for p in app_path.rglob("*") if is_macho(p)]

        for macho in all_machos:
            deps = get_dependencies(macho)
            for dep in deps:
                if dep.startswith(SYSTEM_PREFIXES):
                    continue
                if not (dep.startswith("/opt/homebrew") or dep.startswith("/usr/local")):
                    continue

                dep_path = Path(dep)
                if not dep_path.exists():
                    print(f"  [WARN] Dependency not found: {dep}")
                    continue

                # Check if this dependency is inside a .framework
                framework_match = None
                for part in dep_path.parts:
                    if part.endswith(".framework"):
                        framework_match = part
                        break

                if framework_match:
                    fw_idx = dep_path.parts.index(framework_match)
                    fw_src_dir = Path(*dep_path.parts[:fw_idx + 1])
                    fw_dest_dir = frameworks_dir / framework_match
                    rel_in_fw = Path(*dep_path.parts[fw_idx:])

                    if not fw_dest_dir.exists():
                        print(f"  [COPY FRAMEWORK] {framework_match} -> Frameworks/")
                        shutil.copytree(fw_src_dir, fw_dest_dir, symlinks=True)
                        changed = True

                    new_dep = f"@rpath/{rel_in_fw}"
                else:
                    dest_file = frameworks_dir / dep_path.name
                    if not dest_file.exists():
                        print(f"  [COPY DYLIB] {dep_path.name} -> Frameworks/")
                        real_dep = dep_path.resolve()
                        shutil.copy2(real_dep, dest_file)
                        os.chmod(dest_file, 0o755)

                        if dep_path.name != real_dep.name:
                            soname_link = frameworks_dir / real_dep.name
                            if not soname_link.exists():
                                shutil.copy2(real_dep, soname_link)
                                os.chmod(soname_link, 0o755)
                        changed = True

                    new_dep = f"@executable_path/../Frameworks/{dep_path.name}"

                run_cmd(["install_name_tool", "-change", dep, new_dep, str(macho)], check=False)

    # Post-processing: normalize all LC_ID_DYLIB and add fallback LC_RPATHs in Frameworks/
    print("==> Normalizing dylib IDs and LC_RPATHs in Frameworks/...")
    for macho in frameworks_dir.rglob("*"):
        if not is_macho(macho):
            continue

        framework_match = None
        for part in macho.parts:
            if part.endswith(".framework"):
                framework_match = part
                break

        if framework_match:
            fw_idx = macho.parts.index(framework_match)
            rel_in_fw = Path(*macho.parts[fw_idx:])
            proper_id = f"@rpath/{rel_in_fw}"
        else:
            proper_id = f"@rpath/{macho.name}"

        curr_id = get_dylib_id(macho)
        if curr_id and (curr_id.startswith("/opt/homebrew") or curr_id.startswith("/usr/local")):
            run_cmd(["install_name_tool", "-id", proper_id, str(macho)], check=False)

        # Add rpaths to dylib so it can resolve sibling dylibs
        rpaths_out = run_cmd(["otool", "-l", str(macho)], check=False)
        for rp in ("@loader_path", "@executable_path/../Frameworks"):
            if rp not in rpaths_out:
                run_cmd(["install_name_tool", "-add_rpath", rp, str(macho)], check=False)

        # Rewrite any remaining /opt/homebrew or /usr/local links inside this dylib
        for dep in get_dependencies(macho):
            if dep.startswith(("/opt/homebrew", "/usr/local")):
                dep_name = Path(dep).name
                new_ref = f"@rpath/{dep_name}"
                run_cmd(["install_name_tool", "-change", dep, new_ref, str(macho)], check=False)

    print("==> Applying ad-hoc code signature (required for Apple Silicon)...")
    # Sign inside out: Frameworks, Plugins, MacOS binaries, then bundle
    for macho in sorted(app_path.rglob("*"), key=lambda p: len(str(p)), reverse=True):
        if is_macho(macho):
            run_cmd(["codesign", "--force", "--sign", "-", str(macho)], check=False)

    for fw in app_path.rglob("*.framework"):
        if fw.is_dir():
            run_cmd(["codesign", "--force", "--sign", "-", str(fw)], check=False)

    res = subprocess.run(["codesign", "--force", "--deep", "--sign", "-", str(app_path)], capture_output=True, text=True)
    if res.returncode == 0:
        print(f"✔︎ Successfully signed {app_path.name}")
    else:
        print(f"Warning during codesign: {res.stderr}")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(f"Usage: {sys.argv[0]} <path_to_app_bundle>")
        sys.exit(1)
    target = Path(sys.argv[1]).resolve()
    if not target.exists():
        print(f"Error: {target} does not exist", file=sys.stderr)
        sys.exit(1)
    bundle_dependencies(target)
