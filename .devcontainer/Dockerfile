FROM docker.io/library/debian:bullseye-20260112-slim

# Install necessary packages and create a non-root user
RUN apt-get update && \
    apt-get install -y curl ca-certificates procps iproute2 util-linux dnsutils netcat-openbsd git jq vim fish supervisor && \
    useradd -m vscode && \
    apt-get install -y sudo && \
    echo vscode ALL=\(root\) NOPASSWD:ALL > /etc/sudoers.d/vscode && \
    chmod 0440 /etc/sudoers.d/vscode

# Install Nix package manager
RUN curl -sSfL https://artifacts.nixos.org/nix-installer | sh -s -- install linux \
    --extra-conf "sandbox = false" --enable-flakes --init none --no-confirm && \
    sudo chown -R vscode /nix

# Set up Supervisor to run opencode serve on container start
RUN cat <<EOF > /etc/supervisor/conf.d/opencode.conf
[program:opencode]
command=/bin/bash -lc "opencode serve"
user=vscode
environment=HOME="/home/vscode",USER="vscode"
directory=/home/vscode
autostart=true
autorestart=false
stderr_logfile=/var/log/opencode.err.log
stdout_logfile=/var/log/opencode.out.log
EOF

ENV NIX_PAGER=cat
# Update PATH to include both the system Nix and the user's Nix profile
ENV PATH="/home/vscode/.nix-profile/bin:/nix/var/nix/profiles/default/bin:${PATH}"

# Install the packages from the flake as the vscode user
USER vscode
WORKDIR /setup
COPY flake.nix /setup/
RUN nix profile add . && \
    nix-store --gc && \
    nix-collect-garbage -d

# Set up opencode server configuration
RUN mkdir -p /home/vscode/.config/
COPY opencode.jsonc /home/vscode/.config/opencode.jsonc

# Entrypoint to start Supervisor, which will manage the opencode server process
USER root
ENTRYPOINT ["/usr/bin/supervisord", "-n"]
