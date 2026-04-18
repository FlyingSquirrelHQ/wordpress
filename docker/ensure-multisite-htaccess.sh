#!/usr/bin/env bash
# When WP_MULTISITE_MODE=network, WordPress expects multisite rewrite rules in
# /var/www/html/.htaccess (see Tools → Network Setup). The project bind-mounts only
# wp-content, so this script writes the rules on container start.
#
# Idempotent: skips if the file already contains our marker block.

set -euo pipefail

root=/var/www/html
ht="${root}/.htaccess"
marker='# BEGIN flyingsquirrel-wp-multisite'

if [[ ! -f "${root}/wp-config.php" ]]; then
	exit 0
fi

if [[ -f "${ht}" ]] && grep -qF "${marker}" "${ht}"; then
	exit 0
fi

# PATH_CURRENT_SITE e.g. / or /subdir/
pc="${WP_PATH_CURRENT_SITE:-/}"
pc="${pc#/}"
pc="${pc%/}"
if [[ -z "${pc}" ]]; then
	rewrite_base=/
else
	rewrite_base="/${pc}/"
fi

tmp="$(mktemp)"
trap 'rm -f "${tmp}"' EXIT

cat >"${tmp}" <<HTACCESS
${marker}
RewriteEngine On
RewriteRule .* - [E=HTTP_AUTHORIZATION:%{HTTP:Authorization}]
RewriteBase ${rewrite_base}
RewriteRule ^index\\.php\$ - [L]

# add a trailing slash to /wp-admin
RewriteRule ^wp-admin\$ wp-admin/ [R=301,L]

RewriteCond %{REQUEST_FILENAME} -f [OR]
RewriteCond %{REQUEST_FILENAME} -d
RewriteRule ^ - [L]
RewriteRule ^(wp-(content|admin|includes).*) \$1 [L]
RewriteRule ^(.*\\.php)\$ \$1 [L]
RewriteRule . index.php [L]
# END flyingsquirrel-wp-multisite
HTACCESS

install -m 0644 -o www-data -g www-data "${tmp}" "${ht}"
echo >&2 "ensure-multisite-htaccess: wrote ${ht} (RewriteBase ${rewrite_base})."
