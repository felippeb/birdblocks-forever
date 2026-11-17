#!/usr/bin/env python3
"""Publish a built addon zip to CurseForge.

Deliberately stdlib-only: this runs in CI with no install step, and every
branch of it can be exercised offline by tools/test_cf_release.py.

Three jobs, in order:
  1. refuse to upload an archive whose top level is not exactly the addon folders
  2. resolve the game-version id from CurseForge (ids, never names, are what the
     upload API accepts — a wrong one silently publishes to another flavor)
  3. POST the file as multipart/form-data and report what came back

The token is read from CURSEFORGE_API_TOKEN, not from argv, so it never shows
up in a process list or a log line.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
import uuid
import zipfile
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

DEFAULT_API = "https://wow.curseforge.com"
RELEASE_TYPES = ("alpha", "beta", "release")


class ReleaseError(RuntimeError):
    """Anything that should stop the release with a readable message."""


# --------------------------------------------------------------------- archive
def check_archive(path: str, expected_roots: list[str]) -> list[str]:
    """Return the archive's top-level entries, or raise if the layout is wrong."""
    if not os.path.isfile(path):
        raise ReleaseError(f"archive not found: {path}")
    if os.path.getsize(path) == 0:
        raise ReleaseError(f"archive is empty: {path}")

    with zipfile.ZipFile(path) as zf:
        names = [n for n in zf.namelist() if n and not n.endswith("/")]
        if not names:
            raise ReleaseError(f"archive has no entries: {path}")

    roots = sorted({n.split("/", 1)[0] for n in names})
    missing = [r for r in expected_roots if r not in roots]
    extra = [r for r in roots if r not in expected_roots]
    if missing or extra:
        raise ReleaseError(
            "wrong archive root layout.\n"
            f"  expected exactly: {', '.join(expected_roots)}\n"
            f"  found:            {', '.join(roots)}\n"
            f"  missing:          {', '.join(missing) or '-'}\n"
            f"  unexpected:       {', '.join(extra) or '-'}"
        )

    # The client only loads Interface\AddOns\<folder>\<folder>.toc, so a nested
    # build/ or version/ wrapper, or a .toc buried in a subfolder, would
    # install but never run.
    for root in expected_roots:
        direct = any(
            n.startswith(f"{root}/")
            and n.endswith(".toc")
            and "/" not in n[len(root) + 1 :]
            for n in names
        )
        if not direct:
            raise ReleaseError(f"{root}/ has no .toc at its top level")
    return roots


# ------------------------------------------------------------- game versions
def http_json(url: str, token: str, timeout: float = 60.0):
    request = Request(url, headers={"X-Api-Token": token, "Accept": "application/json"})
    try:
        with urlopen(request, timeout=timeout) as response:
            return json.load(response)
    except HTTPError as exc:
        detail = exc.read()[:400].decode("utf-8", "replace")
        raise ReleaseError(f"GET {url} -> HTTP {exc.code}: {detail}") from None
    except URLError as exc:
        raise ReleaseError(f"GET {url} failed: {exc.reason}") from None


def discover_game_version(versions: list[dict], wanted: str) -> int:
    """Resolve a display name such as '1.60.1' to the numeric id uploads want."""
    if not versions:
        raise ReleaseError("CurseForge returned no game versions")

    exact = [v for v in versions if str(v.get("name", "")).strip() == wanted]
    if len(exact) == 1:
        return int(exact[0]["id"])

    if len(exact) > 1:
        rows = "\n".join(
            f"  id={v['id']} type={v.get('gameVersionTypeID')} name={v.get('name')} slug={v.get('slug')}"
            for v in exact
        )
        raise ReleaseError(
            f"'{wanted}' matched {len(exact)} game versions; refusing to guess:\n{rows}\n"
            "set CF_GAME_VERSIONS to the id you want"
        )

    # No exact hit: show near misses instead of dumping all 200 versions.
    stem = re.match(r"\d+\.\d+", wanted)
    near = (
        [v for v in versions if stem and str(v.get("name", "")).startswith(stem.group(0))]
        if stem
        else versions[:20]
    )
    rows = "\n".join(
        f"  id={v['id']} type={v.get('gameVersionTypeID')} name={v.get('name')}" for v in near
    ) or "  (no versions with a similar name)"
    raise ReleaseError(
        f"no game version named '{wanted}'. Candidates:\n{rows}\n"
        "set CF_GAME_VERSIONS to the id you want, or CF_GAME_VERSION_NAME to the right name"
    )


