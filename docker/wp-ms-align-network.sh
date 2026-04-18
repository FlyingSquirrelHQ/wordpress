#!/usr/bin/env bash
# Align wp_site + wp_blogs with WP_DOMAIN_CURRENT_SITE / WP_PATH_CURRENT_SITE using ONLY mysql.
# Sync site_id on the main blog row so it matches the network row WordPress resolves first.

set -uo pipefail

if [[ ! -f /var/www/html/wp-config.php ]]; then
	exit 0
fi

d_raw="${WP_DOMAIN_CURRENT_SITE:-}"
p_raw="${WP_PATH_CURRENT_SITE:-/}"
if [[ -z "${d_raw}" ]]; then
	echo >&2 "wp-ms-align-network: WP_DOMAIN_CURRENT_SITE is empty; skipping."
	exit 0
fi

prefix="${WORDPRESS_TABLE_PREFIX:-wp_}"
if [[ ! "${prefix}" =~ ^[a-zA-Z0-9_]+$ ]]; then
	echo >&2 "wp-ms-align-network: invalid WORDPRESS_TABLE_PREFIX; skipping."
	exit 1
fi

db="${WORDPRESS_DB_NAME:-}"
user="${WORDPRESS_DB_USER:-}"
if [[ -z "${db}" ]] || [[ -z "${user}" ]]; then
	echo >&2 "wp-ms-align-network: WORDPRESS_DB_NAME / WORDPRESS_DB_USER missing; skipping."
	exit 0
fi

host="${WORDPRESS_DB_HOST%%:*}"
port="${WORDPRESS_DB_HOST##*:}"
if [[ "${port}" == "${host}" ]]; then
	port="3306"
fi

blogs="${prefix}blogs"
site="${prefix}site"

d="$(printf '%s' "${d_raw}" | tr '[:upper:]' '[:lower:]')"
p="${p_raw//[[:space:]]/}"
[[ -z "${p}" ]] && p="/"
[[ "${p}" == /* ]] || p="/${p}"
if [[ "${p}" == "/" ]]; then
	p_out="/"
else
	[[ "${p}" == */ ]] || p="${p}/"
	p_out="${p}"
fi
p="${p_out}"

sql_escape() {
	printf '%s' "$1" | sed "s/'/''/g"
}
d_esc="$(sql_escape "${d}")"
p_esc="$(sql_escape "${p}")"
db_esc="$(sql_escape "${db}")"

export MYSQL_PWD="${WORDPRESS_DB_PASSWORD:-}"

mysql_n() {
	mysql -h"${host}" -P"${port}" -u"${user}" -N "$@"
}

tbl_exists() {
	local name="$1"
	local n
	n="$(mysql_n -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='${db_esc}' AND table_name='${name}'" 2>/dev/null || echo 0)"
	[[ "${n}" == "1" ]]
}

if ! tbl_exists "${blogs}" || ! tbl_exists "${site}"; then
	echo >&2 "wp-ms-align-network: ${blogs} or ${site} missing — not a multisite DB; skipping."
	exit 0
fi

echo >&2 "wp-ms-align-network: WP_MULTISITE_MODE=${WP_MULTISITE_MODE:-}(info); DOMAIN=${d} PATH=${p}"

echo >&2 "wp-ms-align-network: before —"
mysql_n -e "SELECT blog_id,site_id,domain,path FROM \`${db}\`.\`${blogs}\` ORDER BY blog_id" 2>/dev/null | while IFS= read -r line; do echo >&2 "  blogs: ${line}"; done || true
mysql_n -e "SELECT id,domain,path FROM \`${db}\`.\`${site}\` ORDER BY id" 2>/dev/null | while IFS= read -r line; do echo >&2 "  site: ${line}"; done || true

