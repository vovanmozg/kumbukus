# gen_dockerfile <app_name> <repo_root>
# Prints a per-app Dockerfile to stdout. One COPY+RUN layer per vendor recipe
# (presence-check inlined into RUN), then a final layer that runs installapps.
# Requires parse_requirements (requirements.sh) and check_command_for (checks.sh)
# to be sourced first.
gen_dockerfile() {
  local app="$1" repo="${2:-.}" dep vfile check
  printf 'FROM kumbukus-test-base\n\n'
  while IFS= read -r dep; do
    [ -z "$dep" ] && continue
    vfile="$repo/vendor/$dep"
    check="$(check_command_for "$vfile")"
    printf 'COPY vendor/%s /recipes/%s\n' "$dep" "$dep"
    printf 'RUN cd /tmp && bash -e /recipes/%s && %s\n\n' "$dep" "$check"
  done < <(parse_requirements "$repo/apps/$app")
  printf 'COPY tests/lib/run-installapps.sh /tmp/run-installapps.sh\n'
  printf 'COPY . /repo\n'
  printf 'RUN bash /tmp/run-installapps.sh /repo %s && test -x /root/bin/%s\n' "$app" "$app"
}
