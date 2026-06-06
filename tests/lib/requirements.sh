# parse_requirements <app_file>
# Prints vendor dependency names (one per line), in declaration order.
# Reads '# requirement: vendor/<dep> [ (note) ]' headers; keeps only <dep>.
parse_requirements() {
  local f="$1"
  [ -f "$f" ] || { echo "parse_requirements: file not found: $f" >&2; return 1; }
  grep -E '^# requirement:[[:space:]]*vendor/' "$f" \
    | sed -E 's|^# requirement:[[:space:]]*vendor/||' \
    | awk '{print $1}'
}
