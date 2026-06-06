# parse_requirements <app_file>
# Prints vendor dependency names (one per line), in declaration order.
# Reads '# requirement: vendor/<dep> [ (note) ]' headers; keeps only <dep>.
parse_requirements() {
  grep -E '^# requirement:[[:space:]]*vendor/' "$1" \
    | sed -E 's|^# requirement:[[:space:]]*vendor/||' \
    | awk '{print $1}'
}
