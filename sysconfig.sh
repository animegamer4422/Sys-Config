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

# Function to install jq if not installed
install_jq() {
    if ! command -v jq &> /dev/null; then
        echo "jq is not installed. Installing jq..."
        case $PACKAGE_MANAGER in
            "apt")
                $SUDO apt update && $SUDO apt install -y jq
                ;;
            "dnf")
                $SUDO dnf install -y jq
                ;;
            "pacman")
                $SUDO pacman -Sy --noconfirm jq
                ;;
            *)
                echo "Error: Unsupported package manager."
                exit 1
                ;;
        esac
    fi
}

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

# Function to read the JSON file and get the packages list for the current distribution
get_packages_for_distribution() {
    local distro=$1
    local json_file=$2

    if ! packages=$(jq -r --arg distro "$distro" '.[$distro].packages[]' "$json_file" 2>/dev/null); then
        echo "Error: Failed to parse the config file. Ensure it is a valid JSON file."
        exit 1
    fi

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

# Main script execution
if [ -z "$CONFIG_FILE" ]; then
    echo "No config file provided."
    echo "Please enter the path or URL to the config file:" > /dev/tty
    read -r CONFIG_FILE < /dev/tty
fi

if [[ "$CONFIG_FILE" =~ ^http[s]?:// ]]; then
    CONFIG_FILE=$(download_config_file "$CONFIG_FILE")
elif [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: Config file '$CONFIG_FILE' not found."
    exit 1
fi

if [ -f /etc/os-release ]; then
    source /etc/os-release
    DISTRO=$ID
else
    echo "Error: Could not determine the distribution."
    exit 1
fi

# Detect the package manager
detect_package_manager

# Ensure jq is installed
install_jq

# Get the list of packages for the current distribution
PACKAGES=$(get_packages_for_distribution "$DISTRO" "$CONFIG_FILE")
PACKAGE_ARRAY=($PACKAGES)

# Install the packages
install_packages "${PACKAGE_ARRAY[@]}"

# List installed packages
echo "The following packages were installed:"
for pkg in "${PACKAGE_ARRAY[@]}"; do
    echo "- $pkg"
done
