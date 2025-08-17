#!/bin/bash
# =============================================================================
# 03-beegfs-storage.sh - Configuration du Storage Node avec BeeGFS
# =============================================================================
# Usage: bash 03-beegfs-storage.sh
# Description: Installe et configure BeeGFS Management, Metadata et Storage
# Prérequis: 00-base.sh doit avoir été exécuté
# =============================================================================

set -e  # Arrêt immédiat en cas d'erreur

# Variables globales
SCRIPT_NAME="[BEEGFS-STORAGE]"
LOG_FILE="/var/log/hpc-beegfs-storage.log"
BEEGFS_VERSION="7.4.4"
STORAGE_DEVICE="/dev/sdb"  # Disque dédié pour BeeGFS (peut être modifié)
STORAGE_MOUNT="/mnt/beegfs"
META_MOUNT="/mnt/beegfs-meta"

# Fonction de logging
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $SCRIPT_NAME $1" | tee -a "$LOG_FILE"
}

log "🚀 Début de la configuration BeeGFS Storage Node"

# =============================================================================
# 1. VÉRIFICATION DES PRÉREQUIS
# =============================================================================
log "🔍 Vérification des prérequis..."

if [ "$(id -u)" -ne 0 ]; then
    log "❌ Ce script doit être exécuté en tant que root"
    exit 1
fi

if [ "$(hostname)" != "hpc-storage-node" ] && [ "$(hostname)" != "storage-node" ]; then
    log "⚠️  Ce script est conçu pour le storage-node (hostname actuel: $(hostname))"
fi

# =============================================================================
# 2. PRÉPARATION DU STOCKAGE
# =============================================================================
log "💾 Préparation du système de stockage..."

# Créer des répertoires de stockage sur le disque système (si pas de disque dédié)
if [ ! -b "$STORAGE_DEVICE" ]; then
    log "⚠️  Disque dédié $STORAGE_DEVICE non trouvé, utilisation du disque système"
    
    # Créer les répertoires de stockage BeeGFS
    mkdir -p $STORAGE_MOUNT $META_MOUNT
    mkdir -p $STORAGE_MOUNT/chunks $META_MOUNT/metadata
    
    # Créer des répertoires pour simuler le stockage distribué
    mkdir -p /opt/hpc/storage/{ost1,ost2,ost3,ost4}
    mkdir -p /opt/hpc/metadata/mdt1
    
    log "✅ Répertoires de stockage créés sur le disque système"
else
    log "💽 Configuration du disque dédié $STORAGE_DEVICE..."
    
    # Partitionner et formater le disque dédié (ATTENTION: DESTRUCTIF!)
    log "⚠️  ATTENTION: Formatage du disque $STORAGE_DEVICE"
    
    # Créer une partition
    parted -s $STORAGE_DEVICE mklabel gpt
    parted -s $STORAGE_DEVICE mkpart primary ext4 0% 100%
    
    # Formater en ext4
    mkfs.ext4 -F ${STORAGE_DEVICE}1
    
    # Monter le disque
    mkdir -p $STORAGE_MOUNT
    mount ${STORAGE_DEVICE}1 $STORAGE_MOUNT
    
    # Ajouter à fstab pour montage automatique
    echo "${STORAGE_DEVICE}1 $STORAGE_MOUNT ext4 defaults 0 2" >> /etc/fstab
    
    # Créer les répertoires BeeGFS
    mkdir -p $STORAGE_MOUNT/chunks
    mkdir -p $META_MOUNT/metadata
    
    log "✅ Disque dédié configuré et monté"
fi

# Configuration des permissions
chown -R root:root $STORAGE_MOUNT $META_MOUNT
chmod -R 755 $STORAGE_MOUNT $META_MOUNT

# =============================================================================
# 3. INSTALLATION DE BEEGFS
# =============================================================================
log "📦 Installation de BeeGFS..."

export DEBIAN_FRONTEND=noninteractive

