#!/usr/bin/env python3
"""
Generate a build.ninja to compile win32metadata partitions into PDBs.

Usage:
    python3 compile-to-pdb.py [options] [PARTITION ...]   # generate build.ninja
    ninja -C build                                         # build all PDBs
    ninja -C build Memory.pdb                              # build one PDB
    ninja -C build -j$(nproc)                              # parallel build

Compiler flags are read from the win32metadata .rsp files
(sources/GeneratorSdk/tools/assets/scraper/baseSettings*.rsp).
"""

import argparse
import os
import sys


def log(message: str) -> None:
    print(message, file=sys.stderr)


# ---------------------------------------------------------------------------
# .rsp parsing
# ---------------------------------------------------------------------------

def parse_rsp_additional_flags(rsp_path):
    """Extract clang flags from --additional sections of a ClangSharp .rsp file."""
    flags = []
    in_additional = False
    with open(rsp_path) as f:
        for line in f:
            stripped = line.strip()
            if not stripped:
                continue
            if stripped == "--additional":
                in_additional = True
                continue
            if stripped.startswith("--"):
                in_additional = False
                continue
            if in_additional:
                flags.append(stripped)
    return flags


def parse_rsp_traverse_files(rsp_path, include_root, partition_dir):
    """Extract --traverse file paths from a ClangSharp .rsp file.

    Resolves <IncludeRoot> and <PartitionDir> placeholders to absolute paths.
    """
    paths = []
    in_traverse = False
    with open(rsp_path) as f:
        for line in f:
            stripped = line.strip()
            if not stripped:
                continue
            if stripped == "--traverse":
                in_traverse = True
                continue
            if stripped.startswith("--"):
                in_traverse = False
                continue
            if in_traverse:
                resolved = stripped.replace("<IncludeRoot>", include_root)
                resolved = resolved.replace("<PartitionDir>", partition_dir)
                paths.append(resolved)
    return paths


# ---------------------------------------------------------------------------
# Partition discovery
# ---------------------------------------------------------------------------

def discover_partitions(partitions_dir):
    """Return sorted list of partition names that have a main.cpp."""
    names = []
    for entry in sorted(os.listdir(partitions_dir)):
        if os.path.isfile(os.path.join(partitions_dir, entry, "main.cpp")):
            names.append(entry)
    return names


# ---------------------------------------------------------------------------
# Ninja generation helpers
# ---------------------------------------------------------------------------

