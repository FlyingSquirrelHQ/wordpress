<?php
/**
 * Plugin Name: Flyingsquirrel reverse-proxy helpers
 * Description: Optional mitigations for Traefik / TLS termination (see WP_DISABLE_REDIRECT_CANONICAL in .env).
 *
 * @package Flyingsquirrel
 */

declare(strict_types=1);

add_action(
	'plugins_loaded',
	static function (): void {
		$raw = getenv( 'WP_DISABLE_REDIRECT_CANONICAL' );
		if ( $raw === false || $raw === '' ) {
			return;
		}
		$on = in_array( strtolower( (string) $raw ), array( '1', 'true', 'yes', 'on' ), true );
		if ( ! $on ) {
			return;
		}
		// Stops http↔https and host “canonical” loops that are common behind TLS-terminating proxies.
		remove_action( 'template_redirect', 'redirect_canonical' );
	},
	0
);
