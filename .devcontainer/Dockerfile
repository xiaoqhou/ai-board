FROM docker.io/library/debian:bullseye-20260112-slim

# Install necessary packages and create a non-root user
RUN apt-get update && \
    apt-get install -y curl ca-certificates procps iproute2 util-linux dnsutils netcat-openbsd git jq vim fish tmux && \
    useradd -m vscode && \
    apt-get install -y sudo && \
    echo vscode ALL=\(root\) NOPASSWD:ALL > /etc/sudoers.d/vscode && \
    chmod 0440 /etc/sudoers.d/vscode

# Install Nix package manager
RUN curl -sSfL https://artifacts.nixos.org/nix-installer | sh -s -- install linux \
    --extra-conf "sandbox = false" --enable-flakes --init none --no-confirm && \
    sudo chown -R vscode /nix


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
RUN mkdir -p /home/vscode/.config/opencode/
COPY opencode.jsonc /home/vscode/.config/opencode/opencode.jsonc

CMD ["sleep", "infinity"]
