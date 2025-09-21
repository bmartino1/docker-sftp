FROM phusion/baseimage:noble-1.0.2
#Ubuntu based docker image

LABEL maintainer=bmartino
LABEL description="Upgraded OpenSSH + Fail2Ban on top of Phusion BaseImage"
# a Updated ubuntu docker image Forked from markusmcnugen/sftp forekd from atmoz for unRAID

# --- Stage full default config folders in container image for entrypoint script ---
# These are backups of all default configs (used optionally at runtime)
RUN mkdir -p /stage
RUN mkdir -p /stage/debug/
COPY fail2ban/ /stage/fail2ban/
COPY sshd/ /stage/sshd/
COPY syslog-ng/ /stage/syslog-ng/
# Set open file permissions for stage
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
# - NOTE: We intentionally DO NOT pre-install openssh-* here. The update script will install v10
#         from a newer Ubuntu suite so that dependencies (e.g., libc6) are satisfied cleanly.
ARG APT_TARGET_SUITE=plucky   # choose a suite that contains OpenSSH v10 + required libc6 (e.g., oracular, plucky)
ENV DEBIAN_FRONTEND=noninteractive
RUN set -e; \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        fail2ban \
        iptables \
        syslog-ng \
        net-tools \
        curl \
        tzdata \
        iproute2 && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* && \
    mkdir -p /var/run/sshd /var/run/fail2ban && \
    rm -f /etc/ssh/ssh_host_*key*

# Add a newer Ubuntu suite as an extra repo and pin ONLY the packages we want from it
# This allows pulling OpenSSH v10 + libc6 from ${APT_TARGET_SUITE} without upgrading the whole base image.
RUN set -e; \
    echo "deb http://archive.ubuntu.com/ubuntu ${APT_TARGET_SUITE} main universe multiverse" > /etc/apt/sources.list.d/${APT_TARGET_SUITE}.list; \
    echo "deb http://archive.ubuntu.com/ubuntu ${APT_TARGET_SUITE}-updates main universe multiverse" >> /etc/apt/sources.list.d/${APT_TARGET_SUITE}.list; \
    echo "deb http://security.ubuntu.com/ubuntu ${APT_TARGET_SUITE}-security main universe multiverse" >> /etc/apt/sources.list.d/${APT_TARGET_SUITE}.list; \
    mkdir -p /etc/apt/preferences.d; \
    printf "Package: openssh-client\nPin: release n=%s\nPin-Priority: 990\n\n" "$APT_TARGET_SUITE" > /etc/apt/preferences.d/openssh-10.pref; \
    printf "Package: openssh-server\nPin: release n=%s\nPin-Priority: 990\n\n" "$APT_TARGET_SUITE" >> /etc/apt/preferences.d/openssh-10.pref; \
    printf "Package: openssh-sftp-server\nPin: release n=%s\nPin-Priority: 990\n\n" "$APT_TARGET_SUITE" >> /etc/apt/preferences.d/openssh-10.pref; \
    printf "Package: libc6\nPin: release n=%s\nPin-Priority: 990\n" "$APT_TARGET_SUITE" >> /etc/apt/preferences.d/openssh-10.pref

#Set TZ for date and time fix for Build date and logs.
ENV TZ=America/Chicago
RUN ln -snf /usr/share/zoneinfo/${TZ} /etc/localtime && echo ${TZ} > /etc/timezone

# Copy entrypoint logic that runs the application in the docker
COPY entrypoint /entrypoint
RUN chmod +x /entrypoint

# --- Default config files preset to run withount /config volume ---
COPY syslog-ng/syslog-ng.conf /etc/syslog-ng/syslog-ng.conf
COPY sshd/sshd_config /etc/default/sshd/sshd_config
#Fail2ban via .local files 
COPY fail2ban/jail.local /etc/fail2ban/jail.d/jail.local
COPY fail2ban/fail2ban.local /etc/fail2ban/fail2ban.local

#fix permission of files coppied
# Set proper ownership and permissions on config files
RUN chown -R root:root /etc/fail2ban /etc/default/sshd /etc/syslog-ng && \
    chmod 644 /etc/fail2ban/*.local /etc/fail2ban/jail.d/*.local && \
    chmod 644 /etc/default/sshd/sshd_config && \
    chmod 644 /etc/syslog-ng/syslog-ng.conf

#Autoupdate Feature for latter
COPY updateapps.sh /stage/updateapps.sh
RUN chmod +x /stage/updateapps.sh

#Debug Build
#RUN cp -r /etc/fail2ban /stage/debug/

#Host Debug Check commands...
#Check Fail2ban Repo Configs after build host commands...
# docker run -it --entrypoint /bin/bash %dockerbuilt name and tag%...
#Check files and settings...
# cd /stage/debug

#Double check and install lattest verions
RUN /stage/updateapps.sh

# Versioning - recorded at image build time for reference at runtime
RUN echo -n "Fail2Ban: " > /stage/debug/versions.txt && \
    fail2ban-client -V | head -n1 | sed 's/[^0-9.]*\([0-9.]*\).*/\1/' >> /stage/debug/versions.txt && \
    echo -n "OpenSSH client: " >> /stage/debug/versions.txt && \
    ssh -V 2>&1 | grep -oP 'OpenSSH_\K[^ ]+' >> /stage/debug/versions.txt && \
    echo -n "OpenSSH server: " >> /stage/debug/versions.txt && \
    dpkg-query -W -f='${Version}\n' openssh-server >> /stage/debug/versions.txt

# Persistent volume for external configuration
VOLUME /config

# Open port for SSH / SFTP
EXPOSE 22

# Docker runs script
ENTRYPOINT ["/entrypoint"]