# Ajouter le repository BeeGFS
wget -qO - https://www.beegfs.io/release/beegfs_7.4.4/gpg/GPG-KEY-beegfs | apt-key add -
echo "deb [arch=amd64] https://www.beegfs.io/release/beegfs_7.4.4/dists/beegfs-jammy ./amd64/" > /etc/apt/sources.list.d/beegfs.list

apt-get update

# Installation des composants BeeGFS pour le storage node
apt-get install -y \
    beegfs-mgmtd \
    beegfs-meta \
    beegfs-storage \
    beegfs-client \
    beegfs-helperd \
    beegfs-utils \
    kernel-headers-$(uname -r) || apt-get install -y linux-headers-$(uname -r)

log "✅ BeeGFS installé"

# =============================================================================
# 4. CONFIGURATION DU SERVICE DE MANAGEMENT (MGMTD)
# =============================================================================
log "🎯 Configuration de BeeGFS Management Service..."

# Configuration du management daemon
cat > /etc/beegfs/beegfs-mgmtd.conf << 'EOF'
# BeeGFS Management Service Configuration

# Service Settings
sysMgmtdHost = 172.16.0.201
connPortShift = 0
connMgmtdPortTCP = 8008
connMgmtdPortUDP = 8008

# Storage Settings
storeMgmtdDirectory = /mnt/beegfs-mgmt
storeAllowFirstRunInit = true

# Network Settings
connInterfacesFile = /etc/beegfs/beegfs-mgmtd.interfaces
connNetFilterFile = /etc/beegfs/beegfs-mgmtd.netfilter

# Logging
logLevel = 3
logType = logfile
logNoDate = false
logStdFile = /var/log/beegfs-mgmtd.log

# Management Settings
runDaemonized = true
pidFile = /var/run/beegfs-mgmtd.pid

# Security
connDisableAuthentication = true
EOF

# Créer le répertoire de management
mkdir -p /mnt/beegfs-mgmt
chown root:root /mnt/beegfs-mgmt
chmod 755 /mnt/beegfs-mgmt

# Configuration des interfaces réseau
echo "172.16.0.201" > /etc/beegfs/beegfs-mgmtd.interfaces

# Initialiser le service de management
systemctl enable beegfs-mgmtd
systemctl start beegfs-mgmtd

sleep 3

if systemctl is-active --quiet beegfs-mgmtd; then
    log "✅ BeeGFS Management Service démarré"
else
    log "❌ Problème avec BeeGFS Management Service"
    systemctl status beegfs-mgmtd
    exit 1
fi

# =============================================================================
# 5. CONFIGURATION DU SERVICE DE MÉTADONNÉES (META)
# =============================================================================
log "📊 Configuration de BeeGFS Metadata Service..."

cat > /etc/beegfs/beegfs-meta.conf << 'EOF'
# BeeGFS Metadata Service Configuration

# Service Settings
sysMgmtdHost = 172.16.0.201
connPortShift = 0
connMetaPortTCP = 8005
connMetaPortUDP = 8005

# Storage Settings
storeMetaDirectory = /mnt/beegfs-meta/metadata
storeAllowFirstRunInit = true

# Network Settings
connInterfacesFile = /etc/beegfs/beegfs-meta.interfaces
connNetFilterFile = /etc/beegfs/beegfs-meta.netfilter

# Logging
logLevel = 3
logType = logfile
logNoDate = false
logStdFile = /var/log/beegfs-meta.log

# Performance Settings
tuneNumWorkers = 8
tuneMetaSpaceLowLimit = 10
tuneMetaSpaceEmergencyLimit = 3
tuneMetaInodesLowLimit = 10
tuneMetaInodesEmergencyLimit = 3

# Management Settings
runDaemonized = true
pidFile = /var/run/beegfs-meta.pid

# Security
connDisableAuthentication = true
EOF

