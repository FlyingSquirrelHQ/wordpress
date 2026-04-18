<?php
/**
 * Tests for flyingsquirrel-proxy mu-plugin.
 *
 * @package Flyingsquirrel
 */

declare(strict_types=1);

/**
 * Tests behavior without firing `template_redirect` (avoids header output under PHPUnit).
 */
class Flyingsquirrel_Proxy_Test extends WP_UnitTestCase {

	public function tearDown(): void {
		putenv( 'WP_DISABLE_REDIRECT_CANONICAL=' );
		remove_all_filters( 'flyingsquirrel_proxy_should_disable_redirect_canonical' );
		parent::tearDown();
	}

	public function test_should_disable_false_when_env_unset(): void {
		putenv( 'WP_DISABLE_REDIRECT_CANONICAL=' );
		$this->assertFalse( flyingsquirrel_proxy_should_disable_redirect_canonical() );
	}

	public function test_should_disable_true_when_env_on(): void {
		putenv( 'WP_DISABLE_REDIRECT_CANONICAL=on' );
		$this->assertTrue( flyingsquirrel_proxy_should_disable_redirect_canonical() );
	}

	public function test_filter_can_force_true_when_env_off(): void {
		putenv( 'WP_DISABLE_REDIRECT_CANONICAL=' );
		add_filter( 'flyingsquirrel_proxy_should_disable_redirect_canonical', '__return_true' );
		$this->assertTrue( flyingsquirrel_proxy_should_disable_redirect_canonical() );
	}
}
