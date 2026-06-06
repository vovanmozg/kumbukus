# Shared assertions for tests/selftest/test_*.sh.
# Source me, run asserts, then `exit $FAILS`.
FAILS=0

assert_eq() {
  # assert_eq <expected> <actual> <msg>
  if [ "$1" = "$2" ]; then
    echo "  PASS: ${3:-}"
  else
    echo "  FAIL: ${3:-}"
    echo "    expected: [$1]"
    echo "    actual:   [$2]"
    FAILS=$((FAILS + 1))
  fi
}

assert_contains() {
  # assert_contains <needle> <haystack> <msg>
  case "$2" in
    *"$1"*) echo "  PASS: ${3:-}" ;;
    *) echo "  FAIL: ${3:-} (missing: [$1])"; FAILS=$((FAILS + 1)) ;;
  esac
}
