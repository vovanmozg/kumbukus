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

### 1. New script `apps/image2pdf.sh`

The existing `makepdf.sh` only accepts a **directory** (globs `*.jpg`/`*.png` inside it),
so making a PDF from a single image file is genuinely new.

- Input: a single image file path (`%f`).
- Output: `<name>.pdf` next to the source — `photo.jpg` → `photo.pdf`.
- **Non-overwriting:** if `photo.pdf` exists, write `photo-1.pdf`, then `photo-2.pdf`, …
- Convert via ImageMagick: `convert "$src" "$out"`.
- Follows the family conventions: `#!/bin/bash`, a `# requirement: vendor/imagemagick`
  comment (as in `makepdf.sh`), arg-count guard, and an "is a file / readable" guard.

Sketch:

```bash
#!/bin/bash
# requirement: vendor/imagemagick
set -euo pipefail
[ "$#" -eq 1 ] || { echo "Usage: $0 <image-file>"; exit 1; }
src="$1"
[ -f "$src" ] || { echo "Not a file: $src"; exit 1; }
dir=$(dirname "$src")
base=$(basename "$src")
name="${base%.*}"
out="$dir/$name.pdf"
i=1
while [ -e "$out" ]; do out="$dir/$name-$i.pdf"; i=$((i+1)); done
convert "$src" "$out"
```

### 2. Restructure the `PDF` menu in `config.json`

Replace the current `PDF` menu's `actions` array with filtered entries:

| Label | `command_line` | Filters |
|---|---|---|
| `Make PDF` | `image2pdf.sh %f` | `mimetypes:["image/*"]`, `filetypes:["file"]` |
| `Make PDF` | `makepdf.sh %f` | `filetypes:["directory"]` |
| `PDF compress` | `compresspdf.sh %f` | `mimetypes:["application/pdf"]` |
| `PDF ultra compress` | `compresspdf.sh %f --width=1000` | `mimetypes:["application/pdf"]` |
| `Merge PDFs` | `mergepdf.sh %f` | `filetypes:["directory"]` (unchanged) |

Two entries deliberately share the label `Make PDF`; their filters are mutually exclusive
(`image/* file` vs `directory`), so exactly one is ever applicable and the user sees a
single context-appropriate `Make PDF`.

Also remove the stray leading spaces in the current `" compresspdf.sh %f"` command lines.

Resulting behavior:

- **Image** → `PDF ▸ Make PDF` only. Multi-select images → one PDF each. ✓
- **Folder** → `PDF ▸ Make PDF + Merge PDFs` (folder `Make PDF` = current behavior). ✓
- **PDF** → `PDF ▸ PDF compress + PDF ultra compress`. ✓

### 3. Install & apply

1. Install `image2pdf.sh` to `~/bin` (same mechanism as the other `apps/*.sh`).
2. Copy the updated `config.json` to the live
   `~/.local/share/actions-for-nautilus/config.json` — reuse the existing
   `~/pro/kumbukus-personal/apps/install_nautilus_actions` installer if it covers this,
   otherwise copy directly.
3. Reload Nautilus: `nautilus -q` (it relaunches on next folder open).

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
