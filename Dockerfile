FROM markusmcnugen/sftp:latest

LABEL maintainer=bmartino
LABEL description="Upgraded OpenSSH + Fail2Ban on top of MarkusMcNugen SFTP container with full config support"

#Orginal Fork
#FROM phusion/baseimage:master-amd64
#MAINTAINER MarkusMcNugen
# Forked from atmoz for unRAID

VOLUME /config

# Steps done in one RUN layer:
# - Install packages
# - OpenSSH needs /var/run/sshd to run
# - Remove generic host keys, entrypoint generates unique keys
# Install updated versions of openssh-server, fail2ban, and iptables
RUN apt-get update && \
    apt-get upgrade -y && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        openssh-server \
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

# Copy updated and hardened entrypoint logic and default configurations
COPY entrypoint /
RUN chmod +x /entrypoint

# Make sure Fail2Ban directories exist (for mounts + logs)
RUN mkdir -p /etc/default/sshd \
             /etc/default/f2ban \
             /config/fail2ban/filter.d \
             /config/sshd/keys \
             /config/userkeys \
             /var/log \
             /var/run/sshd \
             /var/run/fail2ban

# Copy the Default config for backups (used to restore if /config is empty/missing files)
COPY fail2ban/jail.conf /etc/default/f2ban/jail.conf
COPY fail2ban/fail2ban.conf /etc/fail2ban/fail2ban.conf
COPY fail2ban/filter.d/ /etc/fail2ban/filter.d/
COPY sshd/sshd_config /etc/default/sshd/sshd_config
COPY syslog-ng/syslog-ng.conf /etc/syslog-ng/syslog-ng.conf

#Open posrt docker uses for ssh / sftp
EXPOSE 22

#Docker runs script
ENTRYPOINT ["/entrypoint"]
