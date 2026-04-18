# Standardized WordPress image: PHP (Apache), common extensions, and repo-specific defaults.
#
# Matches Docker Hub “wordpress” behavior: WORDPRESS_* env vars → wp-config-docker.php /
# WORDPRESS_CONFIG_EXTRA (see https://hub.docker.com/_/wordpress ). This image adds WP-CLI
# (official Hub also publishes wordpress:cli for one-off commands; we embed the phar so the
# same container can run first-boot `wp core install` with the same env as Apache).
#
# Versions are pinned to stable tags (bump deliberately when upgrading).

ARG WORDPRESS_VERSION=6.9.4
ARG PHP_VERSION=8.3

FROM wordpress:${WORDPRESS_VERSION}-php${PHP_VERSION}-apache

ARG WP_CLI_VERSION=2.12.0
RUN set -eux; \
	mkdir -p /usr/local/lib/wp-cli; \
	curl -fsSL -o /usr/local/lib/wp-cli/wp-cli.phar "https://github.com/wp-cli/wp-cli/releases/download/v${WP_CLI_VERSION}/wp-cli-${WP_CLI_VERSION}.phar"; \
	chmod +x /usr/local/lib/wp-cli/wp-cli.phar; \
	php /usr/local/lib/wp-cli/wp-cli.phar --allow-root cli info >/dev/null

# Ensure intl/exif when the base tag omits them (safe no-ops when already present).
RUN set -eux; \
	apt-get update; \
	apt-get install -y --no-install-recommends libicu-dev; \
	php -r 'exit(extension_loaded("intl") ? 0 : 1);' || docker-php-ext-install intl; \
	php -r 'exit(extension_loaded("exif") ? 0 : 1);' || docker-php-ext-install exif; \
	apt-get purge -y --auto-remove libicu-dev; \
	rm -rf /var/lib/apt/lists/*

# WP-CLI `wp db query` / `wp db check` invoke the `mysql` / `mysqlcheck` clients; the stock
# WordPress image does not ship them (errors: env: 'mysql': No such file or directory).
RUN set -eux; \
	apt-get update; \
	apt-get install -y --no-install-recommends default-mysql-client; \
	rm -rf /var/lib/apt/lists/*

COPY docker/php/conf.d/zz-custom.ini /usr/local/etc/php/conf.d/zz-custom.ini

# Baked plugins/themes ship in /usr/src/wordpress so the upstream entrypoint's tar copy
# merges them into /var/www/html/wp-content on first run (and upgrades respect existing dirs).
COPY baked/wp-content/plugins/ /usr/src/wordpress/wp-content/plugins/
COPY baked/wp-content/themes/ /usr/src/wordpress/wp-content/themes/
RUN set -eux; \
	chown -R www-data:www-data /usr/src/wordpress/wp-content; \
	find /usr/src/wordpress/wp-content -type d -exec chmod 755 {} \;; \
	find /usr/src/wordpress/wp-content -type f -exec chmod 644 {} \;

COPY docker/docker-entrypoint-multitenant.sh /usr/local/bin/docker-entrypoint-multitenant.sh
COPY docker/apache2-auto-install /usr/local/bin/apache2-auto-install
COPY docker/wp.sh /usr/local/bin/wp
COPY docker/wp-auto-install-www.sh /usr/local/share/wordpress/wp-auto-install-www.sh
COPY docker/ensure-multisite-htaccess.sh /usr/local/share/wordpress/ensure-multisite-htaccess.sh
RUN chmod +x /usr/local/bin/docker-entrypoint-multitenant.sh \
	/usr/local/bin/apache2-auto-install \
	/usr/local/bin/wp \
	/usr/local/share/wordpress/wp-auto-install-www.sh \
	/usr/local/share/wordpress/ensure-multisite-htaccess.sh

# Baked default: run `wp core install` on first start when the DB is empty (see
# apache2-auto-install). Override at runtime with `-e WP_AUTO_INSTALL=off` or Compose.
# WP_ADMIN_PASSWORD / WP_ADMIN_EMAIL are still required at runtime for headless install;
# do not put secrets in this Dockerfile.
ENV WP_AUTO_INSTALL=on

ENTRYPOINT ["docker-entrypoint-multitenant.sh"]
CMD ["apache2-auto-install"]
