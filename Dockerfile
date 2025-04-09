FROM phusion/baseimage:noble-1.0.1

LABEL maintainer=bmartino
LABEL description="Upgraded OpenSSH + Fail2Ban on top of Phusion BaseImage"
# a Updated ubuntu docker image Forked from markusmcnugen/sftp forekd from atmoz for unRAID

# --- Stage full default config folders in container image for later use ---
# These are backups of all default configs (used optionally at runtime)
RUN mkdir -p /stage
RUN mkdir -p /stage/debug/
COPY fail2ban/ /stage/fail2ban/
COPY sshd/ /stage/sshd/
COPY syslog-ng/ /stage/syslog-ng/
# Fix file permissions
RUN chmod 777 -R /stage/ && \
    chown nobody:users -R /stage/

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

# Persistent volume for external configuration
VOLUME /config

# --- Default config files preset to run withount /config volume ---
COPY syslog-ng/syslog-ng.conf /etc/syslog-ng/syslog-ng.conf
COPY sshd/sshd_config /etc/default/sshd/sshd_config
#Entry point will do this... issues with fail2ban configs... we want package maintainers first!
#COPY fail2ban/jail.local /etc/fail2ban/jail.d/jail.local
#COPY fail2ban/fail2ban.conf /etc/fail2ban/fail2ban.conf
#

#Debug
#RUN cp -r /etc/fail2ban /stage/debug/
#Check Fail2ban Repo Configs...

#Versioning
RUN echo -n "Fail2Ban: " > /stage/debug/versions.txt && \
    fail2ban-client -V | head -n1 >> /stage/debug/versions.txt && \
    echo -n "OpenSSH: " >> /stage/debug/versions.txt && \
    ssh -V 2>> /stage/debug/versions.txt

# Open port for SSH / SFTP
EXPOSE 22

# Docker runs script
ENTRYPOINT ["/entrypoint"]
