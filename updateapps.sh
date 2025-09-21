#!/bin/bash
set -e

# ADDED: make apt noninteractive & allow selecting a newer suite containing OpenSSH v10 + libc6
export DEBIAN_FRONTEND=noninteractive
APT_TARGET_SUITE="${APT_TARGET_SUITE:-plucky}"   # set via Docker build ARG or container env if desired

# ADDED: targeted apt install for a given package from ${APT_TARGET_SUITE}, pulling deps (e.g., libc6)
apt_targeted_install() {
    local pkg="$1"
    echo "[INFO] Installing ${pkg} from suite '${APT_TARGET_SUITE}' via apt (with dependencies)..."
    apt-get update -qq
    if apt-get install -y --no-install-recommends -t "${APT_TARGET_SUITE}" "${pkg}"; then
        echo "[INFO] ${pkg} installed from ${APT_TARGET_SUITE}."
        return 0
    fi
    echo "[WARN] Failed to install ${pkg} from ${APT_TARGET_SUITE}."
    return 1
}

# ADDED: helper to install a local .deb and resolve deps from configured repos
apt_install_local_deb() {
    local deb_path="$1"
    echo "[INFO] Attempting to resolve dependencies via apt for $(basename "$deb_path")..."
    if apt-get update -qq; then
        if apt-get install -y --no-install-recommends "$deb_path"; then
            echo "[INFO] apt successfully installed $(basename "$deb_path") with dependencies."
            return 0
        fi
    fi
    echo "[ERROR] apt failed to install $(basename "$deb_path") with dependencies."
    return 1
}

