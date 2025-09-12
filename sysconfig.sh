#!/bin/sh
# POSIX sh compatible

set -eu
IFS='
	'

LOG_LEVEL="INFO"   # INFO|DEBUG
DRY_RUN="false"
SILENT_MODE_ENV=""
YES="false"
CONFIG_FILE="${CONFIG_FILE:-}"
CONFIG_TYPE="${CONFIG_TYPE:-}"
SUDO=""

log() {
  lvl="$1"; shift
  if [ "$lvl" = "DEBUG" ] && [ "$LOG_LEVEL" != "DEBUG" ]; then
    return 0
  fi
  printf '[%s] %s\n' "$lvl" "$*" >&2
}

run() {
  log "DEBUG" "RUN: $*"
  if [ "$DRY_RUN" = "true" ]; then
    return 0
  fi
  "$@"
}

parse_arguments() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --config)       CONFIG_FILE="${2:-}"; shift 2 ;;
      --config-type)  CONFIG_TYPE="${2:-}"; shift 2 ;;
      --yes|-y)       YES="true"; shift ;;
      --silent)       SILENT_MODE_ENV="true"; shift ;;
      --dry-run)      DRY_RUN="true"; shift ;;
      --debug)        LOG_LEVEL="DEBUG"; shift ;;
      -h|--help)
        cat <<EOF
Usage: $0 --config <path_or_url_to_config_file> [options]

Options:
  --config <path_or_url>   JSON config path or HTTPS URL
  --config-type <name>     Configuration key to use (skips prompt)
  --yes | -y               Assume "yes" to prompts (non-interactive safe)
  --silent                 Force silent mode (skip extra packages prompt)
  --dry-run                Show what would happen; make no changes
  --debug                  Verbose debug logging
  -h | --help              Show this help
EOF
        exit 0 ;;
      *) echo "Unknown argument: $1"; echo "Try: $0 --help"; exit 1 ;;
    esac
  done
}

decide_sudo() {
  if [ "$(id -u)" -eq 0 ]; then SUDO=""; else SUDO="sudo"; fi
}

detect_package_manager() {
  if command -v apt-get >/dev/null 2>&1; then
    PACKAGE_MANAGER="apt"
  elif command -v dnf >/dev/null 2>&1; then
    PACKAGE_MANAGER="dnf"
  elif command -v pacman >/dev/null 2>&1; then
    PACKAGE_MANAGER="pacman"
  elif command -v apk >/dev/null 2>&1; then
    PACKAGE_MANAGER="apk"
  else
    echo "Error: Unsupported package manager."; exit 1
  fi
  log "DEBUG" "Detected package manager: $PACKAGE_MANAGER"
}

install_essential_tool() {
  tool="$1"
  if ! command -v "$tool" >/dev/null 2>&1; then
    log "INFO" "$tool is not installed. Installing $tool..."
    case "$PACKAGE_MANAGER" in
      apt)    run $SUDO apt-get update; run $SUDO apt-get install -y "$tool" ;;
      dnf)    run $SUDO dnf install -y "$tool" ;;
      pacman) run $SUDO pacman -S --noconfirm --needed "$tool" ;;
      apk)    run $SUDO apk add --no-cache "$tool" ;; 
      *) echo "Error: Unsupported package manager."; exit 1 ;;
    esac

  else
    log "DEBUG" "$tool already present"
  fi
}

install_jq() { install_essential_tool "jq"; }

validate_config_file() {
  config_file="$1"
  [ -f "$config_file" ] || { echo "Error: Configuration file '$config_file' does not exist."; exit 1; }
  jq empty "$config_file" >/dev/null 2>&1 || { echo "Error: Configuration file '$config_file' is not valid JSON."; exit 1; }
  log "INFO" "Validation successful: '$config_file' is valid."
}

download_config_file() {
  url="$1"
  if command -v mktemp >/dev/null 2>&1; then
    tmp="$(mktemp -t cfg.XXXXXX.json)"
  else
    tmp="/tmp/cfg.$$.$(date +%s).json"
  fi
  if command -v curl >/dev/null 2>&1; then
    run curl -fsSL "$url" -o "$tmp" || { echo "Error: Failed to download with curl."; exit 1; }
  elif command -v wget >/dev/null 2>&1; then
    run wget -qO "$tmp" "$url" || { echo "Error: Failed to download with wget."; exit 1; }
  else
    echo "Error: Neither curl nor wget is installed."; exit 1
  fi
  echo "$tmp"
}

