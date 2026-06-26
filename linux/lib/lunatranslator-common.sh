#!/usr/bin/env bash
# lunatranslator-common.sh — shared helpers for the LunaTranslator Wine wrappers.
#
# This file is sourced by every wrapper in /usr/bin. It owns:
#   * path resolution for the shared, portable LunaTranslator app
#   * first-run bootstrap (download + unzip the Windows portable build)
#   * run_luna_in_prefix(): the single code path that launches the shared
#     LunaTranslator into an arbitrary Wine/Proton prefix.
#

# --- configuration (override via environment) --------------------------------

# Where the shared, portable LunaTranslator lives. Its userconfig, caches and
# self-updates all persist here regardless of which prefix it is run in.
LT_DATA_HOME="${LT_DATA_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/lunatranslator}"
LT_APP_DIR="${LT_APP_DIR:-$LT_DATA_HOME/app}"

# Default prefix used when no game prefix is supplied (general OCR/clipboard use).
LT_DEFAULT_PREFIX="${LT_DEFAULT_PREFIX:-$LT_DATA_HOME/prefix}"

# Wine binary used for the default prefix. Per-launcher wrappers override this
# with the launcher's own wine/proton so the injected hook ABI matches the game.
LT_WINE="${LT_WINE:-wine}"

# Release channel. The portable Windows build matching a modern Wine is win10/x64.
LT_RELEASE_ASSET="${LT_RELEASE_ASSET:-LunaTranslator_x64_win10.zip}"
LT_RELEASE_URL="${LT_RELEASE_URL:-https://github.com/HIllya51/LunaTranslator/releases/latest/download/$LT_RELEASE_ASSET}"

# --- logging -----------------------------------------------------------------

lt_log()  { printf '\033[1;36m[lunatranslator]\033[0m %s\n' "$*" >&2; }
lt_warn() { printf '\033[1;33m[lunatranslator]\033[0m %s\n' "$*" >&2; }
lt_die()  { printf '\033[1;31m[lunatranslator]\033[0m %s\n' "$*" >&2; exit 1; }

# --- dependency checks -------------------------------------------------------

lt_need() {
	command -v "$1" >/dev/null 2>&1 || lt_die "required command '$1' not found (install it first)"
}

# Locate the LunaTranslator.exe inside the app dir. The release zip extracts to
# a single top-level folder (e.g. LunaTranslator_x64_win10/), so the exe may be
# one level down; resolve it robustly rather than assuming a flat layout.
lt_find_exe() {
	if [[ -f "$LT_APP_DIR/LunaTranslator.exe" ]]; then
		printf '%s\n' "$LT_APP_DIR/LunaTranslator.exe"
		return 0
	fi
	local found
	found="$(find "$LT_APP_DIR" -maxdepth 2 -iname 'LunaTranslator.exe' -print -quit 2>/dev/null)"
	[[ -n "$found" ]] && { printf '%s\n' "$found"; return 0; }
	return 1
}

# --- bootstrap ---------------------------------------------------------------

# Download + unpack the portable Windows build into LT_APP_DIR on first run.
# Idempotent: a no-op once LunaTranslator.exe is present.
lt_bootstrap() {
	if lt_find_exe >/dev/null; then
		return 0
	fi

	lt_log "First run: fetching the portable LunaTranslator build (one time only)."
	lt_log "After this, LunaTranslator updates itself; pacman only updates these wrappers."
	lt_need curl
	lt_need unzip

	local tmp zip extract inner
	tmp="$(mktemp -d)" || lt_die "could not create temp dir"
	# shellcheck disable=SC2064
	trap "rm -rf '$tmp'" RETURN
	zip="$tmp/luna.zip"

	lt_log "Downloading $LT_RELEASE_URL"
	curl -fL --retry 4 --retry-delay 2 -o "$zip" "$LT_RELEASE_URL" \
		|| lt_die "download failed. Set LT_RELEASE_URL to a reachable mirror and retry."

	extract="$tmp/extract"
	mkdir -p "$extract"
	lt_log "Extracting..."
	unzip -q "$zip" -d "$extract" || lt_die "unzip failed (corrupt download?)"

	# The zip contains a single top-level dir; treat the dir holding
	# LunaTranslator.exe as the app root.
	inner="$(find "$extract" -maxdepth 2 -iname 'LunaTranslator.exe' -printf '%h\n' -quit 2>/dev/null)"
	[[ -n "$inner" ]] || lt_die "LunaTranslator.exe not found in the downloaded archive"

	mkdir -p "$(dirname "$LT_APP_DIR")"
	rm -rf "$LT_APP_DIR"
	mv "$inner" "$LT_APP_DIR" || lt_die "could not install app to $LT_APP_DIR"
	lt_find_exe >/dev/null || lt_die "post-install sanity check failed"

	# Best-effort: surface an icon for the .desktop entry if the build ships one.
	lt_install_icon_from_app

	lt_log "Installed to $LT_APP_DIR"
}

# Copy an icon out of the app dir into the user icon theme if one exists.
lt_install_icon_from_app() {
	local ico dest
	dest="${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor/256x256/apps"
	ico="$(find "$LT_APP_DIR" -maxdepth 3 \( -iname 'lunatranslator.png' -o -iname 'icon.png' \) -print -quit 2>/dev/null)"
	[[ -n "$ico" ]] || return 0
	mkdir -p "$dest"
	cp -f "$ico" "$dest/lunatranslator.png" 2>/dev/null || true
}

# --- prefix launch -----------------------------------------------------------

# run_luna_in_prefix <wineprefix> [wine-binary]
#
# Launch the shared, portable LunaTranslator inside the given Wine prefix using
# the given wine binary (defaults to LT_WINE). Running inside the *game's* prefix
# is what lets HOOK attach — we join the prefix, we never patch or copy the game.
run_luna_in_prefix() {
	local prefix="${1:?run_luna_in_prefix: prefix required}"
	local wine="${2:-$LT_WINE}"
	local exe

	lt_bootstrap
	exe="$(lt_find_exe)" || lt_die "LunaTranslator.exe missing after bootstrap"

	command -v "$wine" >/dev/null 2>&1 || lt_die "wine binary '$wine' not found"
	mkdir -p "$prefix"

	lt_log "Launching LunaTranslator in prefix: $prefix (wine: $wine)"
	# WINEPREFIX joins the target prefix; the Z: drive exposes the shared app so
	# its config/updates persist no matter which prefix runs it.
	WINEPREFIX="$prefix" "$wine" "$exe" "${@:3}" &
	LT_PID=$!
	export LT_PID
}

# Start Luna in a prefix and wait briefly so it can register its clipboard /
# hook listeners before the game launches. Used by the per-game wrappers.
start_luna_then() {
	local prefix="$1" wine="$2"; shift 2
	run_luna_in_prefix "$prefix" "$wine"
	# give the GUI a moment to come up and start its listeners
	sleep "${LT_STARTUP_DELAY:-3}"
}
