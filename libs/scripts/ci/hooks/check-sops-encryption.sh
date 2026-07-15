
















set -euo pipefail


source "$(dirname "${BASH_SOURCE[0]}")/lib/hook-common.sh"

HOOK_TITLE="SOPS encryption check"
SECRETS_DIR="$HOOK_REPO_ROOT/secrets"

if [[ ! -d "$SECRETS_DIR" ]]; then
    hook_skip "no secrets/ directory at $SECRETS_DIR"
    hook_exit
fi

if ! command -v sops >/dev/null 2>&1; then
    hook_fail "sops is not installed or not on PATH; cannot verify secrets/ with 'sops -d'"
    hook_exit
fi



has_sops_age_metadata() {
    local file="$1"


    if grep -q '"sops"[[:space:]]*:' "$file" 2>/dev/null &&
       grep -Eq '"recipient"[[:space:]]*:[[:space:]]*"age1' "$file" 2>/dev/null; then
        return 0
    fi


    awk '
        function indent_of(s) { match(s, /[^[:space:]]/); return RSTART - 1 }
        BEGIN { in_sops = 0; found = 0 }
        {
            if ($0 ~ /^[[:space:]]*$/) next
            if (!in_sops) {
                if ($0 ~ /^sops:[[:space:]]*$/) {
                    in_sops = 1
                    base = indent_of($0)
                }
                next
            }
            if (indent_of($0) <= base) {
                in_sops = 0
                next
            }
            if ($0 ~ /recipient["[:space:]]*[:=][[:space:]]*"?age1/) {
                found = 1
                exit
            }
        }
        END { exit(found ? 0 : 1) }
    ' "$file"
}

check_file() {
    local file="$1"
    local relative="${file#$HOOK_REPO_ROOT/}"
    local decrypted

    if ! has_sops_age_metadata "$file"; then
        hook_fail "unencrypted secret (no SOPS block with age recipients): $relative"
        return 0
    fi

    if ! decrypted=$(sops -d "$file" 2>/dev/null); then
        hook_fail "SOPS decryption failed for $relative (missing age key, wrong recipients, or corrupt metadata)"
        return 0
    fi

    if [[ -z "$decrypted" ]]; then
        hook_fail "SOPS decryption produced empty content for $relative"
        return 0
    fi

    if grep -qF 'ENC[AES256_GCM,' <<<"$decrypted"; then
        hook_fail "decrypted secret still contains SOPS ciphertext (ENC[AES256_GCM,) for $relative: file is double-encrypted or broken"
        return 0
    fi

    hook_ok "SOPS metadata, recipients and decryption verified: $relative"
}




while IFS= read -r -d '' file; do
    local_basename=$(basename "$file")
    case "$local_basename" in
        *.[mM][dD])
            hook_skip "documentation file: ${file#$HOOK_REPO_ROOT/}"
            continue
            ;;
    esac
    check_file "$file"
done < <(find "$SECRETS_DIR" -type f -print0)

if [[ $HOOK_ERRORS -gt 0 ]]; then
    echo ""
    echo "Fix: encrypt every non-documentation secrets/ file with your SOPS/age config"
    echo "     (sops -e -i <file>) and make the matching age key available."
    hook_exit
fi

echo "All non-documentation secrets/ files are SOPS-encrypted, decryptable and ciphertext-free."
hook_exit
