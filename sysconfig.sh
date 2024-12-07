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
        echo "Unsupported package manager."
        exit 1
    fi
}

# Function to install packages for Debian-based systems
install_debian_packages() {
    local packages=("$@")
    sudo apt update
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

    # Use jq to parse the JSON file and get the packages array for the current distro
    packages=$(jq -r --arg distro "$distro" '.[$distro].packages[]' "$json_file")
    
    # Convert to an array (bash doesn't support complex structures easily, so we'll handle it as a simple list)
    echo "$packages"
}

# Function to download config file if it's a URL
download_config_file() {
    local url=$1
    local file_name=$(basename "$url")

    # Download the config file using wget or curl
    if command -v wget &> /dev/null; then
        wget -O "$file_name" "$url"
    elif command -v curl &> /dev/null; then
        curl -o "$file_name" "$url"
    else
        echo "Error: Neither wget nor curl is installed."
        exit 1
    fi

    echo "$file_name"
}

# Main script execution

# If the user hasn't provided the config file, prompt them for it
if [ "$#" -eq 0 ]; then
    read -p "Please enter the path or URL to the config file: " CONFIG_FILE
elif [ "$#" -eq 2 ] && [[ $1 == "--config" ]]; then
    CONFIG_FILE=$2
else
    echo "Usage: $0 --config <config_file>"
    exit 1
fi

# Check if the config file is a URL or a local file
if [[ "$CONFIG_FILE" =~ ^http[s]?:// ]]; then
    # If it's a URL, download the config file
    CONFIG_FILE=$(download_config_file "$CONFIG_FILE")
elif [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: Config file '$CONFIG_FILE' not found."
    exit 1
fi

# Check if jq is installed (for JSON parsing)
if ! command -v jq &> /dev/null; then
    echo "Error: jq is required but not installed."
    exit 1
fi

# Detect the system distribution from /etc/os-release
if [ -f /etc/os-release ]; then
    source /etc/os-release
    DISTRO=$ID
else
    echo "Could not determine the distribution."
    exit 1
fi

# Detect the available package manager
detect_package_manager

# Get the list of packages from the JSON config for the current distribution
PACKAGES=$(get_packages_for_distribution "$DISTRO" "$CONFIG_FILE")

# Convert the list of packages into an array
PACKAGE_ARRAY=($PACKAGES)

# Install the packages based on the detected package manager
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
        echo "Unsupported package manager."
        exit 1
        ;;
esac

echo "Packages installed successfully!"