# -------------------------------------------------------------------- upload
def build_metadata(
    display_name: str,
    release_type: str,
    changelog: str,
    game_versions: list[int],
    manual_release: bool = False,
) -> dict:
    if release_type not in RELEASE_TYPES:
        raise ReleaseError(
            f"release type must be one of {', '.join(RELEASE_TYPES)} (got '{release_type}')"
        )
    if not display_name.strip():
        raise ReleaseError("display name is empty")
    if not changelog.strip():
        raise ReleaseError("changelog is empty; CurseForge rejects that")

    metadata = {
        "displayName": display_name.strip(),
        "releaseType": release_type,
        "changelog": changelog,
        "changelogType": "markdown",
        "gameVersions": [int(v) for v in game_versions],
    }
    if manual_release:
        metadata["isMarkedForManualRelease"] = True
    return metadata


def build_multipart(metadata: dict, zip_path: str) -> tuple[str, bytes]:
    boundary = "----birdblocks" + uuid.uuid4().hex
    filename = os.path.basename(zip_path)
    with open(zip_path, "rb") as handle:
        payload = handle.read()

    chunks = [
        f"--{boundary}\r\n".encode(),
        b'Content-Disposition: form-data; name="metadata"\r\n',
        b"Content-Type: application/json\r\n\r\n",
        json.dumps(metadata).encode("utf-8"),
        b"\r\n",
        f"--{boundary}\r\n".encode(),
        f'Content-Disposition: form-data; name="file"; filename="{filename}"\r\n'.encode(),
        b"Content-Type: application/zip\r\n\r\n",
        payload,
        b"\r\n",
        f"--{boundary}--\r\n".encode(),
    ]
    return boundary, b"".join(chunks)


def upload(
    api_base: str,
    project_id: str,
    token: str,
    metadata: dict,
    zip_path: str,
    timeout: float = 600.0,
) -> tuple[int, str]:
    boundary, body = build_multipart(metadata, zip_path)
    url = f"{api_base}/api/projects/{project_id}/upload-file"
    request = Request(url, data=body, method="POST")
    request.add_header("X-Api-Token", token)
    request.add_header("Content-Type", f"multipart/form-data; boundary={boundary}")

    try:
        with urlopen(request, timeout=timeout) as response:
            return response.status, response.read().decode("utf-8", "replace")
    except HTTPError as exc:
        return exc.code, exc.read().decode("utf-8", "replace")
    except URLError as exc:
        raise ReleaseError(f"POST {url} failed: {exc.reason}") from None


# ----------------------------------------------------------------------- copy
def head_section(text: str) -> str:
    """CurseForge shows one release's notes, so send the newest section only."""
    lines = text.splitlines()
    start = next((i for i, line in enumerate(lines) if line.startswith("## ")), None)
    if start is None:
        return text.strip()
    end = next(
        (i for i in range(start + 1, len(lines)) if lines[i].startswith("## ")), len(lines)
    )
    return "\n".join(lines[start:end]).strip()


def read_text(path: str) -> str:
    if not os.path.isfile(path):
        raise ReleaseError(f"file not found: {path}")
    with open(path, encoding="utf-8-sig") as handle:
        return handle.read()


