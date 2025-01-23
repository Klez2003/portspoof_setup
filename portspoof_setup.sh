#!/bin/bash

# Set variables
REAL_SSH_PORT=2222
SSH_CONFIG_FILE="/etc/ssh/sshd_config"

# Update SSH to listen on a new port
echo "Updating SSH configuration to listen on port $REAL_SSH_PORT..."
if grep -q "^#Port" "$SSH_CONFIG_FILE"; then
    sed -i "s/^#Port.*/Port $REAL_SSH_PORT/" "$SSH_CONFIG_FILE"
else
    echo "Port $REAL_SSH_PORT" >> "$SSH_CONFIG_FILE"
fi

# Disable PasswordAuthentication
if grep -q "^#PasswordAuthentication" "$SSH_CONFIG_FILE"; then
    sed -i "s/^#PasswordAuthentication.*/PasswordAuthentication no/" "$SSH_CONFIG_FILE"
elif grep -q "^PasswordAuthentication" "$SSH_CONFIG_FILE"; then
    sed -i "s/^PasswordAuthentication.*/PasswordAuthentication no/" "$SSH_CONFIG_FILE"
else
    echo "PasswordAuthentication no" >> "$SSH_CONFIG_FILE"
fi

# Apply changes
systemctl daemon-reload
systemctl restart ssh.socket
systemctl restart ssh

# Install Portspoof
sudo apt install -y build-essential
sudo adduser portspoof
cd /home/portspoof
git clone https://github.com/drk1wi/portspoof.git
cd portspoof
./configure; make; make install


# Log attempts before redirection (in PREROUTING)
sudo iptables -t nat -A PREROUTING -p tcp -m multiport ! --dports 2222 -j LOG --log-prefix "Pre-redirect scan attempt: "

# Redirect traffic (in PREROUTING)
sudo iptables -t nat -A PREROUTING -p tcp -m multiport ! --dports 2222 -j REDIRECT --to-port 4444

# Log remaining traffic (in INPUT)
sudo iptables -A INPUT -p tcp --dport 1:65535 -m limit --limit 10/min -j LOG --log-prefix "Port scan attempt: "


## Switch to Portspoof user after redirection
chown -R portspoof: /home/portspoof/portspoof/
su - portspoof;