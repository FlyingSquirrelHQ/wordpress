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

# --- Multisite (multitenant) modes -------------------------------------------
# WP_MULTISITE_MODE=off          default, no multisite defines
# WP_MULTISITE_MODE=prepare     define('WP_ALLOW_MULTISITE', true) for Tools → Network Setup
# WP_MULTISITE_MODE=network     full network block (use after network is configured / restored)
#
# When WP_MULTISITE_MODE=network, set at least:
#   WP_DOMAIN_CURRENT_SITE, WP_PATH_CURRENT_SITE (default /)
# Optional: WP_SUBDOMAIN_INSTALL (true|false), WP_SITE_ID_CURRENT_SITE, WP_BLOG_ID_CURRENT_SITE
#
# Aliases for "prepare": on, true, yes, 1 (common mistake vs WP_AUTO_INSTALL=on)

mode_raw="${WP_MULTISITE_MODE:-off}"
mode="$(printf '%s' "${mode_raw}" | tr '[:upper:]' '[:lower:]' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
case "${mode}" in
	prepare | on | true | yes | 1)
		echo >&2 "docker-entrypoint-multitenant: WP_MULTISITE_MODE='${mode_raw}' → WP_ALLOW_MULTISITE (use Tools → Network Setup in wp-admin)."
		append_config_extra "define('WP_ALLOW_MULTISITE', true);"
		;;
	network)
		echo >&2 "docker-entrypoint-multitenant: WP_MULTISITE_MODE=network → MULTISITE constants for ${WP_DOMAIN_CURRENT_SITE:-${APP_NAME:-wordpress}.localhost.direct}"
		domain="${WP_DOMAIN_CURRENT_SITE:-${APP_NAME:-wordpress}.localhost.direct}"
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

# Optional hardening / proxy hints (safe defaults for many compose setups)
if [ "${WP_BEHIND_REVERSE_PROXY:-true}" = "true" ] || [ "${WP_BEHIND_REVERSE_PROXY:-true}" = "1" ]; then
	append_config_extra "$(cat <<'PHP'
if (isset($_SERVER['HTTP_X_FORWARDED_PROTO']) && strpos($_SERVER['HTTP_X_FORWARDED_PROTO'], 'https') !== false) {
	$_SERVER['HTTPS'] = 'on';
}
if (!empty($_SERVER['HTTP_X_FORWARDED_HOST'])) {
	$forwarded = trim((string) $_SERVER['HTTP_X_FORWARDED_HOST']);
	$forwarded = trim(explode(',', $forwarded, 2)[0]);
	$forwarded = preg_replace('/:\d+$/', '', $forwarded);
	if ($forwarded !== '') {
		$_SERVER['HTTP_HOST'] = $forwarded;
	}
}
PHP
)"
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
