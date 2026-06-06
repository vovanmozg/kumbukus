#!/bin/bash
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/assert.sh"
source "$here/../lib/checks.sh"

# explicit '# check:' directive wins
ex="$(mktemp)"
printf '# check: command -v identify\nsudo apt install imagemagick -y\n' > "$ex"
assert_eq "command -v identify" "$(check_command_for "$ex")" "explicit # check directive is used"
rm -f "$ex"

# default = command -v <basename> when no directive
d="$(mktemp -d)"
printf 'sudo apt install pngquant -y\n' > "$d/pngquant"
assert_eq "command -v pngquant" "$(check_command_for "$d/pngquant")" "default uses vendor file basename"
rm -rf "$d"

exit "$FAILS"
