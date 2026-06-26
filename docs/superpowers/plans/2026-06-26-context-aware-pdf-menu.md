# Context-aware PDF submenu Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the Nautilus right-click `PDF` submenu show only the items that fit what was clicked — image → `Make PDF`; folder → `Make PDF` + `Merge PDFs`; PDF → `PDF compress` + `PDF ultra compress` — and let `Make PDF` also turn a single image into a PDF.

**Architecture:** One script `makepdf.sh` is extended to accept either a directory (current behavior) or a single image file (new), with shared non-overwriting output naming. The `PDF` menu in the actions-for-nautilus `config.json` gains per-item `mimetypes`/`filetypes` filters so each item only appears in the right context; the two `Make PDF` cases collapse into one entry.

**Tech Stack:** Bash, ImageMagick (`convert`), actions-for-nautilus (Nautilus Python extension), `jq`, `pdfinfo` (for tests).

## Global Constraints

- All script/config edits are made in the **`~/pro/kumbukus`** repo (the source of truth), then installed/copied to live locations. Do **not** hand-edit live files as the primary change.
- Scripts live in `~/pro/kumbukus/apps/` and install to `~/bin`. Keep the family header convention: `#!/bin/bash` and a `# requirement: vendor/imagemagick` comment.
- actions-for-nautilus rules (verified in `/usr/share/nautilus-python/extensions/actions-for-nautilus/`): `mimetypes` supports the `image/*` wildcard (`startswith` match) and `!`-negation; `filetypes` are exact (`file`, `directory`); an action shows only when **every** selected item matches its filters; `%f` runs the command **once per selected file**.
- `config.json` update flow: (1) verify repo `config/.local/share/actions-for-nautilus/config.json` matches live `~/.local/share/actions-for-nautilus/config.json`, reconciling repo from live if they drift; (2) edit + commit in repo; (3) copy repo config to live.
- Spec: `docs/superpowers/specs/2026-06-26-context-aware-pdf-menu-design.md`.

---

## File Structure

- **Modify:** `~/pro/kumbukus/apps/makepdf.sh` — accept file-or-directory, non-overwriting output (the single behavioral change to script logic).
- **Create:** `~/pro/kumbukus/tests/behavior/test_makepdf.sh` — behavioral test exercising both modes against real fixtures.
- **Create:** `~/pro/kumbukus/tests/behavior/run-all.sh` — runner for `tests/behavior/test_*.sh` (mirrors `tests/selftest/run-all.sh`).
- **Modify:** `~/pro/kumbukus/config/.local/share/actions-for-nautilus/config.json` — restructure the `PDF` menu with filters.

---

## Task 1: Extend `makepdf.sh` to accept a file or a directory (non-overwriting)

**Files:**
- Modify: `~/pro/kumbukus/apps/makepdf.sh`
- Create: `~/pro/kumbukus/tests/behavior/test_makepdf.sh`
- Create: `~/pro/kumbukus/tests/behavior/run-all.sh`

**Interfaces:**
- Consumes: nothing.
- Produces: CLI `makepdf.sh <image-file-or-directory>`. Directory → combines `*.jpg`/`*.png` (maxdepth 1, sorted) into `<dir>.pdf` next to the folder. Single image file → `<name>.pdf` next to it. Both modes never overwrite: if the target exists, use `<base>-1.pdf`, `<base>-2.pdf`, … Empty/imageless directory → prints a message and exits 0. Non-existent / non-image argument → prints a message and exits 1.

- [ ] **Step 1: Write the failing test**

Create `~/pro/kumbukus/tests/behavior/test_makepdf.sh`:

