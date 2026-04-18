<?php
/**
 * PHPUnit bootstrap: WordPress test library + mu-plugin copied into test core.
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

$src = dirname( __DIR__ ) . '/wp-content/mu-plugins/flyingsquirrel-proxy.php';
$dst = $mu_dir . '/flyingsquirrel-proxy.php';
if ( ! is_readable( $src ) || ! copy( $src, $dst ) ) {
	echo 'Could not copy mu-plugin into test WordPress: ' . $src, PHP_EOL;
	exit( 1 );
}

require_once dirname( __DIR__ ) . '/vendor/yoast/phpunit-polyfills/phpunitpolyfills-autoload.php';

require $_tests_dir . '/includes/bootstrap.php';
