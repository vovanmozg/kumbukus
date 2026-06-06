# CLAUDE.md

Personal collection of small Linux CLI utilities (mostly bash, one Ruby), installable into `~/bin`. Target platform is **Ubuntu/Debian** (uses `apt` and GNU coreutils — e.g. `stat -c`, `find -maxdepth`).

## Layout

- `apps/` — the utility scripts. **Only executable files at depth 1 are installable** (see `installapps`). `apps/archive/` holds retired scripts.
- `vendor/` — one file per external dependency. The file *content is the install recipe* for that tool on Ubuntu/Debian (NOT a submodule or binary). Recipe shapes seen: apt one-liner (`curl`, `jq`, `pngquant`…), build-from-source (`mozjpeg` → `/opt/mozjpeg/bin`), `.deb` from GitHub releases (`oxipng`), `docker pull` (`media_tools`).
- `config/` — dotfiles/configs installed to `~/.kumbukus` by `installconfigs`. Includes `.aliases` (sources `~/aliases/*`), `config` (entry point, `source ~/.kumbukus/config` from `~/.zshrc`), terminator config, and the nautilus actions config.
- `installapps` / `installconfigs` / `installenv` — bootstrap scripts run via `curl … | bash`.

## Conventions

**Scripts** (`apps/*`): `#!/bin/bash`, a header comment describing behavior, a `usage()` block, explicit arg parsing. Originals are left untouched — output goes to a sibling file or sibling dir (e.g. `tinifyimage.sh` → `./optimized/`). Declare external deps with header comments:

```bash
# requirement: vendor/exiftool
# requirement: vendor/mozjpeg
```

Each `vendor/<name>` referenced there must exist with its install recipe.

**Secrets**: scripts that need API keys `source ~/.env` (e.g. `TINYPNG_API_KEY` in `tinifyimage.sh --online`). `~/.env` is installed separately via `installenv <private_repo_url>` — never commit secrets here.

## Common tasks

**Add a new script**: drop it in `apps/`, `chmod +x` it (required — `installapps` filters on the executable bit), add a header + `usage()` + `# requirement:` lines, and create any missing `vendor/<dep>` recipe files.

**Add a dependency**: create `vendor/<tool>` containing the exact command(s) to install it on Ubuntu/Debian. Reference it from the script via `# requirement: vendor/<tool>`.

**Expose a script in the file-manager right-click menu**: the live menu is `~/.local/share/actions-for-nautilus/config.json`, edited via the actions-for-nautilus GUI (which writes the `config.json.bak.*` / `config.json_*` backups next to it). The repo copy at `config/.local/share/actions-for-nautilus/config.json` is just a **hand-maintained snapshot for version control** — there is no symlink or auto-deploy, so editing it does NOT change the menu, and it tends to lag the live file. Entries are `command_line` strings invoking the apps scripts (e.g. `mergepdf.sh %f`, where `%f` = the selected path). To version a menu change: edit the live file (or via GUI), then copy it into the repo copy.
