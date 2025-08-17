#!/bin/bash
# =============================================================================
# 04-beegfs-client.sh - Installation du client BeeGFS sur les nœuds
# =============================================================================
# Usage: bash 04-beegfs-client.sh
# Description: Installe et configure le client BeeGFS sur tous les nœuds
# Prérequis: 00-base.sh et 03-beegfs-storage.sh (sur storage-node)
# =============================================================================

set -e

SCRIPT_NAME="[BEEGFS-CLIENT]"
LOG_FILE="/var/log/hpc-beegfs-client.log"
STORAGE_NODE="172.16.0.201"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $SCRIPT_NAME $1" | tee -a "$LOG_FILE"
}

log "🚀 Installation du client BeeGFS"

# =============================================================================
# INSTALLATION ET CONFIGURATION
# =============================================================================
log "📦 Installation du client BeeGFS..."

export DEBIAN_FRONTEND=noninteractive

# Ajouter le repository BeeGFS
wget -qO - https://www.beegfs.io/release/beegfs_7.4.4/gpg/GPG-KEY-beegfs | apt-key add -
echo "deb [arch=amd64] https://www.beegfs.io/release/beegfs_7.4.4/dists/beegfs-jammy ./amd64/" > /etc/apt/sources.list.d/beegfs.list

apt-get update
apt-get install -y beegfs-client beegfs-helperd beegfs-utils linux-headers-$(uname -r)

# Configuration du client
cat > /etc/beegfs/beegfs-client.conf << EOF
sysMgmtdHost = $STORAGE_NODE
connMgmtdPortTCP = 8008
connMgmtdPortUDP = 8008
connInterfacesFile = /etc/beegfs/beegfs-client.interfaces
logStdFile = /var/log/beegfs-client.log
connDisableAuthentication = true
EOF

echo "$(hostname -I | awk '{print $1}')" > /etc/beegfs/beegfs-client.interfaces

# Point de montage
mkdir -p /mnt/beegfs
chmod 755 /mnt/beegfs

# Helper daemon
cat > /etc/beegfs/beegfs-helperd.conf << EOF
connHelperdPortTCP = 8006
connInterfacesFile = /etc/beegfs/beegfs-helperd.interfaces
logStdFile = /var/log/beegfs-helperd.log
EOF

echo "$(hostname -I | awk '{print $1}')" > /etc/beegfs/beegfs-helperd.interfaces

# Démarrage des services
systemctl enable beegfs-helperd beegfs-client
systemctl start beegfs-helperd
sleep 2
systemctl start beegfs-client

# Test de montage
sleep 5
if mount -t beegfs beegfs_nodev /mnt/beegfs; then
    log "✅ BeeGFS monté avec succès"
    echo "beegfs_nodev /mnt/beegfs beegfs defaults,_netdev 0 0" >> /etc/fstab
    ln -sf /mnt/beegfs /beegfs
else
    log "❌ Échec du montage BeeGFS"
fi

# Firewall
ufw allow 8006/tcp comment "BeeGFS Helper"

log "✅ Client BeeGFS configuré sur $(hostname)"
