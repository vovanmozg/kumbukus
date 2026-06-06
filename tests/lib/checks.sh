# check_command_for <vendor_file>
# Prints the presence-check command for a vendor dependency.
# Uses a '# check: <cmd>' directive in the file if present;
# otherwise defaults to 'command -v <basename-of-file>'.
check_command_for() {
  local f="$1" line
  line="$(grep -E '^# check:' "$f" 2>/dev/null | head -1 | sed -E 's|^# check:[[:space:]]*||')"
  if [ -n "$line" ]; then
    printf '%s\n' "$line"
  else
    printf 'command -v %s\n' "$(basename "$f")"
  fi
}
