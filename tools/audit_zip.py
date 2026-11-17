#!/usr/bin/env python3
"""Refuse to publish an archive that carries secrets, private paths or junk.

Runs last, on the exact bytes that are about to be uploaded, and fails the
build if anything looks like it should not be public. Stdlib only, so there is
no dependency to trust in the job that holds the CurseForge token.
"""

from __future__ import annotations

import argparse
import os
import re
import sys
import zipfile

from cf_release import ReleaseError, check_archive

# Extensions that legitimately ship inside a WoW addon.
ALLOWED_EXT = {
    ".lua", ".toc", ".xml", ".md", ".txt",
    ".blp", ".tga", ".png", ".jpg", ".jpeg", ".gif",
    ".ttf", ".otf", ".ttc", ".wav", ".ogg", ".mp3",
}
# Extension-less files that are fine by name.
ALLOWED_NAMES = {"LICENSE", "NOTICE", "COPYING", "README", "CHANGELOG", "AUTHORS"}

# Never ship these, whatever they contain.
FORBIDDEN_EXT = {
    ".bak", ".orig", ".rej", ".patch", ".zip", ".rar", ".7z", ".tar", ".gz",
    ".log", ".exe", ".dll", ".so", ".dylib", ".bat", ".cmd", ".ps1", ".py",
    ".sh", ".js", ".env", ".pem", ".key", ".p12", ".pfx", ".db", ".sqlite",
}
FORBIDDEN_PARTS = {
    ".git", ".github", "wtf", "savedvariables", "logs", ".idea", ".vscode",
    "__pycache__", "node_modules",
}
FORBIDDEN_NAMES = {".ds_store", "thumbs.db", "desktop.ini", ".gitignore", ".gitattributes"}

# Content that must never reach the public.
SECRET_PATTERNS = [
    ("github token", re.compile(r"\b(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,})\b")),
    ("aws key", re.compile(r"\bAKIA[0-9A-Z]{16}\b")),
    ("private key", re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----")),
    ("bearer header", re.compile(r"(?i)authorization\s*:\s*bearer\s+\S{8,}")),
    ("api token header", re.compile(r"(?i)x-api-token\s*[:=]\s*\S{8,}")),
    ("windows home path", re.compile(r"[A-Za-z]:\\\\?Users\\\\?[^\\\\\s\"']{2,}")),
    ("unix home path", re.compile(r"/(?:home|Users)/[^/\s\"']{2,}")),
    ("wow account dir", re.compile(r"(?i)WTF\\\\?Account\\\\?")),
]

TEXT_EXT = {".lua", ".toc", ".xml", ".md", ".txt"}


def audit(path: str, expected_roots: list[str], max_mb: float = 40.0) -> dict:
    roots = check_archive(path, expected_roots)
    problems: list[str] = []
    entries = 0

    size_mb = os.path.getsize(path) / (1024 * 1024)
    if size_mb > max_mb:
        problems.append(f"archive is {size_mb:.1f} MB, over the {max_mb:.0f} MB limit")

    with zipfile.ZipFile(path) as zf:
        for info in zf.infolist():
            name = info.filename
            if name.endswith("/"):
                continue
            entries += 1

            # zip-slip / portability: absolute, traversing or backslash paths
            if name.startswith("/") or ".." in name.split("/") or "\\" in name:
                problems.append(f"{name}: unsafe path")
                continue

            parts = [p.lower() for p in name.split("/")]
            base = parts[-1]
            ext = os.path.splitext(base)[1].lower()

            bad_part = next((p for p in parts[:-1] if p in FORBIDDEN_PARTS), None)
            if bad_part:
                problems.append(f"{name}: forbidden directory '{bad_part}'")
                continue
            if base in FORBIDDEN_NAMES:
                problems.append(f"{name}: forbidden file")
                continue
            if ext in FORBIDDEN_EXT:
                problems.append(f"{name}: forbidden extension '{ext}'")
                continue
            if ext not in ALLOWED_EXT and base.upper() not in ALLOWED_NAMES:
                problems.append(f"{name}: unexpected file type '{ext or 'none'}'")
                continue

            if ext in TEXT_EXT or base.upper() in ALLOWED_NAMES:
                blob = zf.read(info)
                text = blob.decode("utf-8", "replace")
                for label, pattern in SECRET_PATTERNS:
                    found = pattern.search(text)
                    if found:
                        snippet = found.group(0)[:8] + "..."
                        problems.append(f"{name}: looks like a {label} ({snippet})")

    return {
        "path": path,
        "roots": roots,
        "entries": entries,
        "size_mb": round(size_mb, 1),
        "problems": problems,
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="audit a release archive before publishing")
    parser.add_argument("--file", required=True)
    parser.add_argument("--expect-roots", default="BirdBlocks")
    parser.add_argument("--max-mb", type=float, default=40.0)
    args = parser.parse_args(argv)

    expected = [r.strip() for r in args.expect_roots.split(",") if r.strip()]
    try:
        report = audit(args.file, expected, args.max_mb)
    except ReleaseError as error:
        print(f"error: {error}", file=sys.stderr)
        return 1

    print(
        f"audited {report['entries']} files, {report['size_mb']} MB, "
        f"roots: {', '.join(report['roots'])}"
    )
    if report["problems"]:
        print(f"FAILED: {len(report['problems'])} problem(s)", file=sys.stderr)
        for problem in report["problems"]:
            print(f"  {problem}", file=sys.stderr)
        return 1

    print("no secrets, private paths or stray files found")
    return 0


if __name__ == "__main__":
    sys.exit(main())
