#!/bin/bash

# Function to detect the package manager
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

# Function to install packages for Debian-based systems
install_debian_packages() {
    local packages=("$@")
    sudo apt update -y
    sudo apt install -y "${packages[@]}"
}

# Function to install packages for Fedora-based systems
install_fedora_packages() {
    local packages=("$@")
    sudo dnf install -y "${packages[@]}"
}

# Function to install packages for Arch-based systems
install_arch_packages() {
    local packages=("$@")
    sudo pacman -Sy --noconfirm "${packages[@]}"
}

# Function to read the JSON file and get the packages list for the current distribution
get_packages_for_distribution() {
    local distro=$1
    local json_file=$2

    packages=$(jq -r --arg distro "$distro" '.[$distro].packages[]' "$json_file" 2>/dev/null)
    if [[ -z "$packages" ]]; then
        echo "Error: No packages found for distribution '$distro' in the config file."
        exit 1
    fi
    echo "$packages"
}

# Function to download config file if it's a URL
download_config_file() {
    local url=$1
    local file_name=$(basename "$url")

    if command -v wget &> /dev/null; then
        wget -O "$file_name" "$url" || { echo "Error: Failed to download file using wget."; exit 1; }
    elif command -v curl &> /dev/null; then
        curl -o "$file_name" "$url" || { echo "Error: Failed to download file using curl."; exit 1; }
    else
        echo "Error: Neither wget nor curl is installed."
        exit 1
    fi

    echo "$file_name"
}

# Main script execution
if [ -z "$CONFIG_FILE" ]; then
    echo "No config file provided."
    echo "Please enter the path or URL to the config file:"
    read -r CONFIG_FILE
fi

if [[ "$CONFIG_FILE" =~ ^http[s]?:// ]]; then
    CONFIG_FILE=$(download_config_file "$CONFIG_FILE")
elif [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: Config file '$CONFIG_FILE' not found."
    exit 1
fi

if ! command -v jq &> /dev/null; then
    echo "Error: jq is required but not installed."
    exit 1
fi

if [ -f /etc/os-release ]; then
    source /etc/os-release
    DISTRO=$ID
else
    echo "Error: Could not determine the distribution."
    exit 1
fi

detect_package_manager
PACKAGES=$(get_packages_for_distribution "$DISTRO" "$CONFIG_FILE")
PACKAGE_ARRAY=($PACKAGES)

case $PACKAGE_MANAGER in
    "apt")
        install_debian_packages "${PACKAGE_ARRAY[@]}"
        ;;
    "dnf")
        install_fedora_packages "${PACKAGE_ARRAY[@]}"
        ;;
    "pacman")
        install_arch_packages "${PACKAGE_ARRAY[@]}"
        ;;
    *)
        echo "Error: Unsupported package manager."
        exit 1
        ;;
esac

echo "Packages installed successfully!"
