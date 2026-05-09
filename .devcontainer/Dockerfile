FROM docker.io/library/debian:bullseye-20260112-slim

RUN apt-get update && \
    apt-get install -y curl ca-certificates procps iproute2 util-linux dnsutils netcat-openbsd git jq vim fish && \
    # Create the vscode user
    useradd -m vscode && \
    # [Optional] Add sudo support
    apt-get install -y sudo && \
    echo vscode ALL=\(root\) NOPASSWD:ALL > /etc/sudoers.d/vscode && \
    chmod 0440 /etc/sudoers.d/vscode

RUN curl -sSfL https://artifacts.nixos.org/nix-installer | sh -s -- install linux \
    --extra-conf "sandbox = false" --enable-flakes --init none --no-confirm && \
    sudo chown -R vscode /nix

ENV PATH="${PATH}:/nix/var/nix/profiles/default/bin"
# Set the default user for the image
USER vscode
WORKDIR /setup

# 1. Create a setup directory and copy flake files
COPY flake.nix /setup/

# 2. Install packages from the flake
RUN nix profile add . && \
    nix-store --gc && \
    nix-collect-garbage -d

ENV PATH="/home/vscode/.nix-profile/bin:${PATH}"

# CMD ["sleep", "infinity"]
ENTRYPOINT ["opencode", "serve"]