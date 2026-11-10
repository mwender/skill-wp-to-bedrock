#!/usr/bin/env bash
# Move a Bedrock site from WPackagist (legacy) to WP Packages
# (repo.wp-packages.org, run by Roots) without changing any plugin versions.
#
#   wpackagist-to-wp-packages.sh [--dry-run] [--use <pkg>:<version>]... [site-dir]
#
# Run it on a branch, from the site root or with the site directory as the
# argument. It edits composer.json and composer.lock only; it installs nothing.
#
#   --dry-run   Report what would change, and any package WP Packages can't
#               serve at its locked version. Changes nothing.
#   --use       Lock a package at a different version than WPackagist had, for
#               one WP Packages doesn't offer (e.g. a release the author never
#               tagged in SVN): --use wp-plugin/search-meter:2.14.1. Use the new
#               wp-plugin/ or wp-theme/ name. Its constraint in composer.json
#               becomes ^<version> (or the dev- version itself).
#
# What it does:
#   1. Checks every WPackagist package's locked version exists on WP Packages,
#      and stops with a list if any don't (unless covered by --use).
#   2. Renames wpackagist-plugin/<slug> -> wp-plugin/<slug> and
#      wpackagist-theme/<slug> -> wp-theme/<slug> in require, require-dev,
#      extra.patches and extra.installer-paths (the same renames as Roots'
#      migrate-from-wpackagist.sh), and replaces the WPackagist repository with
#      "wp-packages": {"type": "composer", "url": "https://repo.wp-packages.org",
#                      "only": ["wp-plugin/*", "wp-theme/*"]}.
#   3. Runs `composer update 'wp-plugin/*' 'wp-theme/*' --no-install` with
#      `--with <pkg>:<locked version>` for each renamed package, so the lock
#      keeps every version. A plain `composer update` would also upgrade most
#      plugins; this keeps the source switch separate from plugin updates.
#   4. Checks the renamed packages kept their versions (or took the --use
#      version), nothing else in the lock changed, and no wpackagist entry is
#      left.
# On any failure, composer.json and composer.lock are restored.

set -euo pipefail

