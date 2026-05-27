#!/usr/bin/env bash
# Shared config and helpers for realm integration tests.
# Source this file; do not execute it directly.
# GNOHOME must be exported before sourcing.

# ── Chain config ──────────────────────────────────────────────────────────────
CHAIN_ID="${CHAIN_ID:-dev}"
NODE_ADDR="${NODE_ADDR:-http://localhost:26657}"
PKG_PATH="${PKG_PATH:-gno.land/r/berty/social}"
GAS_FEE="${GAS_FEE:-1000000ugnot}"
GAS_WANTED="${GAS_WANTED:-50000000}"
GNOKEY="${GNOKEY:-gnokey}"

# ── Funder key (fixed — must exist on the chain with enough GNOT) ─────────────
TEST1_NAME="test1"
TEST1_MNEMONIC="source bonus chronic canvas draft south burst lottery vacant surface solve popular case indicate oppose farm nothing bullet exhibit title speed wink action roast"
TEST1_ADDR="g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5"

# ── Per-run test users ────────────────────────────────────────────────────────
# Fresh keys are generated each run so names never collide on a persistent chain.
RUN_ID="${RUN_ID:-$(date +%s)}"
ALICE_NAME="alice${RUN_ID}"
BOB_NAME="bob${RUN_ID}"
# ALICE_ADDR and BOB_ADDR are set by test.sh after generate_key() calls.

# Keybase password (only protects the local keybase file — not a real secret).
KB_PASS="testpass"

# ── Key helpers ───────────────────────────────────────────────────────────────

# Import a fixed key from a mnemonic.
# Usage: import_key <name> <mnemonic>
import_key() {
    local name="$1" mnemonic="$2"
    printf "%s\n%s\n%s\n" "$mnemonic" "$KB_PASS" "$KB_PASS" \
        | "$GNOKEY" add \
            --home "$GNOHOME" \
            --insecure-password-stdin \
            --recover \
            "$name" 2>&1
}

# Generate a fresh random key and print its address on stdout.
# Usage: ADDR=$(generate_key <name>)
generate_key() {
    local name="$1"
    local out
    out=$(printf "%s\n%s\n" "$KB_PASS" "$KB_PASS" \
        | "$GNOKEY" add \
            --home "$GNOHOME" \
            --insecure-password-stdin \
            --nobackup \
            "$name" 2>&1)
    # Parse: "* name (local) - addr: g1xxx pub: ..."
    # Use || true so a grep non-match (no addr line) doesn't trigger set -e.
    echo "$out" | grep -oE 'addr: g1[a-z0-9]+' | awk '{print $2}' || true
}

# ── Register helper ───────────────────────────────────────────────────────────
# Register a (name, address) pair in r/sys/users via r/sys/users/init.
# On dev chains, r/sys/users/init is automatically whitelisted as a controller.
# Usage: register <name> <address>
register() {
    local name="$1" addr="$2"
    echo "$KB_PASS" \
        | "$GNOKEY" maketx call \
            --home      "$GNOHOME" \
            --pkgpath   "gno.land/r/sys/users/init" \
            --func      "RegisterUser" \
            --args      "$name" \
            --args      "$addr" \
            --gas-fee   "$GAS_FEE" \
            --gas-wanted "$GAS_WANTED" \
            --broadcast \
            --chainid   "$CHAIN_ID" \
            --remote    "$NODE_ADDR" \
            --insecure-password-stdin \
            "$TEST1_NAME"
}

# ── Balance helper ────────────────────────────────────────────────────────────
# Return the ugnot balance of an address (0 if account does not exist).
# Usage: balance_ugnot <address>
balance_ugnot() {
    local addr="$1"
    "$GNOKEY" query auth/accounts/"$addr" \
        --remote "$NODE_ADDR" 2>/dev/null \
        | grep -oE '"coins": "[0-9]+ugnot"' \
        | grep -oE '[0-9]+' \
        || echo 0
}

# ── Fund helper ───────────────────────────────────────────────────────────────
# Send GNOT from test1 to an address to activate it on-chain.
# Usage: fund <to-address> [amount]
fund() {
    local to="$1" amount="${2:-10000000ugnot}"
    echo "$KB_PASS" \
        | "$GNOKEY" maketx send \
            --home      "$GNOHOME" \
            --to        "$to" \
            --send      "$amount" \
            --gas-fee   "$GAS_FEE" \
            --gas-wanted "$GAS_WANTED" \
            --broadcast \
            --chainid   "$CHAIN_ID" \
            --remote    "$NODE_ADDR" \
            --insecure-password-stdin \
            "$TEST1_NAME"
}

# ── Transaction helper ────────────────────────────────────────────────────────
# Broadcast a call transaction.
# Usage: tx <FuncName> <key-name> [--args val ...]
tx() {
    local func="$1" key="$2"; shift 2
    echo "$KB_PASS" \
        | "$GNOKEY" maketx call \
            --home      "$GNOHOME" \
            --pkgpath   "$PKG_PATH" \
            --func      "$func" \
            --gas-fee   "$GAS_FEE" \
            --gas-wanted "$GAS_WANTED" \
            --broadcast \
            --chainid   "$CHAIN_ID" \
            --remote    "$NODE_ADDR" \
            --insecure-password-stdin \
            "$@" \
            "$key"
}

# ── Query helpers ─────────────────────────────────────────────────────────────
# vm/qeval — call a pure/view function.
# Usage: qeval "FuncName(\"arg\")"
qeval() {
    "$GNOKEY" query vm/qeval \
        --remote "$NODE_ADDR" \
        --data   "${PKG_PATH}.$1"
}

# vm/qrender — render a path.
# Usage: qrender "alice/home"
qrender() {
    "$GNOKEY" query vm/qrender \
        --remote "$NODE_ADDR" \
        --data   "${PKG_PATH}:$1"
}

# ── Parsing helper ────────────────────────────────────────────────────────────
# Extract the uint from a gnokey return value like "(3 gno.land/r/.../PostID)".
# Usage: parse_uint "$(tx ...)"
parse_uint() {
    echo "$1" | grep -oE '^\([0-9]+' | tr -d '('
}

# ── Assertion helpers ─────────────────────────────────────────────────────────
FAILURES=0

ok()   { echo "  [OK]   $*"; }
fail() { echo "  [FAIL] $*" >&2; FAILURES=$((FAILURES + 1)); }

assert_contains() {
    local label="$1" haystack="$2" needle="$3"
    if echo "$haystack" | grep -qF "$needle"; then
        ok "$label"
    else
        fail "$label — expected to find: $needle"
        echo "       output was: $haystack" >&2
    fi
}

assert_not_contains() {
    local label="$1" haystack="$2" needle="$3"
    if echo "$haystack" | grep -qF "$needle"; then
        fail "$label — expected NOT to find: $needle"
        echo "       output was: $haystack" >&2
    else
        ok "$label"
    fi
}
