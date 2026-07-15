









set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KEY_FILE="${1:-$SCRIPT_DIR/flatcar-buildbot.asc}"


KEY_FINGERPRINT="F88CFEDEFF29A5B4D9523864E25D9AED0593B34A"
KEY_KEYID="E25D9AED0593B34A"
KEY_URL="https://www.flatcar.org/security/image-signing-key/Flatcar_Image_Signing_Key.asc"

echo "=== Flatcar Buildbot GPG Key Bootstrap (one-time) ==="

check_fingerprint() {
    local file="$1"
    local actual
    actual=$(gpg --batch --show-keys --with-colons "$file" 2>/dev/null | awk -F: \
        -v kid="$KEY_KEYID" '
        $1 == "pub" { active = ($5 == kid) }
        $1 == "fpr" && active { print $10; active = 0 }
    ' | head -n 1) || actual=""
    [[ "$actual" == "$KEY_FINGERPRINT" ]]
}

if [[ -f "$KEY_FILE" ]]; then
    echo "Key already exists: $KEY_FILE"
    if check_fingerprint "$KEY_FILE"; then
        echo "Full fingerprint verified: $KEY_FINGERPRINT"
        exit 0
    fi
    echo "ERROR: Existing key does not match the pinned full fingerprint."
    echo "Refusing to overwrite automatically. Remove the file deliberately first."
    exit 1
fi

echo "Fetching key from: $KEY_URL"
if ! curl -fsSL --max-time 30 "$KEY_URL" -o "$KEY_FILE"; then
    echo "ERROR: Failed to fetch key from $KEY_URL"
    echo "Manual: curl -fsSL '$KEY_URL' -o $KEY_FILE"
    exit 1
fi

if [[ ! -s "$KEY_FILE" ]]; then
    echo "ERROR: Downloaded key file is empty"
    rm -f "$KEY_FILE"
    exit 1
fi

if ! check_fingerprint "$KEY_FILE"; then
    echo "ERROR: Full fingerprint mismatch after download."
    rm -f "$KEY_FILE"
    exit 1
fi

echo "Key verified and ready: $KEY_FILE"
echo "Full fingerprint: $KEY_FINGERPRINT"
echo "=== Key bootstrap complete ==="
