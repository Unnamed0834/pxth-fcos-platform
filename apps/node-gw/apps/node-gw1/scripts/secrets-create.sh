











set -euo pipefail

umask 077
mkdir -p /run/secrets
chmod 0700 /run/secrets



required=(
  s3_backup_endpoint
  s3_backup_bucket
  s3_backup_access_key_id
  s3_backup_secret_access_key
  s3_backup_restic_password
)
for name in "${required[@]}"; do
  f="/run/secrets/${name}.env"
  [[ -r "$f" ]] || { echo "FATAL: missing out-of-band secret $f" >&2; exit 1; }
done

read_env() { cut -d= -f2- "/run/secrets/$1.env"; }

S3_ENDPOINT=$(read_env s3_backup_endpoint)
S3_BUCKET=$(read_env s3_backup_bucket)
S3_ACCESS_KEY=$(read_env s3_backup_access_key_id)
S3_SECRET_KEY=$(read_env s3_backup_secret_access_key)
S3_RESTORE_PASSWORD=$(read_env s3_backup_restic_password)


tmpfile=$(mktemp /run/secrets/.restic.env.XXXXXXXX)
trap 'rm -f "$tmpfile"' EXIT
cat > "$tmpfile" <<EOF
AWS_ACCESS_KEY_ID=${S3_ACCESS_KEY}
AWS_SECRET_ACCESS_KEY=${S3_SECRET_KEY}
RESTIC_REPOSITORY=s3://${S3_ENDPOINT}/${S3_BUCKET}/restic-node-gw1
RESTIC_PASSWORD=${S3_RESTORE_PASSWORD}
EOF
chmod 0600 "$tmpfile"
chown root:root "$tmpfile"
mv -f "$tmpfile" /run/secrets/restic.env
trap - EXIT

echo "Restic S3 credentials written to /run/secrets/restic.env"
