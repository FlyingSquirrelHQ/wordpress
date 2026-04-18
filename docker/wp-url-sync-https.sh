#!/usr/bin/env bash
# If the DB still has http:// while WP_SITE_URL is https://, WordPress canonical redirects
# loop behind Traefik. Sync idempotently when siteurl is still http.

set -euo pipefail
cd /var/www/html

WPC=(wp --allow-root)

if ! "${WPC[@]}" core is-installed 2>/dev/null; then
	exit 0
fi

want="${WP_SITE_URL:-${WORDPRESS_SITE_URL:-}}"
if [[ -z "${want}" ]] || [[ "${want}" != https://* ]]; then
	exit 0
fi

if [[ "${WP_SYNC_HTTPS_SITEURL:-true}" != "true" ]] && [[ "${WP_SYNC_HTTPS_SITEURL:-}" != "1" ]]; then
	exit 0
fi

want="${want%/}"
cur="$("${WPC[@]}" option get siteurl 2>/dev/null || true)"
cur="${cur%/}"

if [[ -z "${cur}" ]] || [[ "${cur}" == "${want}" ]]; then
	exit 0
fi

if [[ "${cur}" != http://* ]]; then
	exit 0
fi

echo >&2 "wp-url-sync-https: siteurl in DB is '${cur}'; updating options + search-replace to '${want}'."

# Primary site options (explicit URL so multisite CLI targets blog 1).
"${WPC[@]}" option update home "${want}" --url="${want}" 2>/dev/null || "${WPC[@]}" option update home "${want}" || true
"${WPC[@]}" option update siteurl "${want}" --url="${want}" 2>/dev/null || "${WPC[@]}" option update siteurl "${want}" || true

args=(--all-tables --precise --skip-columns=guid)
if "${WPC[@]}" core is-installed --network 2>/dev/null; then
	args+=(--network)
fi

"${WPC[@]}" search-replace "${cur}" "${want}" "${args[@]}" || {
	echo >&2 "wp-url-sync-https: search-replace failed (non-fatal)."
}