# Créer le répertoire de métadonnées
mkdir -p /mnt/beegfs-meta/metadata
chown root:root /mnt/beegfs-meta/metadata
chmod 755 /mnt/beegfs-meta/metadata

# Configuration des interfaces réseau
echo "172.16.0.201" > /etc/beegfs/beegfs-meta.interfaces

# Initialiser le service de métadonnées
systemctl enable beegfs-meta
systemctl start beegfs-meta

sleep 3

if systemctl is-active --quiet beegfs-meta; then
    log "✅ BeeGFS Metadata Service démarré"
else
    log "❌ Problème avec BeeGFS Metadata Service"
    systemctl status beegfs-meta
    exit 1
fi

# =============================================================================
# 6. CONFIGURATION DU SERVICE DE STOCKAGE (STORAGE)
# =============================================================================
log "💾 Configuration de BeeGFS Storage Service..."

cat > /etc/beegfs/beegfs-storage.conf << 'EOF'
# BeeGFS Storage Service Configuration

# Service Settings
sysMgmtdHost = 172.16.0.201
connPortShift = 0
connStoragePortTCP = 8003
connStoragePortUDP = 8003

# Storage Settings
storeStorageDirectory = /mnt/beegfs/chunks
storeAllowFirstRunInit = true

# Network Settings
connInterfacesFile = /etc/beegfs/beegfs-storage.interfaces
connNetFilterFile = /etc/beegfs/beegfs-storage.netfilter

# Logging
logLevel = 3
logType = logfile
logNoDate = false
logStdFile = /var/log/beegfs-storage.log

# Performance Settings
tuneNumWorkers = 8
tuneFileReadAheadSize = 32m
tuneFileReadAheadTriggerSize = 20m
tuneFileWriteSize = 256k
tuneFileWriteSyncSize = 0
tuneWorkerBufSize = 4m

# Quota Settings
quotaQueryType = system
quotaQueryWithSystemUsersGroups = false

# Management Settings
runDaemonized = true
pidFile = /var/run/beegfs-storage.pid

# Security
connDisableAuthentication = true
EOF

# Créer le répertoire de stockage
mkdir -p /mnt/beegfs/chunks
chown root:root /mnt/beegfs/chunks
chmod 755 /mnt/beegfs/chunks

# Configuration des interfaces réseau
echo "172.16.0.201" > /etc/beegfs/beegfs-storage.interfaces

# Initialiser le service de stockage
systemctl enable beegfs-storage
systemctl start beegfs-storage

sleep 3

if systemctl is-active --quiet beegfs-storage; then
    log "✅ BeeGFS Storage Service démarré"
else
    log "❌ Problème avec BeeGFS Storage Service"
    systemctl status beegfs-storage
    exit 1
fi

# =============================================================================
# 7. CONFIGURATION DU CLIENT BEEGFS LOCAL
# =============================================================================
log "📂 Configuration du client BeeGFS local..."

cat > /etc/beegfs/beegfs-client.conf << 'EOF'
# BeeGFS Client Configuration

# Management Settings
sysMgmtdHost = 172.16.0.201
connPortShift = 0

# Mount Settings
connMgmtdPortTCP = 8008
connMgmtdPortUDP = 8008

# Network Settings
connInterfacesFile = /etc/beegfs/beegfs-client.interfaces
connNetFilterFile = /etc/beegfs/beegfs-client.netfilter

# Logging
logLevel = 3
logType = logfile
logNoDate = false
logStdFile = /var/log/beegfs-client.log

# Performance Settings
tuneFileCacheType = buffered
tunePagedIOBufSize = 64k
tunePagedIOBufNum = 16
tuneRemoteFSync = false
tunePreferredMetaFile = /etc/beegfs/beegfs-client.preferred-meta
tunePreferredStorageFile = /etc/beegfs/beegfs-client.preferred-storage

# Security
connDisableAuthentication = true
EOF

