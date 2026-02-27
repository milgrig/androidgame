"""
GDScript static linter — catches patterns that cause black-screen crashes in Godot 4.6.

Run:  python tests/fast/lint/lint_gdscript.py
Exit code 0 = clean, 1 = errors found.

Checks:
  L001  Inner class used as type annotation across files (ClassName.InnerClass)
  L002  class_name script missing from global_script_class_cache.cfg
  L003  .uid file missing for a class_name script
  L004  := with known Variant-returning expressions (Dictionary.get, untyped array index)
"""
import re
import sys
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent.parent.parent.parent
SRC_DIR = PROJECT_ROOT / "src"
CACHE_FILE = PROJECT_ROOT / ".godot" / "global_script_class_cache.cfg"

# ── Helpers ──────────────────────────────────────────────────────────

def find_gd_files(root: Path) -> list[Path]:
    return sorted(root.rglob("*.gd"))


def extract_class_name(path: Path) -> str | None:
    """Return the class_name declared in a .gd file, or None."""
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        m = re.match(r"^class_name\s+(\w+)", line)
        if m:
            return m.group(1)
    return None


def extract_inner_classes(path: Path) -> list[str]:
    """Return inner class names declared in a .gd file."""
    names = []
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        m = re.match(r"^class\s+(\w+)\s*:", line)
        if m:
            names.append(m.group(1))
    return names


def load_cache_classes(cache_path: Path) -> set[str]:
    """Parse global_script_class_cache.cfg and return registered class names."""
    if not cache_path.exists():
        return set()
    text = cache_path.read_text(encoding="utf-8", errors="replace")
    return set(re.findall(r'"class":\s*&"(\w+)"', text))


# ── Checks ───────────────────────────────────────────────────────────

def check_L001_inner_class_type_annotations(gd_files: list[Path]) -> list[str]:
    """L001: ClassName.InnerClass used as type annotation in another file.

    Two severity levels:
    - ERROR if the outer class is NOT registered in global_script_class_cache.cfg
      (high risk of parse failure due to class load order)
    - WARN  if the outer class IS registered (works in practice, but fragile)
    """
    cached = load_cache_classes(CACHE_FILE)

    # Build map: class_name -> set of inner class names
    inner_map: dict[str, set[str]] = {}
    class_to_file: dict[str, Path] = {}
    for f in gd_files:
        cn = extract_class_name(f)
        if cn:
            class_to_file[cn] = f
            inners = extract_inner_classes(f)
            if inners:
                inner_map[cn] = set(inners)

    errors = []
    # Pattern: SomeClass.InnerClass used as type (in var declarations, function params, return types)
    pattern = re.compile(r"(\w+)\.(\w+)")
    for f in gd_files:
        own_class = extract_class_name(f)
        lines = f.read_text(encoding="utf-8", errors="replace").splitlines()
        for lineno, line in enumerate(lines, 1):
            # Skip comments
            stripped = line.lstrip()
            if stripped.startswith("#") or stripped.startswith("##"):
                continue
            # Strip inline comments before scanning for type annotations
            code_part = line.split("#")[0] if "#" in line else line
            for m in pattern.finditer(code_part):
                outer, inner = m.group(1), m.group(2)
                # Check if it's a known ClassName.InnerClass reference in a DIFFERENT file
                if outer in inner_map and inner in inner_map[outer]:
                    if own_class != outer:  # cross-file reference
                        # Check context: is it used as a type annotation?
                        if any(kw in code_part for kw in ["var ", "func ", "-> ", ": "]):
                            rel = f.relative_to(PROJECT_ROOT)
                            if outer not in cached:
                                # Outer class not registered — HIGH risk
                                errors.append(
                                    f"L001 {rel}:{lineno}: Cross-file inner class type "
                                    f"'{outer}.{inner}' — outer class not in cache, will crash"
                                )
                            else:
                                # Outer class registered — lower risk, warn only
                                errors.append(
                                    f"L001-warn {rel}:{lineno}: Cross-file inner class type "
                                    f"'{outer}.{inner}' — works but fragile, consider extracting"
                                )
    return errors


