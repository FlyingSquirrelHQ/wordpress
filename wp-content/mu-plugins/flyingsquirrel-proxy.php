<?php
/**
 * Plugin Name: Flyingsquirrel reverse-proxy helpers
 * Description: Optional mitigations for Traefik / TLS termination (see WP_DISABLE_REDIRECT_CANONICAL in .env).
 *
 * @package Flyingsquirrel
 */

declare(strict_types=1);

/**
 * Whether to disable redirect_canonical (proxy / TLS termination loops).
 *
 * Filter `flyingsquirrel_proxy_should_disable_redirect_canonical` allows tests to override without a new process.
 *
 * @return bool
 */
function flyingsquirrel_proxy_should_disable_redirect_canonical(): bool {
	$raw = getenv( 'WP_DISABLE_REDIRECT_CANONICAL' );
	if ( false === $raw || '' === $raw ) {
		$enabled = false;
	} else {
		$enabled = in_array( strtolower( (string) $raw ), array( '1', 'true', 'yes', 'on' ), true );
	}

	return (bool) apply_filters( 'flyingsquirrel_proxy_should_disable_redirect_canonical', $enabled );
}

add_action(
	'template_redirect',
	static function (): void {
		if ( ! flyingsquirrel_proxy_should_disable_redirect_canonical() ) {
			return;
		}
		// Stops http↔https and host “canonical” loops that are common behind TLS-terminating proxies.
		remove_action( 'template_redirect', 'redirect_canonical' );
	},
	0
);
