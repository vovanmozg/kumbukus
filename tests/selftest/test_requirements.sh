#!/bin/bash
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/assert.sh"
source "$here/../lib/requirements.sh"

tmp="$(mktemp)"
cat > "$tmp" <<'EOF'
#!/bin/bash
# requirement: vendor/curl
# requirement: vendor/exiftool
# requirement: vendor/poppler-utils (pdfunite)
# not a requirement line
echo hi
EOF

out="$(parse_requirements "$tmp")"
assert_eq $'curl\nexiftool\npoppler-utils' "$out" "parses deps in order, strips parenthetical"

rm -f "$tmp"
exit "$FAILS"
