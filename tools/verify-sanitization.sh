set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

fail=0
hits=0

# An optional third argument is an allow-pattern: matches of it are filtered
# out of the result so known-good placeholders do not trip a check.
check() {
  local name="$1" pattern="$2" ignore="${3:-}"
  local out
  out="$(grep -rInE \
      --exclude-dir=.git \
      --exclude='verify-sanitization.sh' \
      --exclude='.gitleaks.toml' \
      --exclude-dir='tests' \
      "$pattern" . 2>/dev/null || true)"
  if [[ -n "$ignore" ]]; then
    out="$(printf '%s\n' "$out" | grep -vE "$ignore" || true)"
  fi
  if [[ -n "$out" ]]; then
    printf 'FAIL  %-34s\n' "$name"
    printf '%s\n' "$out" | head -20 | sed 's/^/        /'
    fail=1
    hits=$(( hits + 1 ))
  else
    printf 'PASS  %s\n' "$name"
  fi
}

echo "== Sanitization verification =="
echo "root: $ROOT"
echo

check "age/private key material" \
  'BEGIN (RSA |EC |DSA |OPENSSH |OPENPGP )?PRIVATE KEY|AGE-SECRET-KEY-1[1-9A-Za-z]{20,}'
check "internal domain sentinels" \
  '[A-Za-z0-9-]+\.(int\.)?internal\.example'
check "private 10.x addresses" \
  '(^|[^0-9])10\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}([^0-9]|$)'
check "real ZeroTier network id" \
  '[Zz]ero[Tt]ier.*(^|[^0-9a-fA-F])[0-9a-fA-F]{16}([^0-9a-fA-F]|$)' \
  '0000000000000000'
check "operator email sentinels" \
  '[A-Za-z0-9._%+-]+@internal\.example'
check "operator path sentinels" \
  '(/home/operator\b|\.\./key\.txt)' \
  '/home/operator'
check "cloud/hosting tokens" \
  '(AKIA[0-9A-Z]{16}|gh[pousr]_[A-Za-z0-9]{20,}|sk-[A-Za-z0-9]{24,})'

echo
echo "== Structural checks =="

if find . -mindepth 2 -name .git -type d -print -quit | grep -q .; then
  echo "FAIL  nested git repositories"
  find . -mindepth 2 -name .git -type d -print
  fail=1
  hits=$(( hits + 1 ))
else
  echo "PASS  no nested git repositories"
fi

secret_files=$(find apps -type f \( -name '*.yml' -o -name '*.yaml' -o -name '.sops.yaml' \) \
  -path '*/secrets/*' 2>/dev/null | wc -l | tr -d ' ')
if [[ "$secret_files" != "0" ]]; then
  echo "FAIL  unexpected secret payload files under apps/*/secrets/ ($secret_files)"
  fail=1
  hits=$(( hits + 1 ))
else
  echo "PASS  no secret payload files under apps/*/secrets/"
fi

if [[ -f LICENSE ]]; then
  echo "PASS  governance files present"
else
  echo "FAIL  governance files missing"
  fail=1
  hits=$(( hits + 1 ))
fi

echo
if [[ "$fail" -ne 0 ]]; then
  echo "RESULT: FAILED — $hits check(s) need attention"
  exit 1
fi
echo "RESULT: PASS — no real credentials or identifiers detected"
