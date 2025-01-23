#!/bin/bash

# Set variables
REAL_SSH_PORT=2222
SSH_CONFIG_FILE="/etc/ssh/sshd_config"
PORTSPOOF_USER="portspoof"
PORTSPOOF_DIR="/home/$PORTSPOOF_USER/portspoof"

# Ensure script is run as root
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root. Exiting."
    exit 1
fi

# Update SSH to listen on a new port
echo "Updating SSH configuration to listen on port $REAL_SSH_PORT..."
if grep -q "^#Port" "$SSH_CONFIG_FILE"; then
    sed -i "s/^#Port.*/Port $REAL_SSH_PORT/" "$SSH_CONFIG_FILE"
elif grep -q "^Port" "$SSH_CONFIG_FILE"; then
    sed -i "s/^Port.*/Port $REAL_SSH_PORT/" "$SSH_CONFIG_FILE"
else
    echo "Port $REAL_SSH_PORT" >> "$SSH_CONFIG_FILE"
fi

# Disable PasswordAuthentication
echo "Disabling PasswordAuthentication in SSH..."
if grep -q "^#PasswordAuthentication" "$SSH_CONFIG_FILE"; then
    sed -i "s/^#PasswordAuthentication.*/PasswordAuthentication no/" "$SSH_CONFIG_FILE"
elif grep -q "^PasswordAuthentication" "$SSH_CONFIG_FILE"; then
    sed -i "s/^PasswordAuthentication.*/PasswordAuthentication no/" "$SSH_CONFIG_FILE"
else
    echo "PasswordAuthentication no" >> "$SSH_CONFIG_FILE"
fi

# Apply SSH configuration changes
echo "Restarting SSH service..."
systemctl daemon-reload
systemctl restart sshd

# Install Portspoof
echo "Installing Portspoof..."
apt update
apt install -y build-essential git

# Create Portspoof user
if ! id "$PORTSPOOF_USER" &>/dev/null; then
    adduser --system --home "/home/$PORTSPOOF_USER" --shell /bin/false $PORTSPOOF_USER
fi

# Clone and build Portspoof
if [ ! -d "$PORTSPOOF_DIR" ]; then
    mkdir -p "$PORTSPOOF_DIR"
    git clone https://github.com/drk1wi/portspoof.git "$PORTSPOOF_DIR"
    cd "$PORTSPOOF_DIR"
    ./configure && make && make install
else
    echo "Portspoof already installed. Skipping build."
fi

# Set ownership for Portspoof user
chown -R $PORTSPOOF_USER: "$PORTSPOOF_DIR"

# Set up iptables rules
echo "Setting up iptables rules..."
iptables -t nat -A PREROUTING -p tcp -m multiport ! --dports $REAL_SSH_PORT -j LOG --log-prefix "Pre-redirect scan attempt: "
iptables -t nat -A PREROUTING -p tcp -m multiport ! --dports $REAL_SSH_PORT -j REDIRECT --to-port 4444
iptables -A INPUT -p tcp --dport 1:65535 -m limit --limit 10/min -j LOG --log-prefix "Port scan attempt: "

# Save iptables rules
echo "Saving iptables rules..."
iptables-save > /etc/iptables/rules.v4

echo "Configuration complete. SSH is now listening on port $REAL_SSH_PORT, and Portspoof is set up."
