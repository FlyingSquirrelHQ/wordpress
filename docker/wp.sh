#!/usr/bin/env bash
# `docker compose exec` injects the container *image* env, not the runtime env of PID 1.
# docker-entrypoint-multitenant.sh merges WORDPRESS_CONFIG_EXTRA after the image env is
# fixed; Apache inherits it via exec, but exec sessions do not. Read PID 1's environ so
# WP-CLI matches wp-config / multisite / proxy defines.

set -euo pipefail

WP_PHAR=/usr/local/lib/wp-cli/wp-cli.phar

if [[ -r /proc/1/environ ]]; then
	while IFS= read -r -d '' _line; do
		case "${_line}" in
			WP_CLI_URL=*)
				export WP_CLI_URL="${_line#WP_CLI_URL=}"
				;;
			WORDPRESS_CONFIG_EXTRA_FILE=*)
				export WORDPRESS_CONFIG_EXTRA_FILE="${_line#WORDPRESS_CONFIG_EXTRA_FILE=}"
				;;
			WORDPRESS_CONFIG_EXTRA=*)
				export WORDPRESS_CONFIG_EXTRA="${_line#WORDPRESS_CONFIG_EXTRA=}"
				;;
		esac
	done < /proc/1/environ
fi

exec php "${WP_PHAR}" "$@"
