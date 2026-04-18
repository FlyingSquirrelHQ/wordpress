#!/usr/bin/env bash
# Wraps the official WordPress entrypoint to assemble WORDPRESS_CONFIG_EXTRA for
# multisite / multitenant-style installs from discrete environment variables.

set -Eeuo pipefail

append_config_extra() {
	local chunk="$1"
	if [ -z "${chunk}" ]; then
		return 0
	fi
	if [ -n "${WORDPRESS_CONFIG_EXTRA:-}" ]; then
		WORDPRESS_CONFIG_EXTRA="${WORDPRESS_CONFIG_EXTRA}"$'\n'"${chunk}"
	else
		WORDPRESS_CONFIG_EXTRA="${chunk}"
	fi
	export WORDPRESS_CONFIG_EXTRA
}

mode_raw="${WP_MULTISITE_MODE:-off}"
mode="$(printf '%s' "${mode_raw}" | tr '[:upper:]' '[:lower:]' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"

# Proxy fixes first so MULTISITE bootstrap never sees the wrong scheme/host.
if [ "${WP_BEHIND_REVERSE_PROXY:-true}" = "true" ] || [ "${WP_BEHIND_REVERSE_PROXY:-true}" = "1" ]; then
	append_config_extra "$(cat <<'PHP'
// WordPress is_ssl() ignores X-Forwarded-*; align with TLS termination (Traefik, etc.).
$__fs_https = false;
if (isset($_SERVER['HTTP_X_FORWARDED_PROTO']) && stripos((string) $_SERVER['HTTP_X_FORWARDED_PROTO'], 'https') !== false) {
	$__fs_https = true;
} elseif (!empty($_SERVER['HTTP_X_FORWARDED_SSL']) && strtolower((string) $_SERVER['HTTP_X_FORWARDED_SSL']) === 'on') {
	$__fs_https = true;
} elseif (!empty($_SERVER['HTTP_FRONT_END_HTTPS']) && strtolower((string) $_SERVER['HTTP_FRONT_END_HTTPS']) === 'on') {
	$__fs_https = true;
}
if ($__fs_https) {
	$_SERVER['HTTPS'] = 'on';
	$_SERVER['REQUEST_SCHEME'] = 'https';
	$_SERVER['SERVER_PORT'] = '443';
}
unset($__fs_https);
if (!empty($_SERVER['HTTP_X_FORWARDED_HOST'])) {
	$forwarded = trim((string) $_SERVER['HTTP_X_FORWARDED_HOST']);
	$forwarded = trim(explode(',', $forwarded, 2)[0]);
	$forwarded = preg_replace('/:\d+$/', '', $forwarded);
	if ($forwarded !== '') {
		$_SERVER['HTTP_HOST'] = strtolower($forwarded);
	}
} elseif (!empty($_SERVER['HTTP_HOST'])) {
	$_SERVER['HTTP_HOST'] = strtolower((string) $_SERVER['HTTP_HOST']);
	$_SERVER['HTTP_HOST'] = preg_replace('/:\d+$/', '', $_SERVER['HTTP_HOST']);
}
PHP
)"
fi

# --- Multisite (multitenant) modes -------------------------------------------
case "${mode}" in
	prepare | on | true | yes | 1)
		echo >&2 "docker-entrypoint-multitenant: WP_MULTISITE_MODE='${mode_raw}' → WP_ALLOW_MULTISITE (use Tools → Network Setup in wp-admin)."
		append_config_extra "define('WP_ALLOW_MULTISITE', true);"
		;;
	network)
		domain="${WP_DOMAIN_CURRENT_SITE:-${APP_NAME:-wordpress}.localhost.direct}"
		domain="$(printf '%s' "${domain}" | tr '[:upper:]' '[:lower:]')"
		echo >&2 "docker-entrypoint-multitenant: WP_MULTISITE_MODE=network → MULTISITE constants for ${domain}"
		path="${WP_PATH_CURRENT_SITE:-/}"
		subdomain="${WP_SUBDOMAIN_INSTALL:-false}"
		site_id="${WP_SITE_ID_CURRENT_SITE:-1}"
		blog_id="${WP_BLOG_ID_CURRENT_SITE:-1}"

		append_config_extra "$(cat <<PHP
define('MULTISITE', true);
define('SUBDOMAIN_INSTALL', filter_var('${subdomain}', FILTER_VALIDATE_BOOLEAN));
define('DOMAIN_CURRENT_SITE', '${domain}');
define('PATH_CURRENT_SITE', '${path}');
define('SITE_ID_CURRENT_SITE', ${site_id});
define('BLOG_ID_CURRENT_SITE', ${blog_id});
PHP
)"
		;;
	off | false | no | 0 | "") ;;
	*)
		echo >&2 "Unknown WP_MULTISITE_MODE='${mode_raw}' (use off, prepare, on, or network)"
		;;
esac

# Pin home/siteurl for single-site (and prepare) only — see README / .env (multisite breaks).
site_url="${WP_SITE_URL:-${WORDPRESS_SITE_URL:-}}"
if [ -n "${site_url}" ] && [ "${mode}" != "network" ]; then
	safe_url="${site_url//\'/\\\'}"
	append_config_extra "$(printf '%s\n' "define( 'WP_HOME', '${safe_url}' );
define( 'WP_SITEURL', '${safe_url}' );")"
fi

# Long / multiline values often fail getenv() under Apache. The official image supports
# WORDPRESS_CONFIG_EXTRA_FILE: wp-config reads the file contents and eval()s them (same as
# a literal WORDPRESS_CONFIG_EXTRA string, without relying on a huge env value).
extra_file='/run/wordpress-config-extra.php'
if [ -n "${WORDPRESS_CONFIG_EXTRA:-}" ]; then
	printf '%s\n' "${WORDPRESS_CONFIG_EXTRA}" >"${extra_file}"
	chmod 644 "${extra_file}" || true
	export WORDPRESS_CONFIG_EXTRA_FILE="${extra_file}"
fi

exec docker-entrypoint.sh "$@"
