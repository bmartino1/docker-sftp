FROM phusion/baseimage:noble-1.0.1

LABEL maintainer=bmartino
LABEL description="Upgraded OpenSSH + Fail2Ban on top of Phusion BaseImage with full config support"

# Forked from markusmcnugen/sftp and atmoz for unRAID

# --- Stage full default config folders in container image for later use ---
# These are backups of all default configs (used optionally at runtime)
RUN mkdir -p /stage
COPY fail2ban/ /stage/fail2ban/
COPY sshd/ /stage/sshd/
COPY syslog-ng/ /stage/syslog-ng/
# Fix file permissions
RUN chmod 777 -R /stage/ && \
    chown nobody:users -R /stage/

# Persistent volume for external configuration
VOLUME /config

# First run rebuild - this will be overwritten by volume mount:
RUN mkdir -p /config/fail2ban/filter.d \
             /config/sshd/keys \
             /config/userkeys

# Install updated packages and setup
# - OpenSSH needs /var/run/sshd to run
# - Remove generic host keys; entrypoint generates unique keys
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        openssh-server \
        openssh-sftp-server \
        fail2ban \
        iptables \
        syslog-ng \
        net-tools \
        curl \
        iproute2 && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* && \
    mkdir -p /var/run/sshd /var/run/fail2ban && \
    rm -f /etc/ssh/ssh_host_*key*

# Copy updated and hardened entrypoint logic
COPY entrypoint /entrypoint
RUN chmod +x /entrypoint

# Ensure all runtime directories exist (for mounts, logs, and service compatibility)
RUN mkdir -p /etc/default/sshd \
             /etc/default/f2ban \
             /etc/fail2ban \
             /etc/fail2ban/filter.d \
             /etc/ssh \
             /etc/syslog-ng \
             /var/log \
             /var/run/sshd \
             /var/run/fail2ban

# --- Default config files (used if /config is empty) ---
COPY fail2ban/jail.local /etc/fail2ban/jail.d/jail.local
COPY fail2ban/fail2ban.conf /etc/fail2ban/fail2ban.conf
COPY fail2ban/filter.d/ /etc/fail2ban/filter.d/
COPY sshd/sshd_config /etc/default/sshd/sshd_config
COPY sshd/users.conf /stage/sshd/users.conf
COPY syslog-ng/syslog-ng.conf /etc/syslog-ng/syslog-ng.conf

# Open port for SSH / SFTP
EXPOSE 22

# Docker runs script
ENTRYPOINT ["/entrypoint"]
