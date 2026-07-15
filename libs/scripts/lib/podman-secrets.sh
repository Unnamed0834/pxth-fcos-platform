


















set -euo pipefail



_PXTH_SECRET_TMPFILE=""

_pxth_secret_cleanup() {
  if [[ -n "$_PXTH_SECRET_TMPFILE" ]]; then
    rm -f -- "$_PXTH_SECRET_TMPFILE"
    _PXTH_SECRET_TMPFILE=""
  fi
}
trap '_pxth_secret_cleanup' EXIT

_pxth_secret_mode() {
  local file="$1" mode=""
  if mode=$(stat -c '%a' -- "$file" 2>/dev/null); then
    printf '%s' "$mode"
    return 0
  fi
  if mode=$(stat -f '%Lp' -- "$file" 2>/dev/null); then
    printf '%s' "$mode"
    return 0
  fi
  return 1
}

create() {
  local secret_name="${1:-}"
  local file_basename="${2:-}"

  if [[ -z "$secret_name" || -z "$file_basename" ]]; then
    echo "ERROR: create() requires <secret_name> <secret_file_basename>" >&2
    return 1
  fi

  if [[ ! "$secret_name" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
    echo "ERROR: invalid secret name: $secret_name" >&2
    return 1
  fi
  if [[ ! "$file_basename" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
    echo "ERROR: invalid secret file basename: $file_basename" >&2
    return 1
  fi

  local secrets_dir="${PODMAN_SECRETS_DIR:-/var/oem/scripts/secrets}"
  local secret_file="$secrets_dir/$file_basename.env"
  if [[ ! -f "$secret_file" || ! -r "$secret_file" ]]; then
    echo "ERROR: secret file is missing or unreadable: $secret_file" >&2
    return 1
  fi



  local old_umask
  old_umask=$(umask)
  umask 077
  if ! _PXTH_SECRET_TMPFILE=$(mktemp "${TMPDIR:-/tmp}/pxth-secret.XXXXXXXX"); then
    umask "$old_umask"
    echo "ERROR: could not create a private temp file" >&2
    return 1
  fi
  umask "$old_umask"

  local mode
  if ! mode=$(_pxth_secret_mode "$_PXTH_SECRET_TMPFILE") || [[ "$mode" != "600" ]]; then
    echo "ERROR: temp file $_PXTH_SECRET_TMPFILE has mode ${mode:-unknown}, expected 600" >&2
    _pxth_secret_cleanup
    return 1
  fi

  local secret_value
  if ! secret_value=$(cut -d= -f2- -- "$secret_file"); then
    echo "ERROR: could not read secret value from $secret_file" >&2
    _pxth_secret_cleanup
    return 1
  fi
  printf '%s' "$secret_value" > "$_PXTH_SECRET_TMPFILE"


  if ! mode=$(_pxth_secret_mode "$_PXTH_SECRET_TMPFILE") || [[ "$mode" != "600" ]]; then
    echo "ERROR: temp file mode changed to ${mode:-unknown} after write, expected 600" >&2
    _pxth_secret_cleanup
    return 1
  fi


  local -a command=()

  local sudo_bin="${PODMAN_SUDO-sudo}"
  if [[ -n "$sudo_bin" ]]; then
    command+=("$sudo_bin" -u "${PODMAN_CONTAINERS_USER:-containers}")
  fi
  command+=("${PODMAN_BIN:-/usr/bin/podman}" secret create --replace "$secret_name" "$_PXTH_SECRET_TMPFILE")

  local rc=0
  "${command[@]}" || rc=$?
  _pxth_secret_cleanup

  if [[ $rc -ne 0 ]]; then
    echo "ERROR: podman secret create failed for $secret_name (exit $rc)" >&2
    return "$rc"
  fi
  return 0
}
