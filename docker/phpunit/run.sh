#!/usr/bin/env bash
# Run inside the phpunit Compose service: install WP test library (once per fresh /tmp) and PHPUnit.
set -euo pipefail

cd /var/www/html

if [[ -z "${MARIADB_ROOT_PASSWORD:-}" ]]; then
	echo "MARIADB_ROOT_PASSWORD must be set (see .env)." >&2
	exit 1
fi

WP_PHPUNIT_VERSION="${WP_PHPUNIT_VERSION:-6.9.4}"

composer install --prefer-dist --no-progress --no-interaction

# Idempotent: install-wp-tests.sh prompts if DB exists; drop first.
mysql --user=root --password="${MARIADB_ROOT_PASSWORD}" --host=db --port=3306 --protocol=tcp \
	--execute="DROP DATABASE IF EXISTS wordpress_test;"

bash bin/install-wp-tests.sh wordpress_test root "${MARIADB_ROOT_PASSWORD}" db:3306 "${WP_PHPUNIT_VERSION}"

exec ./vendor/bin/phpunit "$@"