def ninja_escape(s):
    """Escape a string for ninja build file syntax."""
    return s.replace("$", "$$").replace(" ", "$ ").replace(":", "$:")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(
        description="Generate build.ninja for win32metadata PDB compilation.",
    )
    parser.add_argument(
        "partitions", nargs="*",
        help="Partition names to include (default: all)",
    )
    parser.add_argument(
        "--win32meta-root",
        default=os.path.expanduser("~/win32metadata"),
        help="Path to win32metadata repo root (default: ~/win32metadata)",
    )
    parser.add_argument(
        "--output-dir", "-o", default="build",
        help="Output directory for build.ninja and PDBs (default: build)",
    )
    parser.add_argument(
        "--clang",
        default=os.path.expanduser("~/llvm-project/build/bin/clang"),
        help="Path to patched clang binary",
    )
    parser.add_argument(
        "--lld-link", default="lld-link",
        help="lld-link command (default: lld-link)",
    )
    parser.add_argument(
        "--vc19-include",
        default=os.path.expanduser("~/pdb-test/vc19-include/include"),
        help="Path to VC19 CRT include directory",
    )
    parser.add_argument(
        "--target-triple",
        default="x86_64-pc-windows-msvc",
        help="Clang target triple (default: x86_64-pc-windows-msvc)",
    )
    parser.add_argument(
        "--arch-rsp", action="append", default=[],
        help="Architecture-specific .rsp file name (repeatable, "
             "default: baseSettings.x64.rsp)",
    )
    args = parser.parse_args()

    # --- Derive paths from win32metadata root --------------------------------
    root = os.path.abspath(args.win32meta_root)
    partitions_dir = os.path.join(root, "generation", "WinSDK", "Partitions")
    sdk_inc_root = os.path.join(root, "generation", "WinSDK", "RecompiledIdlHeaders")
    additional_inc = os.path.join(root, "generation", "WinSDK", "inc")
    scraper_dir = os.path.join(
        root, "sources", "GeneratorSdk", "tools", "assets", "scraper",
    )
    base_rsp = os.path.join(scraper_dir, "baseSettings.rsp")

    arch_rsp_names = args.arch_rsp if args.arch_rsp else ["baseSettings.x64.rsp"]
    arch_rsp_paths = [os.path.join(scraper_dir, name) for name in arch_rsp_names]

    for path, label in [
        (partitions_dir, "Partitions directory"),
        (base_rsp, "baseSettings.rsp"),
    ] + [(p, os.path.basename(p)) for p in arch_rsp_paths]:
        if not os.path.exists(path):
            print(f"error: {label} not found: {path}", file=sys.stderr)
            sys.exit(1)

    # --- Parse compiler flags from .rsp files --------------------------------
    clang_flags = parse_rsp_additional_flags(base_rsp)
    for arch_rsp_path in arch_rsp_paths:
        clang_flags += parse_rsp_additional_flags(arch_rsp_path)

    include_dirs = [
        additional_inc,
        os.path.abspath(args.vc19_include),
        os.path.join(sdk_inc_root, "shared"),
        os.path.join(sdk_inc_root, "um"),
        os.path.join(sdk_inc_root, "ucrt"),
        os.path.join(sdk_inc_root, "winrt"),
    ]
    # Also add any subdirectories (cpdk, gl, alljoyn_c, etc.)
    for root_sub in include_dirs[-4:]:
        for entry in sorted(os.listdir(root_sub)):
            sub = os.path.join(root_sub, entry)
            if os.path.isdir(sub):
                include_dirs.append(sub)

    # --- Discover / validate partitions --------------------------------------
    all_partitions = discover_partitions(partitions_dir)
    if args.partitions:
        unknown = set(args.partitions) - set(all_partitions)
        if unknown:
            print(
                f"error: unknown partition(s): {', '.join(sorted(unknown))}",
                file=sys.stderr,
            )
            sys.exit(1)
        partitions = args.partitions
    else:
        partitions = all_partitions

    # --- Prepare output directories ------------------------------------------
    output_dir = os.path.abspath(args.output_dir)
    obj_dir = os.path.join(output_dir, "obj")
    os.makedirs(obj_dir, exist_ok=True)

    clang_bin = os.path.abspath(args.clang)
    lld_link = args.lld_link

    # --- Write shared clang response file ------------------------------------
    # Using a response file (@file) avoids shell-escaping issues with flags
    # like -Wno-#pragma-messages.
    rsp_file = os.path.join(obj_dir, "_compile.rsp")
    with open(rsp_file, "w") as f:
        f.write(f"--target={args.target_triple}\n")
        f.write("-gcodeview\n")
        f.write("-g\n")
        f.write("-fno-eliminate-unused-debug-types\n")
        f.write("-c\n")
        for d in include_dirs:
            f.write(f"-I{d}\n")
        for flag in clang_flags:
            f.write(f"{flag}\n")
        # Suppress remaining warnings — we only care about debug info.
        f.write("-w\n")

    # --- Generate build.ninja ------------------------------------------------
    ninja_path = os.path.join(output_dir, "build.ninja")

    rsp_e = ninja_escape(rsp_file)

    with open(ninja_path, "w") as nf:
        w = nf.write

        w(f"# Generated by compile-to-pdb.py — {len(partitions)} partitions\n\n")

        # Variables (avoid "rspfile" — it's reserved by ninja)
        w(f"clang = {ninja_escape(clang_bin)}\n")
        w(f"lld_link = {ninja_escape(lld_link)}\n")
        w(f"compile_rsp = {rsp_e}\n\n")

        # Rules
        w("rule cc\n")
        w("  command = PDB_TRAVERSE_FILE=$traverse_file $clang @$compile_rsp -o $out $in\n")
        w("  description = CC $partition\n\n")

        # Link .obj into a dummy DLL just to produce the PDB.
        # -dll -noentry       → no entry point needed
        # -nodefaultlib       → no import libraries needed
        # -force:unresolved   → ignore missing symbols (e.g. GUID_NULL)
        w("rule link\n")
        w("  command = $lld_link -dll -noentry -nodefaultlib -force:unresolved"
          " -debug -pdb:$pdb -out:$out $in 2>&1 | grep -v -e '^lld-link' -e '^>>>' || true\n")
        w("  description = PDB $partition\n\n")

        # Per-partition targets
        pdb_aliases = []
        for name in partitions:
            cpp = os.path.join(partitions_dir, name, "main.cpp")
            obj = os.path.join(obj_dir, f"{name}.obj")
            dll = os.path.join(obj_dir, f"{name}.dll")
            pdb = os.path.join(output_dir, f"{name}.pdb")
            traverse_file = os.path.join(obj_dir, f"{name}.traverse")

            # Write per-partition traverse whitelist
            settings_rsp = os.path.join(partitions_dir, name, "settings.rsp")
            partition_dir = os.path.join(partitions_dir, name)
            traverse_paths = parse_rsp_traverse_files(
                settings_rsp, sdk_inc_root, partition_dir,
            )
            with open(traverse_file, "w") as tf:
                for p in traverse_paths:
                    tf.write(p + "\n")

            cpp_e = ninja_escape(cpp)
            obj_e = ninja_escape(obj)
            dll_e = ninja_escape(dll)
            pdb_e = ninja_escape(pdb)
            traverse_e = ninja_escape(traverse_file)

            # compile main.cpp -> .obj
            w(f"build {obj_e}: cc {cpp_e}\n")
            w(f"  partition = {name}\n")
            w(f"  traverse_file = {traverse_e}\n")

            # link .obj -> dummy .dll (+ .pdb as implicit output)
            w(f"build {dll_e} | {pdb_e}: link {obj_e}\n")
            w(f"  pdb = {pdb_e}\n")
            w(f"  partition = {name}\n")

            # phony alias: `ninja Memory.pdb`
            w(f"build {name}.pdb: phony {pdb_e}\n\n")
            pdb_aliases.append(f"{name}.pdb")

        # Default target
        w(f"build all: phony {' '.join(pdb_aliases)}\n")
        w("default all\n")

    log(f"wrote {ninja_path}  ({len(partitions)} partitions)")
    log(f"  rsp: {rsp_file}")
    log(f"  flags from: {base_rsp}")
    for arch_rsp_path in arch_rsp_paths:
        log(f"             {arch_rsp_path}")
    log(f"\nrun:  ninja -C {output_dir}")
    log(f"      ninja -C {output_dir} Memory.pdb        # single partition")
    log(f"      ninja -C {output_dir} -j$(nproc)        # parallel")


if __name__ == "__main__":
    main()