# Configuration des interfaces réseau pour le client
echo "172.16.0.201" > /etc/beegfs/beegfs-client.interfaces

# Créer le point de montage BeeGFS
mkdir -p /mnt/beegfs-client
chmod 755 /mnt/beegfs-client

# =============================================================================
# 8. CONFIGURATION DU HELPER DAEMON
# =============================================================================
log "🔧 Configuration de BeeGFS Helper Daemon..."

cat > /etc/beegfs/beegfs-helperd.conf << 'EOF'
# BeeGFS Helper Daemon Configuration

# Service Settings
connHelperdPortTCP = 8006

# Network Settings
connInterfacesFile = /etc/beegfs/beegfs-helperd.interfaces

# Logging
logLevel = 3
logType = logfile
logNoDate = false
logStdFile = /var/log/beegfs-helperd.log

# Management Settings
runDaemonized = true
pidFile = /var/run/beegfs-helperd.pid
EOF

echo "172.16.0.201" > /etc/beegfs/beegfs-helperd.interfaces

systemctl enable beegfs-helperd
systemctl start beegfs-helperd

# =============================================================================
# 9. MONTAGE DU SYSTÈME DE FICHIERS BEEGFS
# =============================================================================
log "🔗 Montage du système de fichiers BeeGFS..."

# Attendre que tous les services soient prêts
sleep 10

# Monter BeeGFS
if mount -t beegfs beegfs_nodev /mnt/beegfs-client; then
    log "✅ BeeGFS monté sur /mnt/beegfs-client"
    
    # Ajouter à fstab pour montage automatique
    if ! grep -q "beegfs_nodev /mnt/beegfs-client beegfs" /etc/fstab; then
        echo "beegfs_nodev /mnt/beegfs-client beegfs defaults,_netdev 0 0" >> /etc/fstab
    fi
    
    # Créer des répertoires de base
    mkdir -p /mnt/beegfs-client/{home,data,scratch,apps}
    chmod 755 /mnt/beegfs-client/{home,data,scratch,apps}
    
    # Créer un lien symbolique pour faciliter l'accès
    ln -sf /mnt/beegfs-client /beegfs
    
else
    log "❌ Échec du montage BeeGFS"
fi

# =============================================================================
# 10. CONFIGURATION DU FIREWALL
# =============================================================================
log "🔒 Configuration du firewall pour BeeGFS..."

# Ports BeeGFS
ufw allow 8003/tcp comment "BeeGFS Storage"
ufw allow 8003/udp comment "BeeGFS Storage"
ufw allow 8005/tcp comment "BeeGFS Metadata"
ufw allow 8005/udp comment "BeeGFS Metadata"
ufw allow 8006/tcp comment "BeeGFS Helper"
ufw allow 8008/tcp comment "BeeGFS Management"
ufw allow 8008/udp comment "BeeGFS Management"

# Port pour monitoring
ufw allow 8080/tcp comment "BeeGFS Web Interface"

# =============================================================================
# 11. SCRIPTS ET OUTILS DE GESTION
# =============================================================================
log "🔧 Installation d'outils de gestion BeeGFS..."

mkdir -p /opt/hpc/bin

# Script de status BeeGFS
cat > /opt/hpc/bin/beegfs-status << 'EOF'
#!/bin/bash
echo "=== STATUT BEEGFS STORAGE NODE ==="
echo
echo "Services BeeGFS:"
systemctl status beegfs-mgmtd beegfs-meta beegfs-storage beegfs-helperd --no-pager -l
echo
echo "Nœuds du cluster BeeGFS:"
beegfs-ctl --listnodes --nodetype=mgmt
beegfs-ctl --listnodes --nodetype=meta
beegfs-ctl --listnodes --nodetype=storage
echo
echo "Pools de stockage:"
beegfs-ctl --liststoragepools
echo
echo "Informations sur le système de fichiers:"
beegfs-ctl --getentryinfo /mnt/beegfs-client
echo
echo "Statistiques de performance:"
beegfs-ctl --serverstats --nodetype=storage
beegfs-ctl --serverstats --nodetype=meta
echo
echo "Espace disque:"
df -h /mnt/beegfs /mnt/beegfs-meta /mnt/beegfs-client 2>/dev/null
EOF