DRY_RUN=false
SITE_DIR="."
USE_JSON='{}'
while (($#)); do
	case "$1" in
		--dry-run|-n) DRY_RUN=true ;;
		--use)
			[[ "${2:-}" == */*:* ]] || { echo "Error: --use needs <package>:<version>" >&2; exit 1; }
			USE_JSON="$(jq -c --arg k "${2%%:*}" --arg v "${2#*:}" '. + {($k): $v}' <<<"$USE_JSON")"
			shift ;;
		-h|--help) sed -n '2,35p' "$0"; exit 0 ;;
		*) SITE_DIR="$1" ;;
	esac
	shift
done

die() { printf 'Error: %s\n' "$*" >&2; exit 1; }
say() { printf '\033[1m==>\033[0m %s\n' "$*"; }

command -v jq >/dev/null || die "jq is required (brew install jq)"
command -v composer >/dev/null || die "composer is required"
command -v curl >/dev/null || die "curl is required"
cd "$SITE_DIR"
[[ -f composer.json ]] || die "no composer.json in $(pwd)"
[[ -f composer.lock ]] || die "no composer.lock in $(pwd); run composer install first"

# --- Detect -------------------------------------------------------------------

LEGACY_REQS="$(jq -r '[(.require // {}), (."require-dev" // {})] | add | keys[] | select(test("^wpackagist-(plugin|theme)/"))' composer.json)"
LEGACY_REPOS="$(jq -r '(.repositories // {}) | (if type == "array" then .[] else to_entries[].value end) | select(((.url // "") | test("wpackagist\\.org")) or ((.name // "") == "wpackagist")) | .url' composer.json)"

if [[ -z "$LEGACY_REQS" && -z "$LEGACY_REPOS" ]]; then
	say "No WPackagist packages or repository in composer.json; nothing to do."
	exit 0
fi

say "WPackagist (legacy) in $(pwd)/composer.json:"
[[ -n "$LEGACY_REPOS" ]] && sed 's/^/  repository: /' <<<"$LEGACY_REPOS"
[[ -n "$LEGACY_REQS" ]] && sed 's/^/  package:    /' <<<"$LEGACY_REQS"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Target versions, keyed by new name: the locked version, or the --use override.
jq --argjson use "$USE_JSON" '
	[(.packages + (."packages-dev" // []))[] | select(.name | startswith("wpackagist-"))
	 | {key: (.name | sub("^wpackagist-"; "wp-")), value: .version}] | from_entries
	| with_entries(.value = ($use[.key] // .value))' composer.lock > "$WORK/target.json"

# --- Check WP Packages has every target version ---------------------------------

say "Checking WP Packages offers each locked version"
norm() { perl -pe 's/^v//; 1 while s/\.0$//'; }   # 1.2.0 == 1.2, v1.2 == 1.2
MISSING=""
TRUNK=""
while IFS=$'\t' read -r pkg version; do
	available="$(curl -fsS "https://repo.wp-packages.org/p2/$pkg.json" 2>/dev/null | jq -r --arg p "$pkg" '.packages[$p][]?.version' || true)"
	if [[ -z "$available" ]]; then
		MISSING+="  $pkg $version: not on WP Packages at all (closed on WordPress.org, or renamed)"$'\n'
		continue
	fi
	if [[ "$version" == dev-* ]]; then
		TRUNK+="  $pkg $version"$'\n'
	fi
	if ! grep -qxF "$(norm <<<"$version")" < <(norm <<<"$available"); then
		tagged="$(grep -v '^dev-' <<<"$available" | sort -V | tail -1 || true)"
		trunk=""
		if grep -q '^dev-trunk$' <<<"$available"; then trunk=", and dev-trunk"; fi
		MISSING+="  $pkg $version: not offered; latest tagged is ${tagged:-none}$trunk"$'\n'
	fi
done < <(jq -r 'to_entries[] | "\(.key)\t\(.value)"' "$WORK/target.json")

if [[ -n "$TRUNK" ]]; then
	say "Warning: locked to a dev version. WP Packages serves these only from SVN, which needs svn wherever Composer runs, production included. Consider replacing them or putting them in Satispress:"
	printf '%s' "$TRUNK"
fi

if [[ -n "$MISSING" ]]; then
	say "These packages aren't on WP Packages at their locked version:"
	printf '%s' "$MISSING"
	cat <<'EOF'
For each, choose one, then run this again:
  - take a version WP Packages has:  --use wp-plugin/<slug>:<version>
  - put the plugin in Satispress (~/Projects/satispress) and require wenmark/<slug> instead
  - replace or drop the plugin
Nothing was changed.
EOF
	exit 1
fi
say "All $(jq length "$WORK/target.json") packages are available."

if $DRY_RUN; then
	say "Dry run: nothing changed. Run without --dry-run to migrate."
	exit 0
fi

if [[ -n "$(git status --porcelain -- composer.json composer.lock 2>/dev/null)" ]]; then
	die "composer.json or composer.lock has uncommitted changes; commit or stash them first"
fi

# Private GitHub VCS repos need a token; borrow gh's if Composer has none.
if [[ -z "${COMPOSER_AUTH:-}" ]] && ! composer config --global github-oauth.github.com >/dev/null 2>&1 \
	&& ! jq -e '."github-oauth"."github.com"' auth.json >/dev/null 2>&1 \
	&& command -v gh >/dev/null && TOKEN="$(gh auth token 2>/dev/null)"; then
	export COMPOSER_AUTH="{\"github-oauth\": {\"github.com\": \"$TOKEN\"}}"
	say "Using gh's GitHub token for Composer (this run only)"
fi

# --- Migrate ------------------------------------------------------------------

cp composer.json "$WORK/composer.json.orig"
cp composer.lock "$WORK/composer.lock.orig"
restore() {
	cp "$WORK/composer.json.orig" composer.json
	cp "$WORK/composer.lock.orig" composer.lock
	printf 'Error: migration failed; composer.json and composer.lock were restored.\n' >&2
}
trap 'restore' ERR

INDENT="$(awk '/^[ \t]+[^ \t]/ { match($0, /^[ \t]+/); print RLENGTH; exit }' composer.json)"
INDENT="${INDENT:-4}"

jq --indent "$INDENT" --argjson use "$USE_JSON" '
	def rename: if startswith("wpackagist-plugin/") then "wp-plugin/" + ltrimstr("wpackagist-plugin/")
	            elif startswith("wpackagist-theme/") then "wp-theme/" + ltrimstr("wpackagist-theme/")
	            else . end;
	def rename_keys: with_entries(.key |= rename);
	def is_wpackagist: ((.url // "") | test("wpackagist\\.org")) or ((.name // "") == "wpackagist");
	def wp_packages: {"type": "composer", "url": "https://repo.wp-packages.org", "only": ["wp-plugin/*", "wp-theme/*"]};
	# --use versions also become the constraint: ^<version>, or the dev- version itself
	def apply_use: with_entries(if $use[.key] then .value = ($use[.key] | if startswith("dev-") then . else "^" + . end) else . end);

	(if .require then .require |= (rename_keys | apply_use) else . end)
	| (if ."require-dev" then ."require-dev" |= (rename_keys | apply_use) else . end)
	| (if .extra.patches then .extra.patches |= rename_keys else . end)
	| (if .extra."installer-paths" then .extra."installer-paths" |= map_values(map(rename)) else . end)
	| (if (.repositories | type) == "array" then
	       .repositories = [(.repositories[] | select(is_wpackagist | not)), ({"name": "wp-packages"} + wp_packages)]
	   else
	       .repositories = (((.repositories // {}) | with_entries(select(.value | is_wpackagist | not))) + {"wp-packages": wp_packages})
	   end)
' "$WORK/composer.json.orig" > composer.json

WITH=()
while IFS= read -r pin; do WITH+=(--with "$pin"); done < <(jq -r 'to_entries[] | "\(.key):\(.value)"' "$WORK/target.json")

say "Resolving the renamed packages from WP Packages at their locked versions"
composer update 'wp-plugin/*' 'wp-theme/*' "${WITH[@]}" --no-install --no-scripts --no-interaction

# --- Verify -------------------------------------------------------------------

say "Checking the lock file"
# "name version" pairs from a lock file, filtered by a jq select expression
versions() { jq -r --slurpfile t "$WORK/target.json" "(.packages + (.\"packages-dev\" // []))[] | $1 | \"\\(.name) \\(.version)\"" "$2" | sort; }
diff <(jq -r 'to_entries[] | "\(.key) \(.value)"' "$WORK/target.json" | sort) \
     <(versions 'select(.name as $n | $t[0] | has($n))' composer.lock) \
	|| { echo "Renamed packages didn't lock at their target versions (< wanted, > got)" >&2; false; }
diff <(versions 'select(.name as $n | ($n | startswith("wpackagist-")) or ($t[0] | has($n)) | not)' "$WORK/composer.lock.orig") \
     <(versions 'select(.name as $n | $t[0] | has($n) | not)' composer.lock) \
	|| { echo "Packages other than the renamed ones changed (< before, > after)" >&2; false; }
if jq -e '[(.packages + (."packages-dev" // []))[].name | select(startswith("wpackagist-"))] | length > 0' composer.lock >/dev/null; then
	echo "wpackagist packages are still in composer.lock" >&2; false
fi
if composer validate --no-check-publish --no-interaction 2>&1 | grep -q "not up to date"; then
	echo "composer validate reports the lock file is out of date" >&2; false
fi

trap - ERR
say "Done: $(jq length "$WORK/target.json") packages now come from WP Packages."
if [[ "$USE_JSON" != '{}' ]]; then
	say "Version changes you asked for (constraints in composer.json changed to match):"
	jq -r --slurpfile o "$WORK/composer.lock.orig" 'to_entries[] | .key as $k | "  \($k): \(($o[0].packages + ($o[0]."packages-dev" // []))[] | select(.name == ($k | sub("^wp-"; "wpackagist-"))) | .version) -> \(.value)"' <<<"$USE_JSON"
fi
cat <<'EOF'

Next:
  1. composer install          (plugin folders keep their names, so no DB change)
  2. wp plugin list and wp theme list: compare with before; check the site loads
  3. grep the repo for any leftover "wpackagist" (bin/ scripts, docs, AGENTS.md)
  4. commit on the branch; on a Push-to-Deploy site, merging to main deploys it
EOF