```bash
#!/bin/bash
# Behavioral tests for apps/makepdf.sh (file-or-directory → PDF, non-overwriting).
# Requires: imagemagick (convert), pdfinfo (poppler-utils).
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/../.." && pwd)"
# shellcheck source=/dev/null
source "$repo/tests/selftest/assert.sh"

MAKEPDF="$repo/apps/makepdf.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

mkimg() { convert -size 10x10 "xc:$2" "$1"; }   # mkimg <path> <color>
pages() { pdfinfo "$1" 2>/dev/null | awk '/^Pages:/ {print $2}'; }

# --- single image file ---
mkdir -p "$work/single"
mkimg "$work/single/photo.jpg" white
bash "$MAKEPDF" "$work/single/photo.jpg" >/dev/null
assert_eq "1" "$([ -f "$work/single/photo.pdf" ] && echo 1 || echo 0)" "file mode creates photo.pdf"
assert_eq "1" "$(pages "$work/single/photo.pdf")" "file mode PDF has 1 page"

# --- single image, second run does not overwrite ---
bash "$MAKEPDF" "$work/single/photo.jpg" >/dev/null
assert_eq "1" "$([ -f "$work/single/photo-1.pdf" ] && echo 1 || echo 0)" "file mode second run writes photo-1.pdf"

# --- directory of 2 images → one 2-page PDF next to the folder ---
mkdir -p "$work/album"
mkimg "$work/album/01.jpg" white
mkimg "$work/album/02.png" black
bash "$MAKEPDF" "$work/album" >/dev/null
assert_eq "1" "$([ -f "$work/album.pdf" ] && echo 1 || echo 0)" "dir mode creates album.pdf next to folder"
assert_eq "2" "$(pages "$work/album.pdf")" "dir mode PDF has 2 pages"

# --- directory, second run does not overwrite ---
bash "$MAKEPDF" "$work/album" >/dev/null
assert_eq "1" "$([ -f "$work/album-1.pdf" ] && echo 1 || echo 0)" "dir mode second run writes album-1.pdf"

# --- empty directory → exit 0, no PDF ---
mkdir -p "$work/empty"
bash "$MAKEPDF" "$work/empty" >/dev/null
rc=$?
assert_eq "0" "$rc" "empty dir exits 0"
assert_eq "0" "$([ -f "$work/empty.pdf" ] && echo 1 || echo 0)" "empty dir produces no PDF"

# --- bogus argument → non-zero exit ---
bash "$MAKEPDF" "$work/does-not-exist" >/dev/null 2>&1
assert_eq "1" "$?" "missing path exits 1"

exit "$FAILS"
```

Also create the runner `~/pro/kumbukus/tests/behavior/run-all.sh`:

```bash
#!/bin/bash
# Runs every tests/behavior/test_*.sh; non-zero exit if any fail.
here="$(cd "$(dirname "$0")" && pwd)"
rc=0
shopt -s nullglob
for t in "$here"/test_*.sh; do
  echo "== $(basename "$t") =="
  bash "$t" || rc=1
done
exit "$rc"
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash ~/pro/kumbukus/tests/behavior/test_makepdf.sh`
Expected: FAIL — current `makepdf.sh` rejects a file argument ("Directory does not exists") and overwrites in directory mode, so the file-mode and non-overwrite assertions fail.

- [ ] **Step 3: Rewrite `makepdf.sh` with file-or-directory support and non-overwriting output**

Replace the entire contents of `~/pro/kumbukus/apps/makepdf.sh` with:

