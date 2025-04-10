#!/bin/bash
set -e

# Function to check and update a package using curl and dpkg
update_package() {
    local package_name=$1
    local package_base_url=$2

    echo "[INFO] Checking for updates for $package_name..."

    # Determine the current version installed
    local current_version
    case "$package_name" in
        openssh-server)
            current_version=$(dpkg-query --showformat='${Version}' --show openssh-server 2>/dev/null || echo "")
            ;;
        fail2ban)
            current_version=$(dpkg-query --showformat='${Version}' --show fail2ban 2>/dev/null || echo "")
            ;;
        *)
            echo "[ERROR] Unsupported package: $package_name"
            return 1
            ;;
    esac

    if [[ -z "$current_version" ]]; then
        echo "[WARN] $package_name is not currently installed."
    else
        echo "[INFO] Current version of $package_name: $current_version"
    fi

    # Fetch the latest version information from the package base URL
    echo "[INFO] Fetching latest version information for $package_name..."
    local latest_version_info=$(curl -sSL "$package_base_url" | grep -oP "${package_name}_\K[0-9a-zA-Z.+-]+(?=_amd64\.deb)" | sort -V | tail -n 1)

    if [[ -z "$latest_version_info" ]]; then
        echo "[ERROR] Could not retrieve latest version for $package_name. Skipping update."
        return
    fi

    local latest_version="${latest_version_info%-*}"
    local latest_package="${package_name}_${latest_version_info}_amd64.deb"
    local package_url="${package_base_url}${latest_package}"

    echo "[INFO] Latest version of $package_name available: $latest_version"

    # Compare versions and update if a newer version is available or if not currently installed
    if [[ -z "$current_version" ]] || dpkg --compare-versions "$latest_version" gt "$current_version"; then
        echo "[INFO] Newer version detected: $latest_version (current: ${current_version:-none})"
        echo "[INFO] Downloading $package_name version $latest_version..."
        curl -sSL -o "/tmp/$latest_package" "$package_url"

        echo "[INFO] Installing $package_name version $latest_version..."
        if dpkg -i "/tmp/$latest_package"; then
            echo "[INFO] $package_name updated successfully."
        else
            echo "[ERROR] Failed to install $package_name. You may need to manually resolve dependencies."
        fi
    else
        echo "[INFO] $package_name is up-to-date (version: $current_version)."
    fi
}

# Base URLs for the packages
openssh_base_url="http://archive.ubuntu.com/ubuntu/pool/main/o/openssh/"
fail2ban_base_url="http://archive.ubuntu.com/ubuntu/pool/main/f/fail2ban/"

# --- Check and update OpenSSH ---
update_package "openssh-server" "$openssh_base_url"

# --- Check and update Fail2Ban ---
update_package "fail2ban" "$fail2ban_base_url"