chmod +x /opt/hpc/bin/beegfs-status

# Script de monitoring BeeGFS
cat > /opt/hpc/bin/beegfs-monitor << 'EOF'
#!/bin/bash
while true; do
    clear
    echo "=== MONITORING BEEGFS - $(date) ==="
    echo
    echo "Connexions actives:"
    beegfs-ctl --clientstats
    echo
    echo "Performance I/O:"
    beegfs-ctl --serverstats --nodetype=storage --interval=5
    echo
    echo "Utilisation disque:"
    df -h /mnt/beegfs /mnt/beegfs-meta /mnt/beegfs-client 2>/dev/null
    echo
    sleep 10
done
EOF

chmod +x /opt/hpc/bin/beegfs-monitor

# Script de test de performance
cat > /opt/hpc/bin/beegfs-test << 'EOF'
#!/bin/bash
echo "=== TEST DE PERFORMANCE BEEGFS ==="
echo
TEST_DIR="/mnt/beegfs-client/test-$(date +%s)"
mkdir -p $TEST_DIR

echo "Test d'écriture..."
time dd if=/dev/zero of=$TEST_DIR/testfile bs=1M count=1000 2>&1

echo
echo "Test de lecture..."
time dd if=$TEST_DIR/testfile of=/dev/null bs=1M 2>&1

echo
echo "Test de suppression..."
time rm -f $TEST_DIR/testfile
rmdir $TEST_DIR

echo
echo "Test terminé"
EOF

chmod +x /opt/hpc/bin/beegfs-test

# Script de sauvegarde de configuration
cat > /opt/hpc/bin/beegfs-backup-config << 'EOF'
#!/bin/bash
BACKUP_DIR="/opt/hpc/backups/beegfs-$(date +%Y%m%d-%H%M%S)"
mkdir -p $BACKUP_DIR

echo "Sauvegarde de la configuration BeeGFS..."
cp -r /etc/beegfs $BACKUP_DIR/
cp /etc/fstab $BACKUP_DIR/
tar -czf $BACKUP_DIR/beegfs-data.tar.gz /mnt/beegfs-mgmt /mnt/beegfs-meta/metadata 2>/dev/null

echo "Configuration sauvegardée dans $BACKUP_DIR"
EOF

chmod +x /opt/hpc/bin/beegfs-backup-config

# =============================================================================
# 12. CONFIGURATION DES LOGS ET MONITORING
# =============================================================================
log "📊 Configuration des logs et monitoring..."

# Rotation des logs BeeGFS
cat > /etc/logrotate.d/beegfs << 'EOF'
/var/log/beegfs-*.log {
    daily
    missingok
    rotate 30
    compress
    delaycompress
    notifempty
    create 0644 root root
    postrotate
        systemctl reload beegfs-mgmtd beegfs-meta beegfs-storage beegfs-helperd 2>/dev/null || true
    endscript
}
EOF

# Configuration de monitoring avec netdata pour BeeGFS
if [ -f /etc/netdata/netdata.conf ]; then
    mkdir -p /etc/netdata/python.d
    
    cat > /etc/netdata/python.d/beegfs.conf << 'EOF'
beegfs:
    name: 'beegfs'
    update_every: 5
    priority: 60000
    charts:
        beegfs.storage_stats:
            options: [null, 'BeeGFS Storage Statistics', 'operations/s', 'beegfs', 'beegfs.storage', 'line']
            lines: [
                ['read_ops', 'read ops', 'incremental'],
                ['write_ops', 'write ops', 'incremental']
            ]
EOF
    
    systemctl restart netdata
fi

