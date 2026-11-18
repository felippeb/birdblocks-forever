# Publishing

The pipeline mirrors the other Forever addons: CI builds and audits the archive,
a tag always creates a GitHub release, and the same tag uploads to CurseForge
once the project is configured.

## One-time setup for CurseForge

None of this is needed for a GitHub release; without it the upload job is simply
skipped.

1. **CurseForge project** — create it by hand, then note the numeric project id
   from the project page (`/projects/<id>`).
2. **Environment** — in the repository, create an environment called
   `curseforge` with required reviewers and a tag policy. The token lives on the
   environment, so a release run must be approved before it exists.
3. **Secret** — `CURSEFORGE_API_TOKEN` (repository or environment secret).
4. **Variables** — `CURSEFORGE_PROJECT_ID` (the switch: while it is unset, the
   upload job does not run), and optionally `CF_GAME_VERSION_NAME` (default
   `1.60.1`) or `CF_GAME_VERSIONS` with the numeric game-version id if
   discovery ever becomes ambiguous.

The game version is resolved by display name against CurseForge's
`/api/game/versions`. Ids, never names, are what the upload API accepts, so the
script refuses to guess when a name matches more than one version.

## Cutting a release

```powershell
# local dry run: builds, audits and prints metadata, contacts nothing
pwsh -File .\build-zip.ps1 -Version 0.2.0-forever
python tools\audit_zip.py --file release\BirdBlocks-0.2.0-forever.zip
python tools\cf_release.py --file release\BirdBlocks-0.2.0-forever.zip --version 0.2.0-forever --dry-run
```

Keep the `-forever` suffix in the version label. WoWUp's Forever provider only
matches release assets named `*-forever.zip` (or `*-camelot.zip`), so
`BirdBlocks-0.2.0-forever.zip` installs and `BirdBlocks-0.2.0.zip` does not.

Then either run **release** from the Actions tab (pick `alpha`/`beta`/`release`,
optionally `dry_run`) or push a tag:

```powershell
git tag v0.2.0-forever
git push origin v0.2.0-forever
```

A tag runs verify, then creates the GitHub release from the audited archive, and
uploads to CurseForge when `CURSEFORGE_PROJECT_ID` is set. CurseForge holds the
file for moderation; it is not public immediately.

## What the gate checks

- every `.lua` parses (pinned `luaparser`, installed only in the secret-free job);
- the engine, addon and randomised stress suites pass on Lua 5.4;
- the checked-in generated atlas/audio tables still have their expected slots;
- the archive's top level is exactly `BirdBlocks/` with a TOC directly inside;
- no secrets, home paths, save data, executables or stray file types.

The publish jobs never install anything from the network: they run the stdlib
uploader in `tools/cf_release.py` against the archive the verify job built, and
the built-in `gh` CLI for the release asset.