```bash
#!/bin/bash

# requirement: vendor/imagemagick
#
# Make a PDF from images.
#   makepdf.sh <directory>    combine *.jpg/*.png in the folder into <directory>.pdf
#   makepdf.sh <image-file>   convert a single image into <name>.pdf next to it
# Output is written next to the input and never overwrites: if the target
# exists, <base>-1.pdf, <base>-2.pdf, ... is used instead.

set -euo pipefail

if [ "$#" -ne 1 ]; then
    echo "Using: $0 <image-file-or-directory>"
    exit 1
fi

arg="$1"

if [ -d "$arg" ]; then
    readarray -t imgs < <(find "$arg" -maxdepth 1 -type f \( -iname "*.jpg" -o -iname "*.png" \) | sort)
    if [ ${#imgs[@]} -eq 0 ]; then
        echo "No images found in $arg"
        exit 0
    fi
    out_dir=$(dirname "$arg")
    out_name=$(basename "$arg")
elif [ -f "$arg" ]; then
    imgs=("$arg")
    out_dir=$(dirname "$arg")
    out_name=$(basename "${arg%.*}")
else
    echo "Not a file or directory: $arg"
    exit 1
fi

# Pick an unused output name, then convert.
out="$out_dir/$out_name.pdf"
i=1
while [ -e "$out" ]; do
    out="$out_dir/$out_name-$i.pdf"
    i=$((i + 1))
done

convert "${imgs[@]}" "$out"
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash ~/pro/kumbukus/tests/behavior/test_makepdf.sh`
Expected: every line `PASS`, exit code 0.

- [ ] **Step 5: Sanity-check shell syntax**

Run: `bash -n ~/pro/kumbukus/apps/makepdf.sh && command -v shellcheck >/dev/null && shellcheck ~/pro/kumbukus/apps/makepdf.sh || echo "shellcheck not installed, skipped"`
Expected: no syntax errors (shellcheck warnings, if any, are acceptable).

- [ ] **Step 6: Commit**

```bash
cd ~/pro/kumbukus
chmod +x tests/behavior/test_makepdf.sh tests/behavior/run-all.sh
git add apps/makepdf.sh tests/behavior/test_makepdf.sh tests/behavior/run-all.sh
git commit -m "makepdf.sh: accept a single image file or a directory, never overwrite output"
```

---

## Task 2: Filter the `PDF` menu in `config.json` and apply it

**Files:**
- Modify: `~/pro/kumbukus/config/.local/share/actions-for-nautilus/config.json`

**Interfaces:**
- Consumes: `makepdf.sh <file-or-dir>` from Task 1 (installed to `~/bin`); existing `compresspdf.sh`, `mergepdf.sh`.
- Produces: a `PDF` menu whose items appear contextually — image → `Make PDF`; folder → `Make PDF` + `Merge PDFs`; PDF file → `PDF compress` + `PDF ultra compress`.

- [ ] **Step 1: Verify the repo config matches the live config (sync gate)**

Run:
```bash
diff ~/pro/kumbukus/config/.local/share/actions-for-nautilus/config.json \
     ~/.local/share/actions-for-nautilus/config.json && echo IDENTICAL
```
Expected: `IDENTICAL`.
If it differs: the live file has out-of-repo edits — copy live → repo first (`cp ~/.local/share/actions-for-nautilus/config.json ~/pro/kumbukus/config/.local/share/actions-for-nautilus/config.json`), inspect the diff, and commit that reconciliation before continuing.

- [ ] **Step 2: Edit the `PDF` menu's `actions` array in the repo config**

In `~/pro/kumbukus/config/.local/share/actions-for-nautilus/config.json`, find the top-level menu object with `"label": "PDF"` and replace its `"actions"` array so it reads exactly:

```json
            "actions": [
                {
                    "type": "command",
                    "label": "Make PDF",
                    "command_line": "makepdf.sh %f",
                    "mimetypes": [
                        "image/*",
                        "inode/directory"
                    ],
                    "filetypes": [
                        "file",
                        "directory"
                    ]
                },
                {
                    "type": "command",
                    "label": "PDF compress",
                    "command_line": "compresspdf.sh %f",
                    "mimetypes": [
                        "application/pdf"
                    ]
                },
                {
                    "type": "command",
                    "label": "PDF ultra compress",
                    "command_line": "compresspdf.sh %f --width=1000",
                    "mimetypes": [
                        "application/pdf"
                    ]
                },
                {
                    "type": "command",
                    "label": "Merge PDFs",
                    "command_line": "mergepdf.sh %f",
                    "filetypes": [
                        "directory"
                    ]
                }
            ]
```