# =============================================================================
# 13. TESTS FINAUX
# =============================================================================
log "🧪 Tests de fonctionnement..."

# Test des services BeeGFS
SERVICES=("beegfs-mgmtd" "beegfs-meta" "beegfs-storage" "beegfs-helperd")
for service in "${SERVICES[@]}"; do
    if systemctl is-active --quiet $service; then
        log "✅ $service: OK"
    else
        log "❌ $service: ÉCHEC"
    fi
done

# Test du montage BeeGFS
if mountpoint -q /mnt/beegfs-client; then
    log "✅ Montage BeeGFS: OK"
    
    # Test d'écriture/lecture
    if echo "Test BeeGFS" > /mnt/beegfs-client/test.txt && [ -f /mnt/beegfs-client/test.txt ]; then
        log "✅ Test écriture/lecture: OK"
        rm -f /mnt/beegfs-client/test.txt
    else
        log "❌ Test écriture/lecture: ÉCHEC"
    fi
else
    log "❌ Montage BeeGFS: ÉCHEC"
fi

# Afficher les informations du cluster
if command -v beegfs-ctl &> /dev/null; then
    log "📊 Informations du cluster BeeGFS:"
    beegfs-ctl --listnodes --nodetype=mgmt
    beegfs-ctl --listnodes --nodetype=meta  
    beegfs-ctl --listnodes --nodetype=storage
fi

# =============================================================================
# 14. INFORMATIONS FINALES
# =============================================================================
log "✅ Configuration BeeGFS Storage Node terminée avec succès!"

cat << EOF

=============================================================================
🎉 BEEGFS STORAGE NODE CONFIGURÉ AVEC SUCCÈS
=============================================================================

📍 Storage Node: $(hostname)
🌐 IP: 172.16.0.201
💾 Stockage: $STORAGE_MOUNT/chunks
📊 Métadonnées: $META_MOUNT/metadata
🔗 Point de montage: /mnt/beegfs-client

✅ BeeGFS Management Service (port 8008)
✅ BeeGFS Metadata Service (port 8005)  
✅ BeeGFS Storage Service (port 8003)
✅ BeeGFS Helper Daemon (port 8006)
✅ Client BeeGFS monté
✅ Firewall configuré

🔧 COMMANDES UTILES:
   - Status complet: /opt/hpc/bin/beegfs-status
   - Monitoring: /opt/hpc/bin/beegfs-monitor
   - Test performance: /opt/hpc/bin/beegfs-test
   - Sauvegarde config: /opt/hpc/bin/beegfs-backup-config
   - Lister nœuds: beegfs-ctl --listnodes
   - Stats serveur: beegfs-ctl --serverstats

📂 RÉPERTOIRES BEEGFS:
   - /mnt/beegfs-client/home   - Répertoires utilisateurs
   - /mnt/beegfs-client/data   - Données partagées
   - /mnt/beegfs-client/scratch - Espace temporaire
   - /mnt/beegfs-client/apps   - Applications partagées
   - /beegfs -> /mnt/beegfs-client (lien symbolique)

📊 MONITORING:
   - Netdata: http://172.16.0.201:19999
   - Logs BeeGFS: /var/log/beegfs-*.log

🔗 PROCHAINES ÉTAPES:
   1. Installer le client BeeGFS sur tous les nœuds: bash 04-beegfs-client.sh
   2. Configurer les GPU nodes: bash 05-gpu.sh
   3. Tester l'accès depuis les compute nodes

⚠️  NOTES:
   - Le système de fichiers BeeGFS est maintenant disponible
   - Les clients doivent être configurés pour accéder au stockage
   - Sauvegarder régulièrement la configuration

🔧 EXEMPLE D'UTILISATION:
   cd /mnt/beegfs-client
   mkdir mon-projet
   echo "Hello BeeGFS" > mon-projet/test.txt

=============================================================================
EOF

log "🏁 Script 03-beegfs-storage.sh terminé"