# Function to check and update a package using curl and dpkg
update_package() {
    local package_name=$1
    local package_base_url=$2
    local package_pattern=$3

    echo "[INFO] Checking for updates for $package_name..."

    # Determine the current version installed
    local current_version
    current_version=$(dpkg-query --showformat='${Version}' --show "$package_name" 2>/dev/null || echo "")

    if [[ -z "$current_version" ]]; then
        echo "[WARN] $package_name is not currently installed."
    else
        echo "[INFO] Current version of $package_name: $current_version"
    fi

    # Fetch the latest version information from the package base URL with timeout and error handling
    echo "[INFO] Fetching latest version information for $package_name..."
    local curl_output
    if ! curl_output=$(curl -sSL --max-time 10 "$package_base_url"); then
        echo "[WARN] Failed to fetch package list for $package_name. Network may be down or URL unreachable. Skipping update."
        return 0
    fi

    local latest_package_info
    latest_package_info=$(echo "$curl_output" | grep -oP "$package_pattern" | sort -V | tail -n 1)

    if [[ -z "$latest_package_info" ]]; then
        echo "[ERROR] Could not retrieve latest version for $package_name from package list. Skipping update."
        return 0
    fi

    # Extract version from .deb filename (handles _amd64.deb and _all.deb)
    local latest_version
    latest_version=$(echo "$latest_package_info" | sed -E 's/^[^_]+_([^_]+)_(amd64|all)\.deb$/\1/')

    local latest_package_url="${package_base_url}${latest_package_info}"
    echo "[INFO] Latest version of $package_name available: $latest_version"

    # Normalize versions for comparison (strip epoch)
    local norm_current_version=${current_version#*:}

    # Compare versions and update if a newer version is available or if not currently installed
    if [[ -z "$current_version" ]] || dpkg --compare-versions "$latest_version" gt "$norm_current_version"; then
        echo "[INFO] Newer version detected: $latest_version (current: ${current_version:-none})"

        # Prefer apt from the newer suite (pulls libc6 etc.). If it works, we're done.
        if [[ "$package_name" =~ ^openssh-(client|server|sftp-server)$ ]]; then
            if apt_targeted_install "$package_name"; then
                return 0
            else
                echo "[WARN] Targeted apt install for $package_name failed; falling back to direct .deb download."
            fi
        fi

        echo "[INFO] Downloading $package_name version $latest_version..."
        local tmp_deb="/tmp/$latest_package_info"
        if ! curl -sSL --max-time 30 -o "$tmp_deb" "$latest_package_url"; then
            echo "[WARN] Failed to download $package_name package. Skipping installation."
            return 0
        fi

        echo "[INFO] Installing $package_name version $latest_version..."
        if dpkg -i "$tmp_deb"; then
            echo "[INFO] $package_name updated successfully."
        else
            echo "[WARN] dpkg reported missing dependencies for $package_name."
            if apt_install_local_deb "$tmp_deb"; then
                echo "[INFO] $package_name updated successfully (after resolving dependencies)."
            else
                echo "[ERROR] Failed to install $package_name. Manual dependency resolution may be required."
            fi
        fi
    else
        echo "[INFO] $package_name is up-to-date (version: $current_version)."
    fi
}

# Base URLs and patterns for the packages
openssh_base_url="http://archive.ubuntu.com/ubuntu/pool/main/o/openssh/"
openssh_server_pattern="openssh-server_[0-9]+\.[0-9]+p[0-9]+-[0-9a-zA-Z.+~]*_amd64\.deb"
openssh_client_pattern="openssh-client_[0-9]+\.[0-9]+p[0-9]+-[0-9a-zA-Z.+~]*_amd64\.deb"
openssh_sftp_pattern="openssh-sftp-server_[0-9]+\.[0-9]+p[0-9]+-[0-9a-zA-Z.+~]*_amd64\.deb"

fail2ban_base_url="http://archive.ubuntu.com/ubuntu/pool/universe/f/fail2ban/"
fail2ban_pattern="fail2ban_[0-9]+\.[0-9]+\.[0-9]+-[0-9]+_all\.deb"

# --- Check and update OpenSSH packages ---
# Install in order: client → server → sftp (server depends on exact same-version client)
update_package "openssh-client" "$openssh_base_url" "$openssh_client_pattern" || echo "[WARN] OpenSSH client update failed, continuing..."
update_package "openssh-server" "$openssh_base_url" "$openssh_server_pattern" || echo "[WARN] OpenSSH server update failed, continuing..."
update_package "openssh-sftp-server" "$openssh_base_url" "$openssh_sftp_pattern" || echo "[WARN] OpenSSH SFTP server update failed, continuing..."

# --- Check and update Fail2Ban ---
update_package "fail2ban" "$fail2ban_base_url" "$fail2ban_pattern" || echo "[WARN] Fail2Ban update failed, continuing..."

# --- Output Current Installed Versions ---
echo "[INFO] Versions of currently running software:"
echo -n "Fail2Ban: " && fail2ban-client -V 2>/dev/null | head -n1 | sed 's/[^0-9.]*\([0-9.]*\).*/\1/'
echo -n "OpenSSH client: " && ssh -V 2>&1 | grep -oP 'OpenSSH_\K[^ ]+'
echo -n "OpenSSH server: " && dpkg-query -W -f='${Version}\n' openssh-server 2>/dev/null

# --- Extra (optional) ---
#https://forums/unraid.net/topic/189050-support-sftp-fail2ban/#findComment-1545483

#echo "Installing whois..."
#https://ubuntu.pkgs.org/20.04/ubuntu-main-amd64/whois_5.5.6_amd64.deb.html
#if curl -sSL --max-time 30 -o /tmp/whois.deb http://archive.ubuntu.com/ubuntu/pool/main/w/whois/whois_5.5.6_amd64.deb; then
#    set +e
#    dpkg -i /tmp/whois.deb
#    set -e
#else
#    echo "[WARN] Failed to download whois package."
#fi

#echo "Copying custom fail2ban filters..."
#cp /config/fail2ban/logwhois.conf /etc/fail2ban/action.d/logwhois.conf
#cp /config/fail2ban/sshd-cipher-mismatch.conf /etc/fail2ban/filter.d/
#cp /config/fail2ban/sshd-banner-fail.conf /etc/fail2ban/filter.d/
