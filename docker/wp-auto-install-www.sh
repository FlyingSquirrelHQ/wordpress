#!/usr/bin/env bash
# Runs as root with `wp --allow-root` so WORDPRESS_DB_* from the container env is
# always visible (runuser/gosu can drop or alter env on some setups).

set -euo pipefail
cd /var/www/html

WPC=(wp --allow-root)

if "${WPC[@]}" core is-installed 2>/dev/null; then
	echo >&2 "wp-auto-install: database already has a WordPress install; skipping wp core install (no change to site title or users). To reinstall, remove the DB volume or run wp db clean from a shell."
	exit 0
fi

# Wait for MySQL/MariaDB. Do not use `wp db check` here: it shells out to `mysqlcheck`,
# which is not installed in the official WordPress image (false "unreachable" errors).
wp_db_ping() {
	"${WPC[@]}" db query 'SELECT 1' >/dev/null 2>&1
}

# DB can lag healthcheck slightly on first boot.
for _ in $(seq 1 30); do
	if wp_db_ping; then
		break
	fi
	sleep 2
done

if ! wp_db_ping; then
	echo >&2 "wp-auto-install: database not reachable after retries. Last error from wp db query:"
	"${WPC[@]}" db query 'SELECT 1' >&2 || true
	exit 1
fi

# Use --locale=xx_YY (one token). `--locale xx_YY` is parsed as a stray positional "xx_YY"
# and fails with "Too many positional arguments" on current WP-CLI/Symfony.
declare -a locale_args=()
if [ -n "${WP_INSTALL_LOCALE:-}" ]; then
	locale_args+=(--locale="${WP_INSTALL_LOCALE}")
fi

site_url="${WP_SITE_URL:-https://${APP_NAME:-wordpress}.localhost.direct}"
echo >&2 "wp-auto-install: running wp core install --url=${site_url} --title=${WP_SITE_TITLE:-WordPress} --admin_user=${WP_ADMIN_USER:-admin}"

set +e
"${WPC[@]}" core install \
	--url="${site_url}" \
	--title="${WP_SITE_TITLE:-WordPress}" \
	--admin_user="${WP_ADMIN_USER:-admin}" \
	--admin_password="${WP_ADMIN_PASSWORD}" \
	--admin_email="${WP_ADMIN_EMAIL}" \
	--skip-email \
	"${locale_args[@]}"
install_status=$?
set -e

if [ "${install_status}" -ne 0 ]; then
	if "${WPC[@]}" core is-installed 2>/dev/null; then
		echo >&2 "wp-auto-install: wp core install exited ${install_status} but the site is already installed; treating as success."
	else
		echo >&2 "wp-auto-install: wp core install failed (exit ${install_status}). Output above; fix .env or DB and restart, or finish setup in the browser."
		exit 1
	fi
fi

if [ "${WP_BLOG_PUBLIC:-1}" = "0" ] || [ "${WP_BLOG_PUBLIC:-}" = "false" ]; then
	"${WPC[@]}" option update blog_public 0
fi

echo >&2 "wp-auto-install: finished (blog_public=${WP_BLOG_PUBLIC:-1})."