install_packages() {
  [ "$#" -gt 0 ] || { log "INFO" "No packages to install."; return 0; }
  case "$PACKAGE_MANAGER" in
    apt)    run $SUDO apt-get update; run $SUDO apt-get install -y "$@" ;;
    dnf)    run $SUDO dnf install -y "$@" ;;
    pacman) run $SUDO pacman -S --noconfirm --needed "$@" ;;
    apk)    run $SUDO apk add --no-cache "$@" ;;
    *) echo "Error: Unsupported package manager."; exit 1 ;;
  esac
}


resolve_distro_key() {
  [ -f /etc/os-release ] || { echo "Error: Could not determine the distribution."; exit 1; }
  # shellcheck disable=SC1091
  . /etc/os-release

  prefer="${ID:-}"
  like_list="${ID_LIKE-}"   # may be unset under 'set -u'

  # Try exact ID first
  if [ -n "$prefer" ] && jq -e --arg d "$prefer" 'has($d)' "$CONFIG_FILE" >/dev/null 2>&1; then
    DISTRO="$prefer"
    log "INFO" "Detected distribution key: $DISTRO"
    return
  fi

  # Then try ID_LIKE (space-separated)
  if [ -n "$like_list" ]; then
    for like in $like_list; do
      if jq -e --arg d "$like" 'has($d)' "$CONFIG_FILE" >/dev/null 2>&1; then
        DISTRO="$like"
        log "INFO" "Using fallback distribution key via ID_LIKE: $DISTRO"
        return
      fi
    done
  fi

  # Helpful error with available keys
  avail_keys="$(jq -r 'keys[]' "$CONFIG_FILE" | paste -sd' ' -)"
  echo "Error: No configuration block for ID='${ID:-?}' and ID_LIKE='${ID_LIKE-}' in config.
Available top-level keys: ${avail_keys:-<none>}"
  exit 1
}



# ---------------- Entry ----------------
parse_arguments "$@"
decide_sudo
detect_package_manager

# Ensure a downloader exists (prefer curl); install only if neither exists.
if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
  install_essential_tool "curl"
fi

install_jq

# Acquire CONFIG_FILE
if [ -z "${CONFIG_FILE:-}" ]; then
  echo "No config file provided."
  if [ "$YES" != "true" ]; then
    if ! [ -t 0 ] && ! [ -t 1 ]; then
      echo "No TTY available and --config not provided. Exiting."; exit 1
    fi
    echo "Please enter the path or URL to the config file:" > /dev/tty
    # shellcheck disable=SC2162
    read CONFIG_FILE < /dev/tty
  else
    echo "Error: --yes specified but --config missing."; exit 1
  fi
fi

# If URL, download
case "$CONFIG_FILE" in
  http://*|https://*)
    case "$CONFIG_FILE" in https://*) : ;; *) log "INFO" "Warning: Using non-HTTPS URL." ;; esac
    CONFIG_FILE_TMP="$(download_config_file "$CONFIG_FILE")"
    trap 'rm -f "$CONFIG_FILE_TMP"' EXIT
    CONFIG_FILE="$CONFIG_FILE_TMP"
    ;;
  *)
    [ -f "$CONFIG_FILE" ] || { echo "Error: Config file '$CONFIG_FILE' not found."; exit 1; }
    ;;
esac

validate_config_file "$CONFIG_FILE"
resolve_distro_key

# List available config keys
CONFIG_KEYS="$(jq -r --arg d "$DISTRO" '.[$d] | keys[]' "$CONFIG_FILE" | sed '/^[[:space:]]*$/d')"
[ -n "$CONFIG_KEYS" ] || { echo "Error: No configurations found for distribution '$DISTRO'."; exit 1; }

# Verify/choose CONFIG_TYPE
if [ -n "${CONFIG_TYPE:-}" ]; then
  if ! printf '%s\n' "$CONFIG_KEYS" | grep -qx -- "$CONFIG_TYPE"; then
    avail="$(printf '%s' "$CONFIG_KEYS" | paste -sd' ' -)"
    echo "Error: CONFIG_TYPE '$CONFIG_TYPE' not found for '$DISTRO'. Available: $avail"
    exit 1
  fi
