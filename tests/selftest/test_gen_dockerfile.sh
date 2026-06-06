#!/bin/bash
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/assert.sh"
source "$here/../lib/requirements.sh"
source "$here/../lib/checks.sh"
source "$here/../lib/gen-dockerfile.sh"

# gen_dockerfile is a pure text generator; no real recipe/driver files are needed.

# build a fake mini-repo with one app + one vendor recipe
d="$(mktemp -d)"
mkdir -p "$d/apps" "$d/vendor" "$d/tests/lib"
printf '#!/bin/bash\n# requirement: vendor/curl\n' > "$d/apps/foo.sh"
printf 'sudo apt install curl -y\n' > "$d/vendor/curl"

out="$(gen_dockerfile foo.sh "$d")"

assert_contains "FROM kumbukus-test-base" "$out" "starts from base image"
assert_contains "COPY vendor/curl /recipes/curl" "$out" "copies the recipe"
assert_contains "RUN cd /tmp && bash -e /recipes/curl && command -v curl" "$out" "runs recipe + inlined check"
assert_contains "COPY tests/lib/run-installapps.sh /tmp/run-installapps.sh" "$out" "copies installapps driver"
assert_contains "COPY . /repo" "$out" "copies repo for installapps"
assert_contains "RUN bash /tmp/run-installapps.sh /repo foo.sh && test -x /root/bin/foo.sh" "$out" "drives installapps + asserts install"

rm -rf "$d"

# Negative-path: a requirement whose vendor file is ABSENT still produces the
# COPY and RUN lines (missing recipe => Docker build fails at COPY, as intended).
d2="$(mktemp -d)"
mkdir -p "$d2/apps" "$d2/vendor" "$d2/tests/lib"
printf '#!/bin/bash\n# requirement: vendor/ghost\n' > "$d2/apps/bar.sh"
# intentionally do NOT create "$d2/vendor/ghost"

out2="$(gen_dockerfile bar.sh "$d2")"

assert_contains "COPY vendor/ghost /recipes/ghost" "$out2" "absent vendor file still emits COPY (build will fail at COPY, as intended)"
assert_contains "RUN cd /tmp && bash -e /recipes/ghost && command -v ghost" "$out2" "absent vendor file falls back to default check"

rm -rf "$d2"
exit "$FAILS"