# ----------------------------------------------------------------------- main
def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="upload an addon zip to CurseForge")
    parser.add_argument("--file", required=True, help="path to the built zip")
    parser.add_argument("--version", required=True, help="display name, e.g. 0.1.0")
    parser.add_argument("--release-type", default="alpha", choices=RELEASE_TYPES)
    parser.add_argument("--changelog-file", default="CHANGELOG.md")
    parser.add_argument(
        "--expect-roots",
        default="BirdBlocks",
        help="comma-separated top-level folders the archive must contain",
    )
    parser.add_argument("--project-id", default=os.environ.get("CURSEFORGE_PROJECT_ID"))
    parser.add_argument("--api", default=os.environ.get("CURSEFORGE_API", DEFAULT_API))
    parser.add_argument("--token", default=os.environ.get("CURSEFORGE_API_TOKEN"))
    parser.add_argument(
        "--game-version-id",
        default=os.environ.get("CF_GAME_VERSIONS", "").strip(),
        help="numeric id; skips discovery when set",
    )
    parser.add_argument(
        "--game-version-name",
        default=os.environ.get("CF_GAME_VERSION_NAME", "1.60.1"),
        help="display name to resolve when no id is given",
    )
    parser.add_argument("--manual-release", action="store_true")
    parser.add_argument(
        "--dry-run", action="store_true", help="validate and print, contact nothing"
    )
    args = parser.parse_args(argv)

    expected = [r.strip() for r in args.expect_roots.split(",") if r.strip()]
    roots = check_archive(args.file, expected)
    print(f"archive ok: {args.file}")
    print(f"top level:  {', '.join(roots)}")

    changelog = head_section(read_text(args.changelog_file))

    if args.game_version_id:
        game_versions = [int(v) for v in re.split(r"[,\s]+", args.game_version_id) if v]
        print(f"game versions: {game_versions} (from CF_GAME_VERSIONS)")
    elif args.dry_run:
        game_versions = []
        print(f"game versions: would resolve '{args.game_version_name}' (dry run)")
    else:
        if not args.token:
            raise ReleaseError("CURSEFORGE_API_TOKEN is not set")
        print(f"resolving game version '{args.game_version_name}' ...")
        versions = http_json(f"{args.api}/api/game/versions", args.token)
        game_versions = [discover_game_version(versions, args.game_version_name)]
        print(f"game versions: {game_versions} (resolved)")

    if not game_versions and not args.dry_run:
        raise ReleaseError("no game versions resolved")

    metadata = build_metadata(
        args.version, args.release_type, changelog, game_versions, args.manual_release
    )

    if args.dry_run:
        printable = dict(metadata)
        printable["changelog"] = f"<{len(metadata['changelog'])} chars>"
        print("metadata:")
        print(json.dumps(printable, indent=2))
        print("dry run: nothing was uploaded")
        return 0

    if not args.project_id:
        raise ReleaseError("project id missing (set CURSEFORGE_PROJECT_ID)")
    if not args.token:
        raise ReleaseError("CURSEFORGE_API_TOKEN is not set")

    print(f"uploading to project {args.project_id} as {args.release_type} ...")
    status, body = upload(args.api, args.project_id, args.token, metadata, args.file)

    print(f"CurseForge HTTP {status}")
    print(body.strip() or "(empty response)")

    if not 200 <= status < 300:
        raise ReleaseError(f"upload rejected with HTTP {status}")

    try:
        file_id = json.loads(body).get("id")
    except ValueError:
        file_id = None
    if file_id:
        print(f"file id: {file_id}")
        if os.environ.get("GITHUB_STEP_SUMMARY"):
            with open(os.environ["GITHUB_STEP_SUMMARY"], "a", encoding="utf-8") as out:
                out.write(f"### CurseForge\n\n- file id: `{file_id}`\n- type: `{args.release_type}`\n")
    else:
        print("warning: response had no file id")
    print("accepted for moderation; it is not public until CurseForge approves it")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except ReleaseError as error:
        print(f"error: {error}", file=sys.stderr)
        sys.exit(1)