else
  if [ "$YES" != "true" ]; then
    echo "Available configurations for '$DISTRO':"
    idx=0
    printf '%s\n' "$CONFIG_KEYS" | while IFS= read -r key; do
      idx=$((idx+1))
      letter=$(printf "\\$(printf '%03o' $((96 + idx)))")
      echo "$idx ($letter) - $key"
    done
    if ! [ -t 0 ] && ! [ -t 1 ]; then
      echo "No TTY available to choose a configuration. Use --config-type <name>."
      exit 1
    fi
    echo "Please select a configuration by number or letter:" > /dev/tty
    # shellcheck disable=SC2162
    read CONFIG_SELECTION < /dev/tty

    SEL_LOWER=$(printf '%s' "$CONFIG_SELECTION" | tr '[:upper:]' '[:lower:]')
    case "$SEL_LOWER" in
      [a-z]) ord=$(printf "%d" "'$SEL_LOWER"); CONFIG_INDEX=$((ord - 97)) ;;
      *)     CONFIG_INDEX=$((CONFIG_SELECTION - 1)) ;;
    esac

    # Extract CONFIG_TYPE by index
    i=0
    : > /tmp/.cfgtype.$$
    printf '%s\n' "$CONFIG_KEYS" | while IFS= read -r key; do
      if [ "$i" -eq "$CONFIG_INDEX" ]; then
        printf '%s' "$key" > /tmp/.cfgtype.$$
        break
      fi
      i=$((i+1))
    done
    if [ ! -s /tmp/.cfgtype.$$ ]; then
      echo "Invalid selection. Exiting."; rm -f /tmp/.cfgtype.$$
      exit 1
    fi
    CONFIG_TYPE="$(cat /tmp/.cfgtype.$$)"
    rm -f /tmp/.cfgtype.$$
  else
    echo "Error: --yes given but --config-type missing."; exit 1
  fi
fi

# Ensure packages array exists and is array
jq -e --arg d "$DISTRO" --arg c "$CONFIG_TYPE" \
  '.[$d][$c].packages and (.[$d][$c].packages | type=="array")' \
  "$CONFIG_FILE" >/dev/null 2>&1 || {
    echo "Error: packages array missing or not an array for '$DISTRO' → '$CONFIG_TYPE'."; exit 1; }

# Read packages (newline-separated)
PACKAGES="$(jq -r --arg d "$DISTRO" --arg c "$CONFIG_TYPE" '.[$d][$c].packages[]' "$CONFIG_FILE" | sed '/^[[:space:]]*$/d')"

# Determine silent mode, allow --silent to override
SILENT_MODE="$(jq -r --arg d "$DISTRO" --arg c "$CONFIG_TYPE" '([.[$d][$c].silent] | first) // false | tostring' "$CONFIG_FILE")"
[ -n "$SILENT_MODE_ENV" ] && SILENT_MODE="true"
log "INFO" "Silent mode for '$CONFIG_TYPE': $SILENT_MODE"

# Optionally add more packages (interactive only, not silent, not --yes)
if [ "$SILENT_MODE" != "true" ] && [ "$YES" != "true" ]; then
  if [ -t 0 ] || [ -t 1 ]; then
    echo "Would you like to add more packages to the list? (y/n):" > /dev/tty
    # shellcheck disable=SC2162
    read ADD_MORE < /dev/tty
    case "$ADD_MORE" in
      y|Y)
        echo "Enter additional packages, separated by spaces:" > /dev/tty
        # shellcheck disable=SC2162
        read EXTRA_PACKAGES < /dev/tty
        if [ -n "$EXTRA_PACKAGES" ]; then
          EXTRA_NL=$(printf '%s' "$EXTRA_PACKAGES" | tr ' ' '\n' | sed '/^[[:space:]]*$/d')
          [ -n "$EXTRA_NL" ] && PACKAGES=$(printf '%s\n%s\n' "$PACKAGES" "$EXTRA_NL" | sed '/^[[:space:]]*$/d')
        fi
        ;;
      *) : ;;
    esac
  else
    log "DEBUG" "No TTY available; skipping extra packages prompt."
  fi
fi

# Confirm installation
CONFIRM="n"
if [ "$YES" = "true" ] || [ "$SILENT_MODE" = "true" ]; then
  CONFIRM="y"
else
  echo "The following packages will be installed:"
  printf '%s\n' "$PACKAGES" | while IFS= read -r p; do echo "  - $p"; done
  if [ -t 0 ] || [ -t 1 ]; then
    echo "Proceed with installation? (y/n):" > /dev/tty
    # shellcheck disable=SC2162
    read CONFIRM < /dev/tty
  else
    echo "No TTY available to confirm. Use --yes to proceed non-interactively."; exit 1
  fi
fi

case "$CONFIRM" in y|Y) : ;; *) echo "Installation cancelled."; exit 0 ;; esac

# Install packages (newline list → words; assumes no spaces in pkg names)
# shellcheck disable=SC2086
install_packages $PACKAGES

# Post-install summary
echo "Packages installed:"
printf '%s\n' "$PACKAGES" | while IFS= read -r package; do
  if command -v "$package" >/dev/null 2>&1; then
    echo "- $package: $(command -v "$package")"
  else
    echo "- $package"
  fi
done