site_rows="$(mysql_n -e "SELECT COUNT(*) FROM \`${db}\`.\`${site}\`" 2>/dev/null | head -1 | tr -d '\r' | tr -d '[:space:]')"
if [[ ! "${site_rows}" =~ ^[0-9]+$ ]]; then
	echo >&2 "wp-ms-align-network: could not count rows in ${site} (mysql error?). stderr:"
	mysql -h"${host}" -P"${port}" -u"${user}" -D"${db}" -e "SELECT 1 FROM \`${site}\` LIMIT 1" >&2 || true
	exit 1
fi

if [[ "${site_rows}" == "0" ]]; then
	echo >&2 "wp-ms-align-network: ${site} is empty (half-finished multisite). Inserting network row."
	if ! mysql -h"${host}" -P"${port}" -u"${user}" -D"${db}" -e "
INSERT INTO \`${site}\` (domain, path) VALUES ('${d_esc}', '${p_esc}');
"; then
		echo >&2 "wp-ms-align-network: INSERT into ${site} failed."
		exit 1
	fi
fi

net_id="$(mysql_n -e "SELECT COALESCE(MIN(id), 0) FROM \`${db}\`.\`${site}\`" 2>/dev/null | head -1 | tr -d '\r' | tr -d '[:space:]')"
if [[ ! "${net_id}" =~ ^[0-9]+$ ]] || [[ "${net_id}" == "0" ]]; then
	echo >&2 "wp-ms-align-network: could not resolve network id from ${site} (raw='${net_id:-empty}')."
	mysql -h"${host}" -P"${port}" -u"${user}" -D"${db}" -e "SELECT id,domain,path FROM \`${site}\`" >&2 || true
	exit 1
fi

blog_total="$(mysql_n -e "SELECT COUNT(*) FROM \`${db}\`.\`${blogs}\`" 2>/dev/null | head -1 | tr -d '\r' | tr -d '[:space:]')"
if [[ "${blog_total}" == "0" ]]; then
	echo >&2 "wp-ms-align-network: ${blogs} is empty; inserting main site row (blog_id=1)."
	if ! mysql -h"${host}" -P"${port}" -u"${user}" -D"${db}" -e "
INSERT INTO \`${blogs}\` (blog_id, site_id, domain, path, registered, last_updated, public, archived, mature, spam, deleted, lang_id)
VALUES (1, ${net_id}, '${d_esc}', '${p_esc}', NOW(), NOW(), 1, 0, 0, 0, 0, 0)
ON DUPLICATE KEY UPDATE site_id=VALUES(site_id), domain=VALUES(domain), path=VALUES(path), last_updated=VALUES(last_updated);
"; then
		echo >&2 "wp-ms-align-network: INSERT into ${blogs} failed (schema may differ; try docker compose down -v)."
		exit 1
	fi
fi

target_blog=1
bcnt="$(mysql_n -e "SELECT COUNT(*) FROM \`${db}\`.\`${blogs}\` WHERE blog_id=1" 2>/dev/null | head -1 | tr -d '\r' | tr -d '[:space:]')"
if [[ "${bcnt}" != "1" ]]; then
	target_blog="$(mysql_n -e "SELECT MIN(blog_id) FROM \`${db}\`.\`${blogs}\`" 2>/dev/null | head -1 | tr -d '\r' | tr -d '[:space:]')"
	if [[ ! "${target_blog}" =~ ^[0-9]+$ ]]; then
		echo >&2 "wp-ms-align-network: ${blogs} still has no rows after INSERT; aborting."
		exit 1
	fi
	echo >&2 "wp-ms-align-network: blog_id=1 missing; using blog_id=${target_blog}"
fi

echo >&2 "wp-ms-align-network: updating network id=${net_id}, blog_id=${target_blog} → domain='${d}' path='${p}'"

if ! mysql -h"${host}" -P"${port}" -u"${user}" -D"${db}" -e "
UPDATE \`${site}\` SET domain='${d_esc}', path='${p_esc}' WHERE id=${net_id} LIMIT 1;
UPDATE \`${blogs}\` SET domain='${d_esc}', path='${p_esc}', site_id=${net_id} WHERE blog_id=${target_blog} LIMIT 1;
"; then
	echo >&2 "wp-ms-align-network: mysql UPDATE failed (check WORDPRESS_DB_* and DB reachability)."
	exit 1
fi

# WordPress sometimes stores the root blog path as '' instead of '/'. If CLI still fails, set:
#   WP_NETWORK_MAIN_PATH_EMPTY=1
if [[ "${WP_NETWORK_MAIN_PATH_EMPTY:-}" == "1" ]] || [[ "${WP_NETWORK_MAIN_PATH_EMPTY:-}" == "true" ]]; then
	echo >&2 "wp-ms-align-network: also setting main blog path to empty string (WP_NETWORK_MAIN_PATH_EMPTY)."
	mysql -h"${host}" -P"${port}" -u"${user}" -D"${db}" -e "
UPDATE \`${blogs}\` SET path='' WHERE blog_id=${target_blog} LIMIT 1;
" || true
fi

echo >&2 "wp-ms-align-network: after —"
mysql_n -e "SELECT blog_id,site_id,domain,path FROM \`${db}\`.\`${blogs}\` ORDER BY blog_id" 2>/dev/null | while IFS= read -r line; do echo >&2 "  blogs: ${line}"; done || true
mysql_n -e "SELECT id,domain,path FROM \`${db}\`.\`${site}\` ORDER BY id" 2>/dev/null | while IFS= read -r line; do echo >&2 "  site: ${line}"; done || true

echo >&2 "wp-ms-align-network: done."
