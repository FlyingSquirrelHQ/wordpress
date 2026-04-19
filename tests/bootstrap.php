<?php
/**
 * PHPUnit bootstrap: WordPress test library + mu-plugin linked into test core.
 *
 * Uses a symlink (when supported) so the plugin is the same path PHPUnit coverage
 * whitelists; a plain copy under /tmp would load twice and redeclare functions
 * when the Clover report is generated.
 *
 * @package Flyingsquirrel
 */

declare(strict_types=1);

$_tests_dir = getenv( 'WP_TESTS_DIR' );
if ( false === $_tests_dir || '' === $_tests_dir ) {
	$_tests_dir = rtrim( sys_get_temp_dir(), '/\\' ) . '/wordpress-tests-lib';
}

if ( ! file_exists( $_tests_dir . '/includes/functions.php' ) ) {
	echo 'Could not find ' . $_tests_dir . '/includes/functions.php — run bin/install-wp-tests.sh first.', PHP_EOL;
	exit( 1 );
}

require_once $_tests_dir . '/includes/functions.php';

$wp_core_dir = getenv( 'WP_CORE_DIR' );
if ( false === $wp_core_dir || '' === $wp_core_dir ) {
	$wp_core_dir = rtrim( sys_get_temp_dir(), '/\\' ) . '/wordpress';
}

$mu_dir = $wp_core_dir . '/wp-content/mu-plugins';
if ( ! is_dir( $mu_dir ) && ! mkdir( $mu_dir, 0777, true ) && ! is_dir( $mu_dir ) ) {
	echo 'Could not create mu-plugins directory: ' . $mu_dir, PHP_EOL;
	exit( 1 );
}

$src      = dirname( __DIR__ ) . '/wp-content/mu-plugins/flyingsquirrel-proxy.php';
$src_real = realpath( $src );
$dst      = $mu_dir . '/flyingsquirrel-proxy.php';
if ( false === $src_real || ! is_readable( $src_real ) ) {
	echo 'Could not resolve mu-plugin source: ' . $src, PHP_EOL;
	exit( 1 );
}
if ( file_exists( $dst ) || is_link( $dst ) ) {
	if ( ! unlink( $dst ) ) {
		echo 'Could not remove existing mu-plugin path: ' . $dst, PHP_EOL;
		exit( 1 );
	}
}
$linked = function_exists( 'symlink' ) && symlink( $src_real, $dst );
if ( ! $linked && ! copy( $src_real, $dst ) ) {
	echo 'Could not link or copy mu-plugin into test WordPress: ' . $src_real, PHP_EOL;
	exit( 1 );
}

require_once dirname( __DIR__ ) . '/vendor/yoast/phpunit-polyfills/phpunitpolyfills-autoload.php';

require $_tests_dir . '/includes/bootstrap.php';
