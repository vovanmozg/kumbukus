# Context-aware PDF submenu in Nautilus

## Problem

The Nautilus right-click `PDF` submenu (provided by **actions-for-nautilus**) currently
shows all of its items — `Make PDF`, `PDF compress`, `PDF ultra compress`, `Merge PDFs` —
regardless of what was clicked, because the items carry almost no `mimetypes`/`filetypes`
filters. Items appear where they make no sense (e.g. `PDF compress` on a folder,
`Merge PDFs` on an image).

We want the submenu contents to depend on what the user right-clicks:

- **Image** → `PDF ▸ Make PDF` only — creates a PDF next to the image.
- **Folder** → `PDF ▸ Make PDF + Merge PDFs` — `Make PDF` keeps its current folder behavior.
- **PDF file** → `PDF ▸ PDF compress + PDF ultra compress`.

## Relevant findings about actions-for-nautilus

(extension source: `/usr/share/nautilus-python/extensions/actions-for-nautilus/`)

- Each action may carry `mimetypes` and `filetypes` filter lists. A parent `menu` is shown
  when at least one child action is applicable.
- `mimetypes` supports the `image/*` wildcard (matched via `startswith`) and `!`-negation.
- `filetypes` values are matched exactly (`file`, `directory`, …).
- An action is applicable only when **every** selected file matches its filters
  (`all(...)` over the selection).
- `%f` has **SINGULAR** behavior: the command runs **once per selected file**
  (`count = len(files)`). So `image2pdf.sh %f` with N images selected runs N times,
  producing one PDF per image — no loop needed in the config.

## Source of truth

The change lives in the **`~/pro/kumbukus`** repo (not `kumbukus-personal`):

- Config: `~/pro/kumbukus/config/.local/share/actions-for-nautilus/config.json`
  (verified byte-identical to the live `~/.local/share/actions-for-nautilus/config.json`).
- Scripts: `~/pro/kumbukus/apps/` → installed to `~/bin`.

## Design

### 1. Extend `apps/makepdf.sh` to accept a file *or* a directory

Rather than add a second script, `makepdf.sh` gains a single image-file mode. The existing
folder mode (glob `*.jpg`/`*.png`, combine into one PDF) is unchanged; a new branch handles
the case where the argument is a single image file. The duplication concern is resolved by
keeping the `convert` call and the unique-name logic as one shared tail; the branch only
decides the **input list** and the **output base name**.

- **Argument is a directory** (current behavior): collect `*.jpg`/`*.png` (maxdepth 1,
  sorted), output `<dir>.pdf` next to the folder.
- **Argument is a single image file** (new): input list is just that file, output
  `<name>.pdf` next to it — `photo.jpg` → `photo.pdf`.
- **Non-overwriting (both modes):** if the target exists, write `<base>-1.pdf`, then
  `<base>-2.pdf`, … Folder mode thus stops silently overwriting too — a deliberate,
  consistent improvement (the user already requested non-overwrite for the file case).
- Empty folder / no images: report and exit cleanly, as today.
- Keeps the family conventions: `#!/bin/bash`, the `# requirement: vendor/imagemagick`
  comment, an arg-count guard, and a "directory-or-file" guard with a usage message.

Sketch:

```bash
#!/bin/bash
# requirement: vendor/imagemagick
set -euo pipefail
[ "$#" -eq 1 ] || { echo "Usage: $0 <image-file-or-directory>"; exit 1; }
arg="$1"

if [ -d "$arg" ]; then
    readarray -t imgs < <(find "$arg" -maxdepth 1 -type f \( -iname '*.jpg' -o -iname '*.png' \) | sort)
    [ ${#imgs[@]} -gt 0 ] || { echo "No images found in $arg"; exit 0; }
    out_dir=$(dirname "$arg"); out_name=$(basename "$arg")
elif [ -f "$arg" ]; then
    imgs=("$arg")
    out_dir=$(dirname "$arg"); out_name=$(basename "${arg%.*}")
else
    echo "Not a file or directory: $arg"; exit 1
fi

# shared tail: pick an unused name, then convert
out="$out_dir/$out_name.pdf"
i=1; while [ -e "$out" ]; do out="$out_dir/$out_name-$i.pdf"; i=$((i+1)); done
convert "${imgs[@]}" "$out"
```

