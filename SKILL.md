---
name: wp-to-bedrock
description: "Convert a standard WordPress installation (in public/) to a Roots/Bedrock framework setup for sites in /Users/mwender/webdev/laravel-valet/bedrock/."
compatibility: "Targets sites at /Users/mwender/webdev/laravel-valet/bedrock/<site>/. Requires Composer 2.x, WP-CLI, and Laravel Valet (all confirmed available)."
---

# WP to Bedrock Migration

## When to use

Use this skill when a site in `/Users/mwender/webdev/laravel-valet/bedrock/` has only a `public/` directory containing a standard WordPress installation and the goal is to convert it to a Roots/Bedrock structure.

## Environment facts (confirmed)

- **Valet TLD**: `.test` — all local URLs are `https://<slug>.test`
- **DB pattern**: `wp_<slug>` where slug is the domain name without its TLD (e.g., `lewisburgwater.org` → `wp_lewisburgwater`)
- **DB credentials**: typically `root` / empty password / `127.0.0.1`
- **auth.json**: lives at `/Users/mwender/webdev/laravel-valet/bedrock/auth.json` — must be copied to the site root (it is gitignored)
- **Composer repos**: wpackagist.org, packages.wenmarkdigital.com/satispress/ (wenmark/*), connect.advancedcustomfields.com
- **WP-CLI path**: runs from project root; `wp-cli.yml` must point `path: web/wp`, `server.docroot: web`
- **Valet + Bedrock**: Valet's built-in WordPress driver detects a Bedrock site via `web/wp-config.php` and serves from `web/` automatically — no custom driver needed

## Inputs required

- The site directory name (e.g., `lewisburgwater.org`) — provided by the user
- Optionally: which plugins to manage via Composer vs. copy manually

---

## Procedure

### Phase 1 — Gather site information

Derive key variables from the site directory name:

| Variable | Example | How to derive |
|---|---|---|
| `SITE_DIR` | `lewisburgwater.org` | Provided by user |
| `SITE_SLUG` | `lewisburgwater` | Strip TLD from `SITE_DIR` |
| `LOCAL_DOMAIN` | `lewisburgwater.test` | `<SITE_SLUG>.test` |

Read `public/wp-config.php` and extract:
- `DB_NAME`, `DB_USER`, `DB_PASSWORD`, `DB_HOST`
- `$table_prefix`
- All eight salt/key constants: `AUTH_KEY`, `SECURE_AUTH_KEY`, `LOGGED_IN_KEY`, `NONCE_KEY`, `AUTH_SALT`, `SECURE_AUTH_SALT`, `LOGGED_IN_SALT`, `NONCE_SALT`

Inventory existing content:

```bash
wp core version --path=public
ls public/wp-content/plugins/
ls public/wp-content/themes/
ls public/wp-content/mu-plugins/
```

Identify which plugins are likely available via wpackagist (anything with a standard WordPress.org slug). Custom or premium plugins will be copied manually.

---

### Phase 2 — Export the database

```bash
mkdir -p sql
wp db export sql/pre-migration.sql --path=public --allow-root
```

Keep this export; do not delete it until the migration is verified.

---

### Phase 3 — Create the Bedrock scaffold

Run `composer create-project` in a temp directory, then move the scaffold to the site root:

```bash
composer create-project roots/bedrock /tmp/bedrock-scaffold --no-interaction
rsync -av --exclude='.git' /tmp/bedrock-scaffold/ /Users/mwender/webdev/laravel-valet/bedrock/<SITE_DIR>/
rm -rf /tmp/bedrock-scaffold
```

This installs the standard Bedrock structure:
- `composer.json`, `composer.lock`
- `.env.example`
- `config/application.php`, `config/environments/development.php`, `config/environments/staging.php`
- `web/index.php`, `web/wp-config.php`
- `wp-cli.yml`
- `.gitignore`, `.editorconfig`

---

### Phase 4 — Configure composer.json

1. Update the `name` field:
   ```json
   "name": "wenderhost/<SITE_SLUG>-bedrock-site"
   ```

2. Replace the default `repositories` block with the standard set:
   ```json
   "repositories": {
     "0": {
       "type": "composer",
       "url": "https://wpackagist.org",
       "only": ["wpackagist-plugin/*", "wpackagist-theme/*"]
     },
     "1": {
       "type": "composer",
       "url": "https://packages.wenmarkdigital.com/satispress/",
       "only": ["wenmark/*"]
     },
     "2": {
       "type": "composer",
       "url": "https://connect.advancedcustomfields.com"
     }
   }
   ```

3. Add to `require` — common base packages (adjust based on the plugin inventory):
   ```json
   "wpackagist-theme/hello-elementor": "^3",
   "wpackagist-plugin/elementor": "^3",
   "wenmark/elementor-pro": "^3",
   "wpackagist-plugin/disable-emojis": "^1.7",
   "wpackagist-plugin/wordpress-seo": "^26",
   "wpackagist-plugin/updraftplus": "^1"
   ```
   Add other wpackagist-available plugins from the inventory. Ask the user if unclear.

4. Confirm the `extra.installer-paths` block targets `web/app/`:
   ```json
   "extra": {
     "installer-paths": {
       "web/app/mu-plugins/{$name}/": ["type:wordpress-muplugin"],
       "web/app/plugins/{$name}/": ["type:wordpress-plugin"],
       "web/app/themes/{$name}/": ["type:wordpress-theme"]
     },
     "wordpress-install-dir": "web/wp"
   }
   ```

---

### Phase 5 — Set up auth.json

Copy the shared auth.json from the bedrock parent directory:

```bash
cp /Users/mwender/webdev/laravel-valet/bedrock/auth.json .
```

(auth.json is gitignored — do not symlink, as that can cause path issues with Composer.)

---

### Phase 6 — Configure .env

Create `.env` from `.env.example`, filling in values extracted from `public/wp-config.php`:

```dotenv
DB_NAME='<DB_NAME>'
DB_USER='<DB_USER>'
DB_PASSWORD='<DB_PASSWORD>'
DB_HOST='127.0.0.1'

WP_ENV='development'
WP_HOME='https://<LOCAL_DOMAIN>'
WP_SITEURL="${WP_HOME}/wp"

WP_DEBUG=true
WP_DEBUG_LOG=true

AUTH_KEY='<from wp-config.php>'
SECURE_AUTH_KEY='<from wp-config.php>'
LOGGED_IN_KEY='<from wp-config.php>'
NONCE_KEY='<from wp-config.php>'
AUTH_SALT='<from wp-config.php>'
SECURE_AUTH_SALT='<from wp-config.php>'
LOGGED_IN_SALT='<from wp-config.php>'
NONCE_SALT='<from wp-config.php>'
```

---

### Phase 7 — Configure wp-cli.yml

The scaffold's default `wp-cli.yml` should already contain:

```yaml
path: web/wp
server:
  docroot: web
```

Confirm this is correct. Create `wp-cli.local.yml` only if there is a known production SSH target:

```yaml
@production:
  ssh: <user>@<host>/sites/<SITE_DIR>/files/web
```

---

### Phase 8 — Run composer install

```bash
composer install
```

WordPress core is installed to `web/wp/` and Bedrock packages to `vendor/`. Confirm no errors before proceeding.

---

### Phase 9 — Migrate content

#### Plugins not managed by Composer

```bash
cp -r public/wp-content/plugins/<plugin-slug>/ web/app/plugins/
```

Copy only plugins that are NOT already installed via Composer (i.e., not in `web/app/plugins/` after `composer install`).

#### Custom/active themes not managed by Composer

```bash
cp -r public/wp-content/themes/<custom-theme>/ web/app/themes/
```

Skip themes installed by Composer (e.g., `hello-elementor`, `twentytwentyfour`).

#### MU-plugins (custom only)

Bedrock installs its own mu-plugins (`bedrock-autoloader.php`, etc.). Copy only custom mu-plugins that don't conflict:

```bash
# Check what Bedrock already installed:
ls web/app/mu-plugins/

# Copy custom ones:
cp -r public/wp-content/mu-plugins/<custom-muplugin>/ web/app/mu-plugins/
```

#### Uploads (preserve all media)

```bash
cp -r public/wp-content/uploads/. web/app/uploads/
```

---

### Phase 10 — Update database URLs

The database contains the old siteurl/home values (possibly the production domain or the old local URL). Update them to the new local Bedrock URL:

```bash
# Check current values
wp option get siteurl
wp option get home

# Determine OLD_URL (may be production domain or old local URL)
# Then run search-replace dry-run first:
wp search-replace 'https://<OLD_URL>' 'https://<LOCAL_DOMAIN>' --dry-run --all-tables --report-changed-only
wp search-replace 'http://<OLD_URL>' 'https://<LOCAL_DOMAIN>' --dry-run --all-tables --report-changed-only

# If the output looks correct, run without --dry-run:
wp search-replace 'https://<OLD_URL>' 'https://<LOCAL_DOMAIN>' --all-tables --report-changed-only
wp search-replace 'http://<OLD_URL>' 'https://<LOCAL_DOMAIN>' --all-tables --report-changed-only
```

Also update `siteurl` to include the `/wp` suffix (Bedrock puts WP core in `web/wp/`):

```bash
wp option get siteurl
# Should be https://<LOCAL_DOMAIN>/wp — if not:
wp option update siteurl "https://<LOCAL_DOMAIN>/wp"
wp option update home "https://<LOCAL_DOMAIN>"
```

Flush rewrites:

```bash
wp rewrite flush
```

---

### Phase 11 — Remap Valet link and verify

#### Step 1: Check for an existing Valet link

If the site was previously linked from inside `public/`, there is a symlink in `~/.config/valet/Sites/` pointing to `public/` rather than the project root. Valet would serve the wrong directory.

```bash
# List all Valet links and their targets
valet links
```

Look for the site name (e.g., `lewisburgwater`) in the output. If the target path ends in `.../public`, it must be remapped.

#### Step 2: Remap the link (if needed)

```bash
# Unlink from inside public/
cd public && valet unlink && cd ..

# Relink from the project root (Valet's WordPress driver will serve from web/)
valet link --secure <SITE_SLUG>
```

If no link existed (the site was served via Valet's path-based watching), no action is needed — Valet already serves the project root, and the WordPress driver detects Bedrock via `web/wp-config.php`.

#### Step 3: Restart Valet and test

```bash
valet restart
```

1. Visit `https://<LOCAL_DOMAIN>` in a browser — site should load
2. Visit `https://<LOCAL_DOMAIN>/wp/wp-admin/` — admin should load
3. Check for errors: `tail -f web/app/debug.log` (if WP_DEBUG_LOG=true)

---

### Phase 12 — Set up .gitignore

Replace or update `.gitignore` with the standard pattern for this environment:

```gitignore
# Application
web/app/plugins/*
!web/app/plugins/.gitkeep
web/app/mu-plugins/*/
web/app/themes/twentytwentyfour/
web/app/themes/hello-elementor/
web/app/upgrade
web/app/uploads/*
!web/app/uploads/.gitkeep
web/app/cache/*
web/app/updraft/
sql/
auth.json

# Old standard WP install (pre-migration)
public/
public-backup/

# WordPress
web/wp
web/.htaccess

# Logs
*.log

# Dotenv
.env
.env.*
!.env.example

# Composer
/vendor

# WP-CLI
wp-cli.local.yml

# Misc
*.sublime-*
*.sh
```

Adjust the ignored themes list to reflect what is managed by Composer for this site.

---

### Phase 13 — Initialize git and cleanup

The `.gitignore` set up in Phase 12 already excludes `public/` and `public-backup/`, so the old WP install will never be staged — regardless of whether it has been archived yet.

```bash
# Touch gitkeep files for tracked-but-empty directories
touch web/app/plugins/.gitkeep
touch web/app/uploads/.gitkeep

# Initialize git and commit — public/ is excluded by .gitignore
git init
git add -A
git commit -m "Initial Bedrock setup migrated from public/"
```

After confirming the commit looks clean (`git show --stat`), archive or remove the old WP install:

```bash
# Safe: archive first, delete after further testing
mv public/ public-backup/

# Or, once fully verified:
rm -rf public-backup/
```

Both `public/` and `public-backup/` remain excluded from git at all times.

Update `AGENTS.md` to reflect the new Bedrock structure. Refer to `/Users/mwender/webdev/laravel-valet/bedrock/nccagent.com/AGENTS.md` as a template.

---

## Common issues

### White screen / 500 after migration
Enable debug in `.env` (`WP_DEBUG=true`, `WP_DEBUG_LOG=true`) and check `web/app/debug.log`. Most common cause: a plugin referencing a hardcoded `/wp-content/` path — run:
```bash
wp search-replace '/wp-content/' '/app/' --dry-run --all-tables
```
Only apply if confirmed safe (some themes/plugins store full URLs that should not be changed).

### Valet not serving from web/
Confirm `web/wp-config.php` exists (it is a Composer-installed file, not part of the manual scaffold). Run `valet restart`. If still broken, confirm the site directory is under a Valet-watched path (`valet paths`).

### composer install fails with auth errors
Confirm `auth.json` was copied to the site root and contains valid credentials for `packages.wenmarkdigital.com` and `connect.advancedcustomfields.com`.

### WP_CONTENT_URL mismatch (media broken)
Bedrock sets `WP_CONTENT_DIR` to `web/app/`. If the DB still has `wp-content` in attachment URLs, run:
```bash
wp search-replace '<OLD_DOMAIN>/wp-content/' '<LOCAL_DOMAIN>/app/' --dry-run --all-tables
```

### Table prefix
Default is `wp_`. If the source `wp-config.php` used a different prefix, Bedrock's `config/application.php` does not set `$table_prefix` — you must add it manually:
```php
$table_prefix = env('DB_PREFIX') ?: 'wp_';
```
And set `DB_PREFIX=<prefix>` in `.env`.
