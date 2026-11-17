# Publishing

The pipeline mirrors the other Forever addons: CI builds and audits the archive,
and a tag publishes it to CurseForge and creates a GitHub release.

## One-time setup

1. **GitHub repository** — `felippeb/birdblocks-forever`. The release workflow
   is gated on this exact name (`.github/workflows/release.yml`).
2. **CurseForge project** — create it by hand, then note the numeric project id
   from the project page (`/projects/<id>`).
3. **Environment** — in the repository, create an environment called
   `curseforge` with required reviewers and a tag policy. The token lives on the
   environment, so a release run must be approved before it exists.
4. **Secret** — `CURSEFORGE_API_TOKEN` (repository or environment secret).
5. **Variables** — `CURSEFORGE_PROJECT_ID`, and optionally
   `CF_GAME_VERSION_NAME` (default `1.60.1`) or `CF_GAME_VERSIONS` with the
   numeric game-version id if discovery ever becomes ambiguous.

The game version is resolved by display name against CurseForge's
`/api/game/versions`. Ids, never names, are what the upload API accepts, so the
script refuses to guess when a name matches more than one version.

## Cutting a release

```powershell
# local dry run: builds, audits and prints metadata, contacts nothing
pwsh -File .\build-zip.ps1 -Version 0.2.0
python tools\audit_zip.py --file release\BirdBlocks-0.2.0.zip
python tools\cf_release.py --file release\BirdBlocks-0.2.0.zip --version 0.2.0 --dry-run
```

Then either run **release** from the Actions tab (pick `alpha`/`beta`/`release`,
optionally `dry_run`) or push a tag:

```powershell
git tag v0.2.0
git push origin v0.2.0
```

A tag runs verify, uploads the audited archive, and creates the GitHub release.
CurseForge holds the file for moderation; it is not public immediately.

## What the gate checks

- every `.lua` parses (pinned `luaparser`, installed only in the secret-free job);
- the engine, addon and randomised stress suites pass on Lua 5.4;
- the checked-in generated atlas/audio tables still have their expected slots;
- the archive's top level is exactly `BirdBlocks/` with a TOC directly inside;
- no secrets, home paths, save data, executables or stray file types.

The publish job never installs anything from the network: it runs the stdlib
uploader in `tools/cf_release.py` against the archive the verify job built.
