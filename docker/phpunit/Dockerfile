# PHP CLI for PHPUnit + WordPress test library (see docker/phpunit/run.sh).
FROM php:8.3-cli-bookworm

RUN apt-get update \
	&& apt-get install -y --no-install-recommends \
		default-mysql-client \
		git \
		unzip \
	&& docker-php-ext-install mysqli \
	&& rm -rf /var/lib/apt/lists/*

COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

WORKDIR /var/www/html
