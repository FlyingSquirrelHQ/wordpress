# WordPress (Docker)

PHP 8.3, Apache, MariaDB, optional WP-CLI auto-install, and [Hyku](https://github.com/samvera/hyku)-style [Traefik](https://traefik.io/) labels on the shared **`stackcar`** network (the same external network Samvera apps use with the **stack_car** gem and `sc proxy`).

## Prerequisites

- [Docker](https://docs.docker.com/get-docker/) with Compose v2
- External Docker network **`stackcar`** (created by stack_car `sc proxy`, or once: `docker network create stackcar`)

## Quick start

Ensure the **`stackcar`** network exists (stack_car `sc proxy` creates it, or run `docker network create stackcar` once). From the repo root:

```bash
# Edit `.env` if needed (defaults target local dev; set strong DB passwords when sharing).

docker compose up -d
```

### HTTPS at `https://${APP_NAME}.localhost.direct`

With default **`APP_NAME=wordpress`**, the site is **`https://wordpress.localhost.direct`**. That only works if **something is listening on port 443** and routing to this project’s Traefik labels on network **`stackcar`**:

1. **stack_car** — run `sc proxy` (or your usual Traefik) *before* `docker compose up`, **or**
2. **Bundled Traefik** — if you are *not* running another proxy, start the optional service (binds host **80** and **443**; stop anything else using those ports first):

   ```bash
   docker compose --profile traefik up -d
   ```

   The first time you may see a browser warning for Traefik’s default certificate; proceed for local dev.

If you **cannot** use Traefik (ports blocked, no proxy), use the direct mapping instead:

- Open **http://localhost:8080** (or your **`WP_PORT`**).
- Set **`WP_SITE_URL=http://localhost:8080`** (and matching **`WP_DOMAIN_CURRENT_SITE`** if you use multisite `network` mode).

Set **`WP_SITE_URL`** and **`WP_DOMAIN_CURRENT_SITE`** in `.env` to match how you actually open the site (**https://…** behind Traefik, **http://localhost:…** for direct port).

- Database and `wp-config.php` are driven by **`WORDPRESS_*`** vars that the official image reads (see `.env`).
- Bootstrap / WP-CLI install uses **`WP_*`** (e.g. `WP_AUTO_INSTALL`, `WP_ADMIN_*`, `WP_SITE_URL`) so startup logs for `wp-config.php` stay limited to real config keys.
- To skip the five-minute web installer, set `WP_AUTO_INSTALL=1` (or `on`) plus `WP_ADMIN_PASSWORD` and `WP_ADMIN_EMAIL`; ensure `WP_SITE_URL` matches the URL you use in the browser. WP-CLI install runs only when the database does not already contain a site (if you used the browser installer once, reset the DB volume or run `docker compose down -v` before expecting automation again).

Stop:

```bash
docker compose down
```

Data volume `db_data` is kept unless you add `-v`.

### Troubleshooting “nothing loads” at `https://${APP_NAME}.localhost.direct`

1. **`docker compose ps`** — `wordpress` should be `Up`. If it exits, check **`docker compose logs wordpress`**.
2. **Traefik `502` during the first minute** — With `WP_AUTO_INSTALL`, Apache starts only after WP-CLI finishes (avoids racing the browser installer). Until then, Traefik may log `connection refused` to the WordPress container. If 502 persists after ~90s, check **`docker compose logs wordpress`**. After a bad run, reset the DB volume once: **`docker compose down -v`** then **`docker compose up -d`**.
3. **Proxy on 443** — `curl -vkI https://wordpress.localhost.direct/` (or your `APP_NAME`) should connect. If “Connection refused”, no Traefik (or other TLS proxy) is bound to **443** on the host — use **`--profile traefik`** or `sc proxy`, or use **http://localhost:8080** instead.
4. **Same Docker network** — `docker network inspect stackcar` should list both **wordpress** and **traefik** (or your `sc proxy` container).
5. **DNS** — `ping -c1 wordpress.localhost.direct` should resolve to **127.0.0.1** ([localhost.direct](https://readme.localhost.direct/)).

## Traefik + stack_car (`sc proxy`) — Hyku-style multitenant hosts

Samvera **Hyku** registers services on the external Docker network **`stackcar`** with Traefik labels (`websecure`, TLS, `traefik.docker.network=stackcar`). This repo mirrors that pattern so WordPress sits next to Hyku-style apps behind the same local proxy.

**Single site vs multisite:** Auto-install gives you **one** WordPress site. Traefik is pre-wired for **`https://<tenant>.${APP_NAME}.localhost.direct`** (e.g. `https://blog.wordpress.localhost.direct`), but those URLs only serve **separate network sites** after you enable **WordPress Multisite** (see §3). With `WP_MULTISITE_MODE=off`, extra subdomains are not separate blogs—use `prepare` → Network Setup → `network` mode when you want true multitenant WordPress.

### 1. Start your proxy

Use stack_car as you normally do locally, e.g.:

```bash
sc proxy
```

That should create the **`stackcar`** network and run Traefik with **`web`** / **`websecure`** entrypoints (same idea as Hyku’s `docker-compose.yml`). If you are not using stack_car, create the network and run Traefik yourself, attached to **`stackcar`**, with Docker provider and those entrypoint names.

When **`sc proxy`** (or any Traefik) is already bound to **80/443**, do **not** also run **`docker compose --profile traefik`** — you would get a port conflict. Use one or the other.

### 2. Configure `.env` for HTTPS hostnames

Pick a per-project **`APP_NAME`** so router names and hostnames do not clash with other stacks (same role as Hyku’s `APP_NAME`).

Example:

```dotenv
APP_NAME=wordpress

# Must match Traefik host + TLS (trailing slash optional for WP-CLI; use https behind proxy)
WP_SITE_URL=https://wordpress.localhost.direct

# Multisite “network” domain (subdomain installs): apex host, no scheme — same as ${APP_NAME}.localhost.direct
WP_DOMAIN_CURRENT_SITE=wordpress.localhost.direct

WP_MULTISITE_MODE=off
WP_SUBDOMAIN_INSTALL=false

WP_BEHIND_REVERSE_PROXY=true
```

Hosts use **`*.localhost.direct`**, which resolves to loopback without editing `/etc/hosts` (see [localhost.direct](https://readme.localhost.direct/)).

If **`APP_NAME`** is `fsq`, use:

- `WP_SITE_URL=https://fsq.localhost.direct`
- `WP_DOMAIN_CURRENT_SITE=fsq.localhost.direct`

Traefik routes (labels on the `wordpress` service in **`docker-compose.yml`**):

| URL pattern | Use |
|-------------|-----|
| `https://${APP_NAME}.localhost.direct` | Main site |
| `https://<tenant>.${APP_NAME}.localhost.direct` | Subdomain multisite tenants (after Network Setup + `network` mode) |

Two routers (apex `Host(...)` + subdomain `HostRegexp`) point at the same WordPress container on port 80.

### 3. Subdomain multisite (`<tenant>.${APP_NAME}.localhost.direct`)

1. **First boot:** `WP_MULTISITE_MODE=off`, `WP_SITE_URL=https://${APP_NAME}.localhost.direct`, `WP_DOMAIN_CURRENT_SITE=${APP_NAME}.localhost.direct`. Run auto-install (or install once in the browser).
2. **Allow multisite:** Set `WP_MULTISITE_MODE=prepare` (or `on`), `docker compose up -d --force-recreate wordpress`. In wp-admin go to **Tools → Network Setup**, choose **Sub-domains**, submit. WordPress will show extra `wp-config.php` lines—use the values below instead of editing the file by hand (this image regenerates `wp-config` from env).
3. **Lock in constants:** Set `WP_MULTISITE_MODE=network`, `WP_SUBDOMAIN_INSTALL=true`, `WP_DOMAIN_CURRENT_SITE` = apex only (e.g. `wordpress.localhost.direct`, no `https://`), `WP_PATH_CURRENT_SITE=/`. Match **Network Admin → Settings** if WordPress suggested different IDs. Recreate the container. **`.htaccess`:** with `WP_MULTISITE_MODE=network`, the image writes multisite rewrite rules to `/var/www/html/.htaccess` on start (bind-mounted `wp-content` only—no need to edit the file by hand for a root install at `/`).
4. **Add sites:** **Network Admin → Sites → Add New**; new blogs load at `https://<slug>.${APP_NAME}.localhost.direct` (same pattern as Hyku tenant hosts).

**Redirect loops (`ERR_TOO_MANY_REDIRECTS` on `wp-login.php`, `wp-signup.php`, etc.):** WordPress must see HTTPS (`is_ssl()`). The stack uses Apache **`SetEnvIf X-Forwarded-Proto`**, wp-config proxy fixes, **`docker-compose` Traefik labels** (`headers.sslProxyHeaders` on the **websecure** routers), **`WP_SYNC_HTTPS_SITEURL`**, and (optional) **`WP_DISABLE_REDIRECT_CANONICAL`** via **`wp-content/mu-plugins/flyingsquirrel-proxy.php`**. Recreate **`wordpress`** after label changes, restart/reload Traefik so it picks up new middleware, and clear cookies. In **`WP_MULTISITE_MODE=network`**, **`WP_HOME`** / **`WP_SITEURL`** are not injected in wp-config.

If you already installed under an old hostname (e.g. `wp-wordpress.localhost.direct`), either **search-replace URLs in the DB** or **`docker compose down -v`** and reinstall with the new `WP_SITE_URL`.

## Project layout

| Path | Purpose |
|------|---------|
| `Dockerfile` | WordPress base image pin, WP-CLI, PHP tweaks, baked `wp-content` merge |
| `docker-compose.yml` | MariaDB + WordPress, `env_file: .env`, Traefik labels, optional **`traefik` profile**, `WP_PORT` |
| `docker/docker-entrypoint-multitenant.sh` | Merges multisite / proxy PHP into `/run/wordpress-config-extra.php` and sets `WORDPRESS_CONFIG_EXTRA_FILE` (official image) |
| `docker/apache2-auto-install` | Optional WP-CLI install when `WP_AUTO_INSTALL` is set |
| `baked/wp-content/` | Plugins/themes copied into the image at build time |
| `wp-content/` | Bind-mounted for local development |

## Environment reference

See **`.env`** for database credentials, auto-install, multisite, and Traefik-related URLs. Bump pinned image versions in the `Dockerfile` and `docker-compose.yml` when you intentionally upgrade WordPress, PHP, MariaDB, or WP-CLI.

### WP-CLI and `WORDPRESS_CONFIG_EXTRA_FILE`

`docker compose exec` does not inherit the **runtime** env of Apache (PID 1). The **`/usr/local/bin/wp`** wrapper copies `WORDPRESS_CONFIG_EXTRA_FILE` and `WORDPRESS_CONFIG_EXTRA` from `/proc/1/environ` before running the phar so WP-CLI matches the web app.

## CI: PHP tests and coverage

GitHub Actions (`.github/workflows/ci.yml`) runs **PHPCS**, **PHPUnit** against the WordPress test library, collects **Clover** + HTML coverage for `wp-content/mu-plugins` (PCOV in CI), enforces a floor with `rregeer/phpunit-coverage-check`, and uploads **`clover.xml`** to **Codecov** (see `codecov.yml`).

**Repository setup**

- Install the [Codecov GitHub app](https://github.com/apps/codecov) on this repository (or organization) and add a **`CODECOV_TOKEN`** secret if Codecov asks for one (common for private repositories).
- Optional: set a repository variable **`PHP_COVERAGE_MIN`** (integer percent). If unset, CI defaults to **55** so the first merge does not fight an arbitrary ceiling; raise it over time after you confirm the real metric (see below).
- To block merges on green CI, use branch protection on `main` and require the **PHPUnit** workflow job (and the Codecov check if you want its status merge-blocking in addition to the local `coverage-check` step).

**Local coverage** (needs PCOV or Xdebug, plus MySQL for `bin/install-wp-tests.sh`):

```bash
composer install
bash bin/install-wp-tests.sh wordpress_test root root 127.0.0.1:3306 6.9.4
composer run test:coverage
./vendor/bin/coverage-check clover.xml 55   # use the same number as PHP_COVERAGE_MIN / composer.json "coverage:check"
```

After `composer run test:coverage`, inspect **`build/coverage-html/`** (when generated) or the CI artifact **php-coverage**. Ratchet **`PHP_COVERAGE_MIN`** and the `coverage:check` script in `composer.json` upward as coverage improves so they stay aligned with Codecov’s project/patch targets in `codecov.yml`.
