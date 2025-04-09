FROM markusmcnugen/sftp:latest

LABEL maintainer=bmartino
LABEL description="Upgraded OpenSSH + Fail2Ban on top of MarkusMcNugen SFTP container with full config support"

#Orginal Fork
#FROM phusion/baseimage:master-amd64
#MAINTAINER MarkusMcNugen
# Forked from atmoz for unRAID

# --- Stage full default config folders in container image for latter ---
# These are backups of all default configs (used optionally at runtime)
RUN mkdir -p /stage
COPY fail2ban/ /stage/fail2ban/
COPY sshd/ /stage/sshd/
COPY syslog-ng/ /stage/syslog-ng/
#Fix file permission
RUN chmod 777 -R /stage/
RUN chown nobody:users -R /stage/


# Persistent volume for external configuration
VOLUME /config

#First run rebuild
# This will be overwritten by volume mount:
#Build Cleanup when needed...
#RUN rm -f /config/
RUN mkdir -p /config/fail2ban/filter.d \
             /config/sshd/keys \
             /config/userkeys

# Steps done in one RUN layer:
# - Install packages
# - OpenSSH needs /var/run/sshd to run
# - Remove generic host keys, entrypoint generates unique keys
# Install updated versions of openssh-server, fail2ban, and iptables
RUN sed -i 's|http://archive.ubuntu.com/ubuntu/|http://us.archive.ubuntu.com/ubuntu/|g' /etc/apt/sources.list && \
    sed -i 's|http://security.ubuntu.com/ubuntu|http://us.archive.ubuntu.com/ubuntu|g' /etc/apt/sources.list && \
    apt-get update && \
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

# Copy updated and hardened entrypoint logic
COPY entrypoint /
RUN chmod +x /entrypoint

# Make sure Fail2Ban directories exist (for mounts + logs)
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
COPY fail2ban/jail.conf /etc/default/f2ban/jail.conf
COPY fail2ban/fail2ban.conf /etc/fail2ban/fail2ban.conf
COPY fail2ban/filter.d/ /etc/fail2ban/filter.d/
COPY sshd/sshd_config /etc/default/sshd/sshd_config
COPY sshd/users.conf /stage/sshd/users.conf
COPY syslog-ng/syslog-ng.conf /etc/syslog-ng/syslog-ng.conf

#Open port docker uses for ssh / sftp
EXPOSE 22

#Docker runs script
ENTRYPOINT ["/entrypoint"]
