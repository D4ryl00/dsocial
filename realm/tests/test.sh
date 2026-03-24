#!/usr/bin/env bash
# Integration tests for gno.land/r/berty/social.
#
# Usage:
#   ./test.sh
#   CHAIN_ID=dev NODE_ADDR=http://localhost:26657 ./test.sh
#
# Each run generates fresh alice/bob keys with unique names so it is safe to
# run multiple times against a persistent chain without name collisions.

set -euo pipefail
cd "$(dirname "$0")"

# Isolated keybase in a tmp directory; cleaned up on exit.
GNOHOME=$(mktemp -d)
export GNOHOME
trap 'rm -rf "$GNOHOME"' EXIT

source env.sh

echo "=== dSocial realm tests ==="
echo "    chain:  $CHAIN_ID @ $NODE_ADDR"
echo "    run id: $RUN_ID"
echo "    home:   $GNOHOME"
echo ""

# ── Setup: import funder key ──────────────────────────────────────────────────
echo "--- Setup: importing keys ---"

import_key "$TEST1_NAME" "$TEST1_MNEMONIC" > /dev/null
ok "test1 imported  ($TEST1_ADDR)"

ALICE_ADDR=$(generate_key "$ALICE_NAME")
[ -n "$ALICE_ADDR" ] && ok "alice generated ($ALICE_ADDR) as $ALICE_NAME" \
                     || { echo "[FAIL] could not generate alice key" >&2; exit 1; }

BOB_ADDR=$(generate_key "$BOB_NAME")
[ -n "$BOB_ADDR" ]   && ok "bob generated   ($BOB_ADDR) as $BOB_NAME" \
                     || { echo "[FAIL] could not generate bob key" >&2; exit 1; }

echo ""

# ── Setup: fund accounts ──────────────────────────────────────────────────────
# Minimum balance required to cover gas for all transactions in the suite.
MIN_BALANCE=5000000   # 5 GNOT in ugnot

echo "--- Setup: funding accounts ---"

BAL=$(balance_ugnot "$ALICE_ADDR")
if [ "${BAL:-0}" -lt "$MIN_BALANCE" ]; then
    OUT=$(fund "$ALICE_ADDR")
    assert_contains "alice funded" "$OUT" "OK"
else
    ok "alice already has sufficient funds (${BAL}ugnot)"
fi

BAL=$(balance_ugnot "$BOB_ADDR")
if [ "${BAL:-0}" -lt "$MIN_BALANCE" ]; then
    OUT=$(fund "$BOB_ADDR")
    assert_contains "bob funded" "$OUT" "OK"
else
    ok "bob already has sufficient funds (${BAL}ugnot)"
fi

echo ""

# ── 1. PostMessage ────────────────────────────────────────────────────────────
echo "--- 1. PostMessage ---"

OUT=$(tx PostMessage "$ALICE_NAME" --args "Hello from the test suite!")
echo "$OUT"
assert_contains "PostMessage succeeds" "$OUT" "OK"
THREAD_ID=$(parse_uint "$OUT")
[ -n "$THREAD_ID" ] && ok "thread id = $THREAD_ID" || fail "could not parse thread id"

echo ""

# ── 2. Render user page ───────────────────────────────────────────────────────
echo "--- 2. Render user page ---"

OUT=$(qrender "$ALICE_ADDR")
echo "$OUT"
assert_contains "post visible in render" "$OUT" "Hello from the test suite"

echo ""


# ── 4. GetJsonUserPostsInfo ───────────────────────────────────────────────────
echo "--- 4. GetJsonUserPostsInfo ---"

OUT=$(qeval "GetJsonUserPostsInfo(address(\"$ALICE_ADDR\"))")
echo "$OUT"
assert_contains "returns n_threads" "$OUT" 'n_threads'

echo ""

# ── 5. PostReply ──────────────────────────────────────────────────────────────
echo "--- 5. PostReply ---"

OUT=$(tx PostReply "$BOB_NAME" \
    --args "$ALICE_ADDR" \
    --args "$THREAD_ID" \
    --args "$THREAD_ID" \
    --args "Nice post!")
echo "$OUT"
assert_contains "PostReply succeeds" "$OUT" "OK"
REPLY_ID=$(parse_uint "$OUT")
[ -n "$REPLY_ID" ] && ok "reply id = $REPLY_ID" || fail "could not parse reply id"

echo ""

# ── 6. AddReaction ────────────────────────────────────────────────────────────
echo "--- 6. AddReaction (gnod) ---"

OUT=$(tx AddReaction "$BOB_NAME" \
    --args "$ALICE_ADDR" \
    --args "$THREAD_ID" \
    --args "$THREAD_ID" \
    --args "0")
echo "$OUT"
assert_contains "AddReaction succeeds" "$OUT" "OK"

echo ""

# ── 7. Follow ─────────────────────────────────────────────────────────────────
echo "--- 7. Follow ---"

OUT=$(tx Follow "$BOB_NAME" --args "$ALICE_ADDR")
echo "$OUT"
assert_contains "Follow succeeds" "$OUT" "OK"

OUT=$(qeval "GetJsonFollowers(address(\"$ALICE_ADDR\"), 0, 10)")
echo "$OUT"
assert_contains "bob in alice's followers" "$OUT" "$BOB_ADDR"

echo ""

# ── 8. RefreshHomePosts ───────────────────────────────────────────────────────
# refreshHomePosts only picks up posts made AFTER the follow, so alice posts
# a second message here before bob refreshes.
echo "--- 8. RefreshHomePosts ---"

OUT=$(tx PostMessage "$ALICE_NAME" --args "Second post after follow!")
echo "$OUT"
assert_contains "alice second post succeeds" "$OUT" "OK"

OUT=$(tx RefreshHomePosts "$BOB_NAME" --args "$BOB_ADDR")
echo "$OUT"
assert_contains "RefreshHomePosts succeeds" "$OUT" "OK"

OUT=$(qeval "GetJsonHomePosts(address(\"$BOB_ADDR\"), 0, 5)")
echo "$OUT"
assert_contains "alice's post in bob's home feed" "$OUT" "Second post after follow"

echo ""

# ── 9. Unfollow ───────────────────────────────────────────────────────────────
echo "--- 9. Unfollow ---"

OUT=$(tx Unfollow "$BOB_NAME" --args "$ALICE_ADDR")
echo "$OUT"
assert_contains "Unfollow succeeds" "$OUT" "OK"

OUT=$(qeval "GetJsonFollowers(address(\"$ALICE_ADDR\"), 0, 10)")
echo "$OUT"
assert_not_contains "bob no longer in alice's followers" "$OUT" "$BOB_ADDR"

echo ""

# ── 10. ListJsonUsersByPrefix ─────────────────────────────────────────────────
echo "--- 10. ListJsonUsersByPrefix ---"

OUT=$(qeval "ListJsonUsersByPrefix(\"\", 20)")
echo "$OUT"
assert_contains "returns a JSON list"       "$OUT" "["
assert_contains "alice appears in results"  "$OUT" "$ALICE_ADDR"

echo ""

# ── Result ────────────────────────────────────────────────────────────────────
if [ "$FAILURES" -eq 0 ]; then
    echo "=== All tests passed ==="
else
    echo "=== $FAILURES test(s) FAILED ===" >&2
    exit 1
fi