### 2. Restructure the `PDF` menu in `config.json`

Replace the current `PDF` menu's `actions` array with filtered entries. Because one
`makepdf.sh` now handles both an image file and a folder, the two `Make PDF` cases collapse
into a **single** menu entry whose filters match either:

| Label | `command_line` | Filters |
|---|---|---|
| `Make PDF` | `makepdf.sh %f` | `mimetypes:["image/*","inode/directory"]`, `filetypes:["file","directory"]` |
| `PDF compress` | `compresspdf.sh %f` | `mimetypes:["application/pdf"]` |
| `PDF ultra compress` | `compresspdf.sh %f --width=1000` | `mimetypes:["application/pdf"]` |
| `Merge PDFs` | `mergepdf.sh %f` | `filetypes:["directory"]` (unchanged) |

Why the combined `Make PDF` filters do the right thing (recall: an action shows only when
**every** selected item matches):

- An image: `filetype=file` ✓ and `mimetype` starts with `image/` ✓ → shows.
- A folder: `filetype=directory` ✓ and `mimetype=inode/directory` ✓ → shows.
- A PDF file: `filetype=file` ✓ but `mimetype=application/pdf` ∉ filters ✗ → hidden.
- Any other file (`.txt`, …): mimetype not in filters ✗ → hidden.

`%f` is per-file, so selecting several images runs `makepdf.sh` once per image → one PDF each.

Also remove the stray leading spaces in the current `" compresspdf.sh %f"` command lines.

Resulting behavior:

- **Image** → `PDF ▸ Make PDF` only. Multi-select images → one PDF each. ✓
- **Folder** → `PDF ▸ Make PDF + Merge PDFs` (folder `Make PDF` = current behavior,
  now non-overwriting). ✓
- **PDF** → `PDF ▸ PDF compress + PDF ultra compress`. ✓

### 3. Install & apply

**`config.json` always follows this three-step flow** (the live file is the source of
record for any out-of-repo manual edits, so we must reconcile before editing):

1. **Sync repo from live.** Diff the repo's
   `config/.local/share/actions-for-nautilus/config.json` against the live
   `~/.local/share/actions-for-nautilus/config.json`. If they differ, the live file has
   newer manual edits — bring them into the repo first so our changes build on the true
   current state. (Verified byte-identical at spec time, so this step is currently a no-op,
   but it must be re-checked at implementation time.)
2. **Edit in the repo.** Make the `PDF`-menu changes in the repo copy and commit them.
3. **Copy back to live.** Copy the repo `config.json` to
   `~/.local/share/actions-for-nautilus/config.json` — reuse the existing
   `~/pro/kumbukus-personal/apps/install_nautilus_actions` installer if it covers this,
   otherwise copy directly.

Around that flow:

- Install `makepdf.sh` (and any other touched `apps/*.sh`) to `~/bin` via the same
  mechanism as the other `apps/*.sh`.
- Reload Nautilus: `nautilus -q` (it relaunches on next folder open).

## Out of scope (YAGNI)

- Combining multiple selected images into one multi-page PDF.
- Page-ordering UI / reordering.
- Special handling for exotic image formats beyond what ImageMagick `convert` does by default.

## Verification

- Right-click a `.jpg` → `PDF` shows only `Make PDF`; running it creates `photo.pdf`
  (and `photo-1.pdf` on a second run) next to the image.
- Select two images → `Make PDF` produces two PDFs.
- Right-click a folder of images → `PDF` shows `Make PDF` + `Merge PDFs`;
  `Make PDF` still produces `<folder>.pdf` next to the folder (unchanged).
- Right-click a `.pdf` → `PDF` shows `PDF compress` + `PDF ultra compress`; neither
  `Make PDF` nor `Merge PDFs` appears.
