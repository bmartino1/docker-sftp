#!/bin/bash
set -e

# Function to check and update a package using curl
update_package() {
    local package_name=$1
    local current_version=$2
    local latest_version=$3
    local package_url=$4

    echo "[INFO] Checking for updates for $package_name..."
    if dpkg --compare-versions "$latest_version" gt "$current_version"; then
        echo "[INFO] Newer version detected: $latest_version (current: $current_version)"
        echo "[INFO] Downloading $package_name version $latest_version..."
        curl -sSL -o "/tmp/$(basename $package_url)" "$package_url"
        echo "[INFO] Installing $package_name version $latest_version..."
        dpkg -i "/tmp/$(basename $package_url)"
        echo "[INFO] $package_name updated successfully."
    else
        echo "[INFO] $package_name is up-to-date (version: $current_version)."
    fi
}

# Update OpenSSH
current_openssh_version=$(ssh -V 2>&1 | awk '{print $1}' | cut -d'_' -f2)
latest_openssh_version="9.6p1-3ubuntu13.9"
openssh_package_url="http://archive.ubuntu.com/ubuntu/pool/main/o/openssh/openssh-server_${latest_openssh_version}_amd64.deb"
update_package "OpenSSH" "$current_openssh_version" "$latest_openssh_version" "$openssh_package_url"

# Update Fail2Ban
current_fail2ban_version=$(fail2ban-client -V | awk '{print $2}')
latest_fail2ban_version="1.0.2-3ubuntu0.1"
fail2ban_package_url="http://archive.ubuntu.com/ubuntu/pool/main/f/fail2ban/fail2ban_${latest_fail2ban_version}_all.deb"
update_package "Fail2Ban" "$current_fail2ban_version" "$latest_fail2ban_version" "$fail2ban_package_url"
