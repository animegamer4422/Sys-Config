#!/bin/bash

# Function to parse command-line arguments
parse_arguments() {
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
            --config)
                CONFIG_FILE="$2"
                shift 2
                ;;
            *)
                echo "Unknown argument: $1"
                echo "Usage: $0 --config <path_or_url_to_config_file>"
                exit 1
                ;;
        esac
    done
}

# Function to detect the package manager (used for installing essential tools)
detect_package_manager() {
    if command -v apt &> /dev/null; then
        PACKAGE_MANAGER="apt"
    elif command -v dnf &> /dev/null; then
        PACKAGE_MANAGER="dnf"
    elif command -v pacman &> /dev/null; then
        PACKAGE_MANAGER="pacman"
    else
        echo "Error: Unsupported package manager."
        exit 1
    fi
}

# Function to ensure essential tools are installed
install_essential_tools() {
    local tool=$1
    if ! command -v "$tool" &> /dev/null; then
        echo "$tool is not installed. Installing $tool..."
        case $PACKAGE_MANAGER in
            "apt")
                $SUDO apt update && $SUDO apt install -y "$tool"
                ;;
            "dnf")
                $SUDO dnf install -y "$tool"
                ;;
            "pacman")
                $SUDO pacman -Sy --noconfirm "$tool"
                ;;
            *)
                echo "Error: Unsupported package manager."
                exit 1
                ;;
        esac
    fi
}

# Function to install jq if not installed
install_jq() {
    install_essential_tools "jq"
}

# Function to validate the configuration file
validate_config_file() {
    local config_file=$1

    # Check if the file exists
    if [ ! -f "$config_file" ]; then
        echo "Error: Configuration file '$config_file' does not exist."
        exit 1
    fi

    # Check if the file is a valid JSON
    if ! jq empty "$config_file" &> /dev/null; then
        echo "Error: Configuration file '$config_file' is not a valid JSON file."
        exit 1
    fi

    echo "Validation successful: Configuration file '$config_file' is valid."
}

# Parse command-line arguments
parse_arguments "$@"

# Detect the package manager
detect_package_manager

# Ensure jq is installed before validating the config file
install_jq

# Ensure essential tools (curl or wget) are installed
install_essential_tools "curl"
install_essential_tools "wget"


# Main script execution
if [ -z "$CONFIG_FILE" ]; then
    echo "No config file provided."
    echo "Please enter the path or URL to the config file:" > /dev/tty
    read -r CONFIG_FILE < /dev/tty
fi


# Function to install packages
install_packages() {
    local packages=("$@")
    case $PACKAGE_MANAGER in
        "apt")
            $SUDO apt update -y && $SUDO apt install -y "${packages[@]}"
            ;;
        "dnf")
            $SUDO dnf install -y "${packages[@]}"
            ;;
        "pacman")
            $SUDO pacman -Sy --noconfirm "${packages[@]}"
            ;;
        *)
            echo "Error: Unsupported package manager."
            exit 1
            ;;
    esac
}

# Function to download config file if it's a URL
download_config_file() {
    local url=$1
    local file_name=$(basename "$url")

    if command -v wget &> /dev/null; then
        wget -q -O "$file_name" "$url" || { echo "Error: Failed to download file using wget."; exit 1; }
    elif command -v curl &> /dev/null; then
        curl -s -o "$file_name" "$url" || { echo "Error: Failed to download file using curl."; exit 1; }
    else
        echo "Error: Neither wget nor curl is installed."
        exit 1
    fi

    echo "$file_name"
}

# Check if the script is run as root
if [ "$(id -u)" -eq 0 ]; then
    SUDO=""
else
    SUDO="sudo"
fi

if [[ "$CONFIG_FILE" =~ ^http[s]?:// ]]; then
    CONFIG_FILE=$(download_config_file "$CONFIG_FILE")
elif [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: Config file '$CONFIG_FILE' not found."
    exit 1
fi

# Validate the configuration file
validate_config_file "$CONFIG_FILE"

if [ -f /etc/os-release ]; then
    source /etc/os-release
    DISTRO=$ID
    echo "Detected distribution: $DISTRO"
else
    echo "Error: Could not determine the distribution."
    exit 1
fi


# Prompt the user to select a configuration type if not already provided
if [ -z "$CONFIG_TYPE" ]; then
    echo "Available configurations for '$DISTRO':"
    CONFIG_KEYS=($(jq -r --arg distro "$DISTRO" '.[$distro] | keys[]' "$CONFIG_FILE" 2>/dev/null))
    if [[ ${#CONFIG_KEYS[@]} -eq 0 ]]; then
        echo "Error: No configurations found for distribution '$DISTRO' in the config file."
        exit 1
    fi

    # Display configurations as numbered list
    for i in "${!CONFIG_KEYS[@]}"; do
        ALPHABET=$(printf "\x$(printf %x $((97 + i)))")
        echo "$((i + 1)) ($ALPHABET) - ${CONFIG_KEYS[$i]}"
    done

    # Prompt the user to select a configuration
    echo "Please select a configuration by number or letter:" > /dev/tty
    read -r CONFIG_SELECTION < /dev/tty

    # Convert letter to number if necessary
    if [[ "$CONFIG_SELECTION" =~ ^[a-zA-Z]$ ]]; then
        CONFIG_INDEX=$(( $(printf "%d" "'$CONFIG_SELECTION") - 97 ))
    else
        CONFIG_INDEX=$((CONFIG_SELECTION - 1))
    fi

    # Validate the selection
    if [[ $CONFIG_INDEX -lt 0 || $CONFIG_INDEX -ge ${#CONFIG_KEYS[@]} ]]; then
        echo "Invalid selection. Exiting."
        exit 1
    fi

    CONFIG_TYPE=${CONFIG_KEYS[$CONFIG_INDEX]}
fi

# Get the packages and silent mode for the selected configuration
PACKAGES=$(jq -r --arg distro "$DISTRO" --arg config "$CONFIG_TYPE" '.[$distro][$config].packages[]' "$CONFIG_FILE")
PACKAGE_ARRAY=($PACKAGES)
SILENT_MODE=$(jq -r --arg distro "$DISTRO" --arg config "$CONFIG_TYPE" '.[$distro][$config].silent' "$CONFIG_FILE")

if [[ "$SILENT_MODE" != "true" ]]; then
    SILENT_MODE=false
fi

echo "Silent mode for '$CONFIG_TYPE': $SILENT_MODE"

# Ask for additional packages if silent mode is disabled
if [ "$SILENT_MODE" = false ]; then
    echo "Would you like to add more packages to the list? (y/n):" > /dev/tty
    read -r ADD_MORE < /dev/tty

    if [[ "$ADD_MORE" =~ ^[Yy]$ ]]; then
        echo "Enter additional packages, separated by spaces:" > /dev/tty
        read -r -a EXTRA_PACKAGES < /dev/tty
        PACKAGE_ARRAY+=("${EXTRA_PACKAGES[@]}")
    fi
fi

# Confirm package installation
if [ "$SILENT_MODE" = true ]; then
    CONFIRM="y"
else
    echo "Do you want to proceed with installation? (y/n):" > /dev/tty
    read -r CONFIRM < /dev/tty
fi

if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo "Installation cancelled."
    exit 0
fi

# Install the packages
install_packages "${PACKAGE_ARRAY[@]}"

# Print the installed packages
echo "Packages installed:"
for package in "${PACKAGE_ARRAY[@]}"; do
    echo "- $package"
done