(This drops the duplicate `Make PDF`, adds the filters, removes the stray leading spaces in the two `compresspdf.sh` command lines.)

- [ ] **Step 3: Validate JSON and assert the new filters are present**

Run:
```bash
cfg=~/pro/kumbukus/config/.local/share/actions-for-nautilus/config.json
jq -e . "$cfg" >/dev/null && echo "VALID JSON"
jq -e '
  (.actions[] | select(.label=="PDF").actions) as $pdf
  | ([ $pdf[].label ] == ["Make PDF","PDF compress","PDF ultra compress","Merge PDFs"])
    and (($pdf[] | select(.label=="Make PDF").mimetypes) == ["image/*","inode/directory"])
    and (($pdf[] | select(.label=="Make PDF").filetypes) == ["file","directory"])
    and (($pdf[] | select(.label=="PDF compress").mimetypes) == ["application/pdf"])
    and (($pdf[] | select(.label=="PDF compress").command_line) == "compresspdf.sh %f")
' "$cfg" >/dev/null && echo "PDF MENU OK"
```
Expected: `VALID JSON` then `PDF MENU OK`.

- [ ] **Step 4: Commit the repo config**

```bash
cd ~/pro/kumbukus
git add config/.local/share/actions-for-nautilus/config.json
git commit -m "actions-for-nautilus: make the PDF submenu context-aware (image/folder/pdf)"
```

- [ ] **Step 5: Install the script and apply the config to live, then reload Nautilus**

```bash
cp ~/pro/kumbukus/apps/makepdf.sh ~/bin/makepdf.sh
chmod +x ~/bin/makepdf.sh
cp ~/pro/kumbukus/config/.local/share/actions-for-nautilus/config.json \
   ~/.local/share/actions-for-nautilus/config.json
jq -e . ~/.local/share/actions-for-nautilus/config.json >/dev/null && echo "LIVE CONFIG VALID"
nautilus -q
```
Expected: `LIVE CONFIG VALID`; Nautilus quits (relaunches on next folder open).

- [ ] **Step 6: Manual verification in Nautilus**

Open a folder containing a `.jpg`, a subfolder of images, and a `.pdf`, then check the right-click `PDF` submenu in each case:
- Right-click the `.jpg` → `PDF` shows **only** `Make PDF`; clicking it creates `<name>.pdf` next to the image (and `<name>-1.pdf` on a second run).
- Select two images → `Make PDF` creates one PDF per image.
- Right-click the subfolder → `PDF` shows `Make PDF` + `Merge PDFs`; `Make PDF` creates `<folder>.pdf` next to it.
- Right-click the `.pdf` → `PDF` shows `PDF compress` + `PDF ultra compress`; `Make PDF` and `Merge PDFs` do **not** appear.

---

## Self-Review

**Spec coverage:**
- Image → only `Make PDF`, PDF next to image → Task 1 (file mode) + Task 2 (filters); verified Task 2 Step 6.
- Single image file is new behavior → Task 1.
- Multi-select images → one PDF each → relies on `%f` per-file semantics (Global Constraints); verified Task 2 Step 6.
- Folder → `Make PDF` + `Merge PDFs`, current behavior → Task 2 combined filters keep both; Task 1 preserves directory mode.
- PDF → `PDF compress` + `PDF ultra compress` → Task 2 mimetype filters.
- Non-overwriting output (both modes) → Task 1 Step 3 + tests.
- Config sync flow (verify → edit → copy) → Task 2 Steps 1–5.
- Stray leading spaces removed → Task 2 Step 2.

**Placeholder scan:** none — all script and config bodies are complete.

**Type/name consistency:** `makepdf.sh <file-or-dir>` interface in Task 1 matches the `makepdf.sh %f` command line in Task 2; output-naming behavior asserted in Task 1 tests matches the manual checks in Task 2 Step 6.
