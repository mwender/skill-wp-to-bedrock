# wp-to-bedrock

A Claude Code skill that automates migrating a standard WordPress installation to the [Roots/Bedrock](https://roots.io/bedrock/) framework.

## What it does

When invoked with `/wp-to-bedrock <site-directory>`, it walks through a 15-phase process to convert a site that has WordPress living in a `public/` directory into a full Bedrock project structure — complete with Composer-managed plugins, environment-based configuration, and production sync tooling.

### What gets set up

- **Bedrock scaffold** — `web/` docroot, `web/wp/` for WordPress core, `web/app/` for plugins/themes/uploads
- **Composer** — all plugins and themes managed via wpackagist, a private Satispress instance, or GitHub VCS repos; no manually copied plugin files
- **`.env`** — database credentials, WP salts, and environment URLs extracted from the original `wp-config.php`
- **Plugin disabling by environment** — uses [`lukasbesch/bedrock-plugin-disabler`](https://github.com/lukasbesch/bedrock-plugin-disabler) to disable server/security plugins that shouldn't run locally
- **Valet link remapping** — detects and fixes any existing Valet link pointing at `public/` so the site serves correctly from `web/`
- **Git initialization** — `.gitignore` tuned for Bedrock; `public/` excluded from day one
- **`bin/sync-prod-to-local`** — clones the [sync-prod-to-local](https://github.com/mwender/sync-prod-to-local) script into `bin/` and wires up a site-specific `post-import.sh` hook (auto-detects Elementor)

## Where it lives

`~/.claude/skills/wp-to-bedrock/SKILL.md` — loaded by Claude Code when you invoke `/wp-to-bedrock`.

## Environment assumptions

- Laravel Valet 4.x with `.test` TLD
- Sites live under `~/webdev/laravel-valet/bedrock/`
- Shared `auth.json` at `~/webdev/laravel-valet/bedrock/auth.json`
- Composer 2.x and WP-CLI available in `$PATH`