def check_L002_cache_registration(gd_files: list[Path]) -> list[str]:
    """L002: class_name script not registered in global_script_class_cache.cfg."""
    cached = load_cache_classes(CACHE_FILE)
    errors = []
    for f in gd_files:
        cn = extract_class_name(f)
        if cn and cn not in cached:
            rel = f.relative_to(PROJECT_ROOT)
            errors.append(
                f"L002 {rel}: class_name '{cn}' not in global_script_class_cache.cfg — "
                f"open project in Godot editor to regenerate, or add manually"
            )
    return errors


def check_L003_missing_uid(gd_files: list[Path]) -> list[str]:
    """L003: class_name script missing .uid file."""
    errors = []
    for f in gd_files:
        cn = extract_class_name(f)
        if cn:
            uid_path = f.with_suffix(".gd.uid")
            if not uid_path.exists():
                rel = f.relative_to(PROJECT_ROOT)
                errors.append(
                    f"L003 {rel}: class_name '{cn}' has no .uid file — "
                    f"open project in Godot editor to generate it"
                )
    return errors


# Patterns known to return Variant in GDScript 4.6
VARIANT_RETURN_PATTERNS = [
    # dict.get(key, default)  — always returns Variant
    re.compile(r":=\s+\w+\.get\("),
    # dict[key]  — returns Variant for untyped Dictionary
    re.compile(r":=\s+\w+\["),
    # .duplicate()  without `as Type` cast
    re.compile(r":=\s+\w+\.duplicate\(\)(?!\s+as\s)"),
]

# Exceptions: these return typed values even though they look like dict access
VARIANT_FALSE_POSITIVES = [
    # Array.find() returns int — not a problem
    re.compile(r":=\s+\w+\.find\("),
    # .new() returns the class — not a problem
    re.compile(r":=\s+\w+\.new\("),
    # .size() returns int
    re.compile(r":=\s+\w+\.size\("),
]


def check_L004_variant_inference(gd_files: list[Path]) -> list[str]:
    """L004: := with Variant-returning expression (warning-as-error in Godot 4.6)."""
    errors = []
    for f in gd_files:
        lines = f.read_text(encoding="utf-8", errors="replace").splitlines()
        for lineno, line in enumerate(lines, 1):
            stripped = line.lstrip()
            if stripped.startswith("#") or stripped.startswith("##"):
                continue
            if ":=" not in stripped:
                continue

            # Check each Variant pattern
            for pat in VARIANT_RETURN_PATTERNS:
                if pat.search(stripped):
                    # Filter false positives
                    is_fp = any(fp.search(stripped) for fp in VARIANT_FALSE_POSITIVES)
                    if not is_fp:
                        rel = f.relative_to(PROJECT_ROOT)
                        errors.append(
                            f"L004 {rel}:{lineno}: ':=' infers Variant — "
                            f"use explicit type annotation instead: {stripped.strip()}"
                        )
                    break  # one error per line
    return errors


# ── Main ─────────────────────────────────────────────────────────────

def main() -> int:
    gd_files = find_gd_files(SRC_DIR)
    print(f"Scanning {len(gd_files)} .gd files in {SRC_DIR.relative_to(PROJECT_ROOT)}/...")

    all_errors: list[str] = []
    all_errors += check_L001_inner_class_type_annotations(gd_files)
    all_errors += check_L002_cache_registration(gd_files)
    all_errors += check_L003_missing_uid(gd_files)
    all_errors += check_L004_variant_inference(gd_files)

    # Split errors vs warnings
    real_errors = [e for e in all_errors if "-warn " not in e]
    warnings = [e for e in all_errors if "-warn " in e]

    if warnings:
        print(f"\n{len(warnings)} warning(s):\n")
        for w in sorted(warnings):
            print(f"  {w}")

    if real_errors:
        print(f"\n{len(real_errors)} error(s) found:\n")
        for e in sorted(real_errors):
            print(f"  {e}")
        print(f"\n--- {len(real_errors)} error(s), {len(warnings)} warning(s) ---")
        return 1
    else:
        if warnings:
            print(f"\n--- 0 errors, {len(warnings)} warning(s) ---")
        else:
            print("All checks passed.")
        return 0


if __name__ == "__main__":
    sys.exit(main())
