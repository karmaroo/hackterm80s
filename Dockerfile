# Godot 4.3 Development Container for HackTerm80s
FROM ubuntu:24.04

# Prevent interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Install dependencies for Godot and X11 forwarding
RUN apt-get update && apt-get install -y \
    wget \
    unzip \
    libgl1 \
    libgl1-mesa-dri \
    libx11-6 \
    libxcursor1 \
    libxinerama1 \
    libxrandr2 \
    libxi6 \
    libasound2t64 \
    libpulse0 \
    libfontconfig1 \
    libdbus-1-3 \
    ca-certificates \
    fontconfig \
    fonts-dejavu-core \
    && rm -rf /var/lib/apt/lists/*

# Set Godot version
ARG GODOT_VERSION=4.3
ARG GODOT_RELEASE=stable

# Download and install Godot
RUN wget -q https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-${GODOT_RELEASE}/Godot_v${GODOT_VERSION}-${GODOT_RELEASE}_linux.x86_64.zip \
    && unzip Godot_v${GODOT_VERSION}-${GODOT_RELEASE}_linux.x86_64.zip \
    && mv Godot_v${GODOT_VERSION}-${GODOT_RELEASE}_linux.x86_64 /usr/local/bin/godot \
    && chmod +x /usr/local/bin/godot \
    && rm Godot_v${GODOT_VERSION}-${GODOT_RELEASE}_linux.x86_64.zip

# Download export templates (for building releases)
RUN mkdir -p /root/.local/share/godot/export_templates/${GODOT_VERSION}.${GODOT_RELEASE} \
    && wget -q https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-${GODOT_RELEASE}/Godot_v${GODOT_VERSION}-${GODOT_RELEASE}_export_templates.tpz \
    && unzip Godot_v${GODOT_VERSION}-${GODOT_RELEASE}_export_templates.tpz \
    && mv templates/* /root/.local/share/godot/export_templates/${GODOT_VERSION}.${GODOT_RELEASE}/ \
    && rm -rf templates Godot_v${GODOT_VERSION}-${GODOT_RELEASE}_export_templates.tpz

# Create workspace directory
WORKDIR /game

# Set display for X11 forwarding
ENV DISPLAY=:0

# Default command - run Godot editor
CMD ["godot", "--editor", "--path", "/game"]
