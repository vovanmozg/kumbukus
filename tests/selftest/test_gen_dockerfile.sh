#!/bin/bash
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/assert.sh"
source "$here/../lib/requirements.sh"
source "$here/../lib/checks.sh"
source "$here/../lib/gen-dockerfile.sh"

# build a fake mini-repo with one app + one vendor recipe
d="$(mktemp -d)"
mkdir -p "$d/apps" "$d/vendor" "$d/tests/lib"
printf '#!/bin/bash\n# requirement: vendor/curl\n' > "$d/apps/foo.sh"
printf 'sudo apt install curl -y\n' > "$d/vendor/curl"
: > "$d/tests/lib/run-installapps.sh"

out="$(gen_dockerfile foo.sh "$d")"

assert_contains "FROM kumbukus-test-base" "$out" "starts from base image"
assert_contains "COPY vendor/curl /recipes/curl" "$out" "copies the recipe"
assert_contains "RUN cd /tmp && bash -e /recipes/curl && command -v curl" "$out" "runs recipe + inlined check"
assert_contains "COPY tests/lib/run-installapps.sh /tmp/run-installapps.sh" "$out" "copies installapps driver"
assert_contains "COPY . /repo" "$out" "copies repo for installapps"
assert_contains "RUN bash /tmp/run-installapps.sh /repo foo.sh && test -x /root/bin/foo.sh" "$out" "drives installapps + asserts install"

rm -rf "$d"
exit "$FAILS"
