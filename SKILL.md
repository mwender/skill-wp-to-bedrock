---
name: wp-to-bedrock
description: "Convert a standard WordPress installation (in public/) to a Roots/Bedrock framework setup for sites in ~/webdev/laravel-valet/bedrock/."
compatibility: "Targets sites at ~/webdev/laravel-valet/bedrock/<site>/. Requires Composer 2.x, WP-CLI, and Laravel Valet (all confirmed available)."
---

# WP to Bedrock Migration

## When to use

Use this skill when a site under your local Bedrock directory has only a `public/` directory containing a standard WordPress installation and the goal is to convert it to a Roots/Bedrock structure.

## Environment facts (confirmed)

- **Valet TLD**: `.test` — all local URLs are `https://<slug>.test`
- **DB pattern**: `wp_<slug>` where slug is the domain name without its TLD (e.g., `example.com` → `wp_example`)
- **DB credentials**: typically `root` / empty password / `127.0.0.1`
- **auth.json**: lives one level above the site directory (e.g., `~/webdev/laravel-valet/bedrock/auth.json`) — must be copied to the site root (it is gitignored)
- **Composer repos**: wpackagist.org, packages.wenmarkdigital.com/satispress/ (wenmark/*), connect.advancedcustomfields.com
- **WP-CLI path**: runs from project root; `wp-cli.yml` must point `path: web/wp`, `server.docroot: web`
- **Valet + Bedrock**: Valet's built-in WordPress driver detects a Bedrock site via `web/wp-config.php` and serves from `web/` automatically — no custom driver needed

## Adapting this skill to a different environment

This skill was written for a specific local setup. If you are using it on a different machine, review and update these before running:

| Setting | Where it appears | What to change |
|---|---|---|
| Bedrock parent directory | Phase 0, Phase 5 | Replace `~/webdev/laravel-valet/bedrock/` with your own path |
| `auth.json` location | Phase 0, Phase 5 | Update to wherever your shared `auth.json` lives |
| Satispress URL | Phase 4, Environment facts | Replace `packages.wenmarkdigital.com/satispress/` with your own Satispress host |
| Satispress namespace | Phase 4 | Replace `wenmark/*` with your own Satispress package namespace |
| Valet TLD | Phase 6, Environment facts | Change `.test` if your Valet uses a different TLD |

## Inputs required

- The site directory name (e.g., `example.com`) — provided by the user
- Optionally: which plugins to manage via Composer vs. copy manually

---

## Procedure

### Phase 0 — Pre-flight checks

Before touching anything, verify all prerequisites. If any check fails, stop and report clearly — do not proceed.

```bash
# 1. Confirm the site directory exists and contains a standard WP install
ls <SITE_DIR>/public/wp-config.php

# 2. Confirm auth.json is present one level above the site directory
ls "$(dirname "$(pwd)")/auth.json"   # or the known shared location

# 3. Confirm Composer is available
composer --version

# 4. Confirm WP-CLI is available
wp --info

# 5. Confirm Valet is running
valet status

# 6. Confirm the local database exists (or can be created)
mysql -u root -e "SHOW DATABASES LIKE 'wp_<SITE_SLUG>';"
```

**Pass criteria:**

| Check | Pass | Fail — stop and report |
|---|---|---|
| `public/wp-config.php` exists | File found | Missing — not a standard WP install |
| `auth.json` present | File found | Ask user to confirm location |
| Composer | Any 2.x version | Not found or version < 2 |
| WP-CLI | Any version | Not found |
| Valet | Running | Start with `valet start` |
| DB exists | Database listed | Offer to create: `wp db create --path=public` |

If all checks pass, report a summary and proceed to Phase 1.

---

### Phase 1 — Gather site information

Derive key variables from the site directory name:

| Variable | Example | How to derive |
|---|---|---|
| `SITE_DIR` | `example.com` | Provided by user |
| `SITE_SLUG` | `example` | Strip TLD from `SITE_DIR` |
| `LOCAL_DOMAIN` | `example.test` | `<SITE_SLUG>.test` |

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

3. Resolve **every** plugin and theme from `public/wp-content/plugins/` and `public/wp-content/themes/` to a Composer package. All plugins and themes are managed via Composer — there is no fallback of copying files manually.

   **Decision tree for each plugin/theme:**

   | Source | Condition | Composer require string |
   |---|---|---|
   | wpackagist.org | Free plugin on WordPress.org | `wpackagist-plugin/<wp-slug>` |
   | wpackagist.org | Free theme on WordPress.org | `wpackagist-theme/<wp-slug>` |
   | wenmark/* (Satispress) | Premium plugin already in Satispress | `wenmark/<slug>` |
   | GitHub VCS | Custom plugin with a GitHub repo | Add VCS repo entry + `wenderhost/<plugin>` |
   | **UNKNOWN** | **Not found in any source yet** | **PAUSE — see below** |

   **When a plugin is not yet available anywhere:**

   Do not proceed past Phase 4 for that plugin. Instead, ask the user:

   > "The plugin `<plugin-slug>` is not available on wpackagist.org or at packages.wenmarkdigital.com/satispress/. Please add it to your Satispress instance and return the `wenmark/<package-slug>` string so I can add it to composer.json."

   Wait for the user to respond with the Satispress slug before continuing. Once received, add it to `require` as `"wenmark/<slug>": "*"` (or a specific version if provided).

   Add all resolved packages to the `require` block before moving to Phase 5.

4. Always add `"lukasbesch/bedrock-plugin-disabler": "^1.5"` to `require`. This package reads the `DISABLED_PLUGINS` constant defined in `config/environments/development.php` (configured in Phase 9) and prevents those plugins from loading locally.

5. Confirm the `extra.installer-paths` block targets `web/app/`:
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

### Phase 9 — Configure development plugin disabling

`lukasbesch/bedrock-plugin-disabler` reads a `DISABLED_PLUGINS` constant defined in `config/environments/development.php` and silently skips loading those plugins when `WP_ENV === 'development'`. This prevents production-only services (email delivery, security hardening, server agents) from running or nagging locally.

**Common candidates — cross-reference against what is actually installed for this site:**

| Plugin | Main plugin file |
|---|---|
| SpinupWP | `spinupwp/spinupwp.php` |
| iThemes Security Pro | `ithemes-security-pro/ithemes-security-pro.php` |
| Limit Login Attempts Reloaded | `limit-login-attempts-reloaded/limit-login-attempts-reloaded.php` |
| SMTP2GO | `smtp2go/smtp2go-wordpress-plugin.php` |
| Yoast SEO Premium | `wordpress-seo-premium/wp-seo-premium.php` |

**PAUSE** — before writing `development.php`, present a numbered list of candidates drawn from the plugins actually installed for this site, then ask:

> "Which of these should be disabled in the development environment? Reply with the numbers, e.g. `1, 3`:
>
> 1. SpinupWP — `spinupwp/spinupwp.php`
> 2. iThemes Security Pro — `ithemes-security-pro/ithemes-security-pro.php`
> 3. SMTP2GO — `smtp2go/smtp2go-wordpress-plugin.php`
> 4. Limit Login Attempts Reloaded — `limit-login-attempts-reloaded/limit-login-attempts-reloaded.php`
> _(include only plugins that are actually installed for this site)_
>
> Any others not on this list?"

Wait for the reply, then map the chosen numbers back to their plugin file paths and write the `DISABLED_PLUGINS` constant to `config/environments/development.php`, placed after the existing `Config::define('DISALLOW_FILE_MODS', false);` line:

```php
Config::define('DISABLED_PLUGINS', [
    'spinupwp/spinupwp.php',
    // ... other confirmed plugins
]);
```

---

### Phase 10 — Migrate content

All plugins and themes are managed via Composer (resolved in Phase 4 and installed in Phase 8). Do not manually copy plugin or theme directories.

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

### Phase 11 — Update database URLs

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

### Phase 12 — Remap Valet link and verify

#### Step 1: Check for an existing Valet link

If the site was previously linked from inside `public/`, there is a symlink in `~/.config/valet/Sites/` pointing to `public/` rather than the project root. Valet would serve the wrong directory.

```bash
# List all Valet links and their targets
valet links
```

Look for the site name (e.g., `example`) in the output. If the target path ends in `.../public`, it must be remapped.

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

### Phase 13 — Set up .gitignore

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

# Local work directory (scripts, context docs, scratch files)
bin/

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

### Phase 14 — Initialize git and cleanup

The `.gitignore` set up in Phase 13 already excludes `public/` and `public-backup/`, so the old WP install will never be staged — regardless of whether it has been archived yet.

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

### Phase 15 — Install sync-prod-to-local

This phase sets up the `bin/` directory and clones the `sync-prod-to-local` script as a self-contained subfolder within it.

#### Step 1: Create bin/ and clone the repo

```bash
mkdir -p bin
git clone git@github.com:mwender/sync-prod-to-local.git bin/sync-prod-to-local
```

#### Step 2: Add SYNC_* vars to .env

**PAUSE** — ask the user:

> "Do you have the production SSH/server details for this site yet? If yes, provide them and I'll add the SYNC_* vars to .env. If not, I'll add placeholder values you can fill in later."

Whether filled in or as placeholders, append this block to `.env`:

```dotenv
# --- WP Sync (prod -> local) ---
SYNC_REMOTE_SSH_USER=
SYNC_REMOTE_SSH_HOST=
SYNC_REMOTE_SSH_PORT=22
SYNC_REMOTE_HOST=
SYNC_LOCAL_HOST=<LOCAL_DOMAIN>
SYNC_REMOTE_WEB_DIR=
SYNC_REMOTE_STAGE_DIR=~/files
```

#### Step 3: Write post-import.sh

The hook lives at `bin/sync-prod-to-local/sync.d/post-import.sh`. Write it based on what is installed for this site.

**Elementor (auto-detect):** If `wpackagist-plugin/elementor` or `wenmark/elementor-pro` is in `composer.json`, always include the Elementor URL replacement and CSS flush:

```bash
wp elementor replace_urls "https://$SYNC_REMOTE_HOST" "https://$SYNC_LOCAL_HOST"
wp elementor flush_css
```

**Other post-import actions — PAUSE** and ask:

Before asking, scan `composer.json`'s `require` block for plugins that are commonly undesirable in a local dev environment (e.g. server management, security hardening, email delivery, CDN/caching plugins). Build a numbered list from only those that are actually present. Then append generic options at the end.

Example (adjust based on what is actually installed):

> "Any other post-import actions needed?
>
> 1. Deactivate SpinupWP (`wp plugin deactivate spinupwp`) ← only if `wpackagist-plugin/spinupwp` is in composer.json
> 2. Deactivate iThemes Security Pro (`wp plugin deactivate ithemes-security-pro`) ← only if `wenmark/ithemes-security-pro` is in composer.json
> 3. Activate a local-dev plugin (`wp plugin activate <slug>`)
> 4. Something else
>
> Reply with numbers and/or describe custom steps."

Only include plugin-deactivation entries for plugins confirmed present in `composer.json`. Do not list hypothetical plugins.

Assemble the confirmed actions into `bin/sync-prod-to-local/sync.d/post-import.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

cd "$WEB_DIR"

# Elementor URL replacement (included if Elementor is installed)
echo "👉 [Elementor] Replacing https://$SYNC_REMOTE_HOST with https://$SYNC_LOCAL_HOST..."
wp elementor replace_urls "https://$SYNC_REMOTE_HOST" "https://$SYNC_LOCAL_HOST"

echo "👉 [Elementor] Flushing CSS..."
wp elementor flush_css

# Additional project-specific actions confirmed above
# ...
```

Make the script executable:

```bash
chmod +x bin/sync-prod-to-local/sync.d/post-import.sh
```

#### Step 4: Usage

From the project root:

```bash
bin/sync-prod-to-local/sync-prod-to-local
```

Or with `-y` to skip the confirmation prompt:

```bash
bin/sync-prod-to-local/sync-prod-to-local -y
```

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
