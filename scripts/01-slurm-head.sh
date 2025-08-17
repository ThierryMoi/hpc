#!/bin/bash
# =============================================================================
# 01-slurm-head.sh - Configuration du Head-node avec Slurm Controller
# =============================================================================
# Usage: bash 01-slurm-head.sh
# Description: Installe et configure Slurm Controller sur le head-node
# Prérequis: 00-base.sh doit avoir été exécuté
# =============================================================================

set -e  # Arrêt immédiat en cas d'erreur

# Variables globales
SCRIPT_NAME="[SLURM-HEAD]"
LOG_FILE="/var/log/hpc-slurm-head.log"
SLURM_VERSION="23.02"
SLURM_UID=2001
SLURM_GID=2001

# Fonction de logging
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $SCRIPT_NAME $1" | tee -a "$LOG_FILE"
}

log "🚀 Début de la configuration Slurm Head-node"

# =============================================================================
# 1. VÉRIFICATION DES PRÉREQUIS
# =============================================================================
log "🔍 Vérification des prérequis..."

if [ "$(id -u)" -ne 0 ]; then
    log "❌ Ce script doit être exécuté en tant que root"
    exit 1
fi

if [ "$(hostname)" != "hpc-head-node" ] && [ "$(hostname)" != "head-node" ]; then
    log "⚠️  Ce script est conçu pour le head-node (hostname actuel: $(hostname))"
fi

# =============================================================================
# 2. INSTALLATION DES DÉPENDANCES
# =============================================================================
log "📦 Installation des dépendances Slurm..."

export DEBIAN_FRONTEND=noninteractive
apt-get update

# Packages nécessaires pour Slurm
apt-get install -y \
    mariadb-server \
    mariadb-client \
    munge \
    libmunge-dev \
    libmunge2 \
    slurm-wlm \
    slurm-wlm-basic-plugins \
    slurmdbd \
    slurm-client \
    mailutils \
    ntp \
    ntpdate \
    chrony \
    libpam-slurm \
    libslurm-dev \
    python3-pip \
    python3-dev

# =============================================================================
# 3. CONFIGURATION DE LA BASE DE DONNÉES MARIADB
# =============================================================================
log "🗄️  Configuration de MariaDB pour SlurmDBD..."

# Démarrer MariaDB
systemctl start mariadb
systemctl enable mariadb

# Sécurisation de MariaDB
mysql -u root << 'EOSQL'
-- Sécurisation de MariaDB
UPDATE mysql.user SET Password=PASSWORD('SlurmDB2025!') WHERE User='root';
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';

-- Création de la base de données Slurm
CREATE DATABASE IF NOT EXISTS slurm_acct_db;
CREATE USER IF NOT EXISTS 'slurm'@'localhost' IDENTIFIED BY 'SlurmDB2025!';
GRANT ALL PRIVILEGES ON slurm_acct_db.* TO 'slurm'@'localhost';
FLUSH PRIVILEGES;
EOSQL

log "✅ MariaDB configurée pour Slurm"

# =============================================================================
# 4. CONFIGURATION DE MUNGE (AUTHENTIFICATION)
# =============================================================================
log "🔐 Configuration de Munge pour l'authentification..."

# Création du groupe et utilisateur munge
if ! getent group munge > /dev/null 2>&1; then
    groupadd -g 997 munge
fi

if ! id "munge" &>/dev/null; then
    useradd -u 997 -g munge -d /var/lib/munge -s /sbin/nologin munge
fi

# Génération de la clé Munge (partagée avec tous les nœuds)
if [ ! -f /etc/munge/munge.key ]; then
    dd if=/dev/urandom bs=1 count=1024 > /etc/munge/munge.key
    chown munge:munge /etc/munge/munge.key
    chmod 400 /etc/munge/munge.key
    log "✅ Clé Munge générée"
else
    log "✅ Clé Munge existante trouvée"
fi

# Configuration des permissions
chown -R munge:munge /etc/munge /var/lib/munge /var/log/munge /run/munge
chmod 700 /etc/munge /var/lib/munge /var/log/munge
chmod 755 /run/munge

# Démarrage de Munge
systemctl enable munge
systemctl start munge

# Test de Munge
sleep 2
if munge -n | unmunge; then
    log "✅ Munge fonctionne correctement"
else
    log "❌ Problème avec Munge"
    exit 1
fi

# =============================================================================
# 5. CRÉATION DE L'UTILISATEUR SLURM
# =============================================================================
log "👤 Configuration de l'utilisateur Slurm..."

# Création du groupe et utilisateur slurm
if ! getent group slurm > /dev/null 2>&1; then
    groupadd -g $SLURM_GID slurm
fi

if ! id "slurm" &>/dev/null; then
    useradd -u $SLURM_UID -g slurm -d /var/lib/slurm -s /bin/bash slurm
fi

# Création des répertoires Slurm
mkdir -p /var/spool/slurm /var/log/slurm /etc/slurm /var/lib/slurm
chown -R slurm:slurm /var/spool/slurm /var/log/slurm /var/lib/slurm
chmod 755 /var/spool/slurm /var/log/slurm /var/lib/slurm

# =============================================================================
# 6. CONFIGURATION DE SLURMDBD
# =============================================================================
log "📊 Configuration de SlurmDBD..."

cat > /etc/slurm/slurmdbd.conf << 'EOF'
#
# Slurm Database Daemon Configuration
#
AuthType=auth/munge
AuthInfo=/var/run/munge/munge.socket.2

# Database info
DbdAddr=172.16.0.200
DbdHost=hpc-head-node
DbdPort=6819
SlurmUser=slurm

# Database
StorageType=accounting_storage/mysql
StorageHost=localhost
StoragePort=3306
StoragePass=SlurmDB2025!
StorageUser=slurm
StorageLoc=slurm_acct_db

# Logging
LogFile=/var/log/slurm/slurmdbd.log
PidFile=/var/run/slurm/slurmdbd.pid

# Archive des jobs
ArchiveEvents=yes
ArchiveJobs=yes
ArchiveResvs=yes
ArchiveSteps=yes
ArchiveSuspend=no

# Purge automatique (garder 1 an)
PurgeEventAfter=365days
PurgeJobAfter=365days
PurgeResvAfter=365days
PurgeStepAfter=365days
PurgeSuspendAfter=365days
EOF

chown slurm:slurm /etc/slurm/slurmdbd.conf
chmod 600 /etc/slurm/slurmdbd.conf

# =============================================================================
# 7. CONFIGURATION DE SLURM.CONF
# =============================================================================
log "⚙️  Configuration de Slurm Controller..."

cat > /etc/slurm/slurm.conf << 'EOF'
#
# Configuration Slurm pour Cluster HPC
# Version: 23.02
#

# CONTROLLER
ClusterName=hpc-cluster
ControlMachine=hpc-head-node
ControlAddr=172.16.0.200
BackupController=
BackupAddr=

# DATABASE
AccountingStorageType=accounting_storage/slurmdbd
AccountingStorageHost=172.16.0.200
AccountingStoragePort=6819
JobAcctGatherType=jobacct_gather/linux
JobAcctGatherFrequency=30

# SCHEDULING
SchedulerType=sched/backfill
SelectType=select/cons_tres
SelectTypeParameters=CR_Core_Memory

# FAIRSHARE
PriorityType=priority/multifactor
PriorityDecayHalfLife=7-0
PriorityFavorSmall=NO
PriorityMaxAge=7-0
PriorityUsageResetPeriod=NONE
PriorityWeightAge=1000
PriorityWeightFairshare=10000
PriorityWeightJobSize=1000
PriorityWeightPartition=10000
PriorityWeightQOS=10000

# LIMITS
DefMemPerCPU=4096
MaxJobCount=10000
MaxStepCount=40000
MaxTasksPerNode=128
MaxSubmitJobs=1000

# TIMEOUTS
SlurmctldTimeout=120
SlurmdTimeout=300
InactiveLimit=0
KillWait=30
MinJobAge=300
Waittime=0

# LOGGING
SlurmctldDebug=info
SlurmctldLogFile=/var/log/slurm/slurmctld.log
SlurmdDebug=info
SlurmdLogFile=/var/log/slurm/slurmd.log
SlurmdSpoolDir=/var/spool/slurm/slurmd

# PATHS
SlurmdPidFile=/var/run/slurm/slurmd.pid
SlurmctldPidFile=/var/run/slurm/slurmctld.pid
StateSaveLocation=/var/lib/slurm/slurmctld

# AUTHENTIFICATION
AuthType=auth/munge
AuthInfo=/var/run/munge/munge.socket.2

# NETWORK
SlurmctldPort=6817
SlurmdPort=6818

# MPI
MpiDefault=pmix_v4
MpiParams=ports=12000-12999

# PROCESS TRACKING
ProctrackType=proctrack/cgroup
TaskPlugin=task/cgroup

# RESOURCES
GresTypes=gpu
TreeWidth=50

# CGROUP
CgroupMountpoint="/sys/fs/cgroup"
CgroupAutomount=yes
CgroupReleaseAgentDir="/etc/slurm/cgroup"
ConstrainCores=yes
ConstrainRAMSpace=yes
ConstrainSwapSpace=yes
ConstrainDevices=yes

#
# NODES CONFIGURATION
#

# COMPUTE NODES (8 nodes, 16 cores, 64GB RAM each)
NodeName=hpc-compute-01 NodeAddr=172.16.0.202 CPUs=16 RealMemory=64000 Sockets=2 CoresPerSocket=8 ThreadsPerCore=1 State=UNKNOWN
NodeName=hpc-compute-02 NodeAddr=172.16.0.203 CPUs=16 RealMemory=64000 Sockets=2 CoresPerSocket=8 ThreadsPerCore=1 State=UNKNOWN
NodeName=hpc-compute-03 NodeAddr=172.16.0.204 CPUs=16 RealMemory=64000 Sockets=2 CoresPerSocket=8 ThreadsPerCore=1 State=UNKNOWN
NodeName=hpc-compute-04 NodeAddr=172.16.0.205 CPUs=16 RealMemory=64000 Sockets=2 CoresPerSocket=8 ThreadsPerCore=1 State=UNKNOWN
NodeName=hpc-compute-05 NodeAddr=172.16.0.206 CPUs=16 RealMemory=64000 Sockets=2 CoresPerSocket=8 ThreadsPerCore=1 State=UNKNOWN
NodeName=hpc-compute-06 NodeAddr=172.16.0.207 CPUs=16 RealMemory=64000 Sockets=2 CoresPerSocket=8 ThreadsPerCore=1 State=UNKNOWN
NodeName=hpc-compute-07 NodeAddr=172.16.0.208 CPUs=16 RealMemory=64000 Sockets=2 CoresPerSocket=8 ThreadsPerCore=1 State=UNKNOWN
NodeName=hpc-compute-08 NodeAddr=172.16.0.209 CPUs=16 RealMemory=64000 Sockets=2 CoresPerSocket=8 ThreadsPerCore=1 State=UNKNOWN

# GPU NODES (2 nodes, 32 cores, 128GB RAM, 4 GPUs each)
NodeName=hpc-gpu-01 NodeAddr=172.16.0.210 CPUs=32 RealMemory=128000 Sockets=2 CoresPerSocket=16 ThreadsPerCore=1 Gres=gpu:4 State=UNKNOWN
NodeName=hpc-gpu-02 NodeAddr=172.16.0.211 CPUs=32 RealMemory=128000 Sockets=2 CoresPerSocket=16 ThreadsPerCore=1 Gres=gpu:4 State=UNKNOWN

#
# PARTITIONS CONFIGURATION
#

# Partition pour calcul standard
PartitionName=compute Nodes=hpc-compute-[01-08] Default=YES MaxTime=7-00:00:00 State=UP
PartitionName=compute AllowGroups=hpc,users PriorityJobFactor=1

# Partition pour calcul GPU
PartitionName=gpu Nodes=hpc-gpu-[01-02] Default=NO MaxTime=3-00:00:00 State=UP
PartitionName=gpu AllowGroups=hpc,users PriorityJobFactor=2

# Partition debug (temps court)
PartitionName=debug Nodes=hpc-compute-[01-02] Default=NO MaxTime=01:00:00 State=UP MaxNodes=2
PartitionName=debug AllowGroups=hpc,users PriorityJobFactor=10

# Partition longue durée
PartitionName=long Nodes=hpc-compute-[03-04] Default=NO MaxTime=14-00:00:00 State=UP
PartitionName=long AllowGroups=hpc,users PriorityJobFactor=0.5
EOF

chown slurm:slurm /etc/slurm/slurm.conf
chmod 644 /etc/slurm/slurm.conf

# =============================================================================
# 8. CONFIGURATION DES CGROUPS
# =============================================================================
log "🔧 Configuration des CGroups..."

cat > /etc/slurm/cgroup.conf << 'EOF'
#
# Configuration CGroup pour Slurm
#
CgroupMountpoint="/sys/fs/cgroup"
CgroupAutomount=yes
CgroupReleaseAgentDir="/etc/slurm/cgroup"

# Constraindre les ressources
ConstrainCores=yes
ConstrainDevices=yes
ConstrainRAMSpace=yes
ConstrainSwapSpace=yes

# Configuration des devices
AllowedDevicesFile="/etc/slurm/cgroup_allowed_devices_file.conf"
EOF

# Fichier des devices autorisés
cat > /etc/slurm/cgroup_allowed_devices_file.conf << 'EOF'
/dev/null
/dev/urandom
/dev/zero
/dev/sda*
/dev/cpu/*/*
/dev/pts/*
/dev/nvidia*
/dev/dri/*
EOF

chown slurm:slurm /etc/slurm/cgroup.conf /etc/slurm/cgroup_allowed_devices_file.conf
chmod 644 /etc/slurm/cgroup.conf /etc/slurm/cgroup_allowed_devices_file.conf

# =============================================================================
# 9. CONFIGURATION DES GRES (GPU)
# =============================================================================
log "🎮 Configuration des GPU Resources..."

cat > /etc/slurm/gres.conf << 'EOF'
#
# Configuration des Generic Resources (GPU)
#

# Configuration automatique des GPU NVIDIA
AutoDetect=nvml

# Configuration manuelle pour les nodes GPU
# NodeName=hpc-gpu-01 Name=gpu Type=nvidia File=/dev/nvidia[0-3]
# NodeName=hpc-gpu-02 Name=gpu Type=nvidia File=/dev/nvidia[0-3]
EOF

chown slurm:slurm /etc/slurm/gres.conf
chmod 644 /etc/slurm/gres.conf

# =============================================================================
# 10. CONFIGURATION DES SERVICES SYSTEMD
# =============================================================================
log "🔄 Configuration des services systemd..."

# Service slurmdbd
cat > /etc/systemd/system/slurmdbd.service << 'EOF'
[Unit]
Description=Slurm Database Daemon
After=network.target mariadb.service munge.service
Requires=mariadb.service munge.service

[Service]
Type=notify
User=slurm
Group=slurm
ExecStart=/usr/sbin/slurmdbd -D
ExecReload=/bin/kill -HUP $MAINPID
PIDFile=/var/run/slurm/slurmdbd.pid
LimitNOFILE=65536
TasksMax=infinity

[Install]
WantedBy=multi-user.target
EOF

# Service slurmctld
cat > /etc/systemd/system/slurmctld.service << 'EOF'
[Unit]
Description=Slurm Controller Daemon
After=network.target munge.service slurmdbd.service
Requires=munge.service

[Service]
Type=notify
User=slurm
Group=slurm
ExecStart=/usr/sbin/slurmctld -D
ExecReload=/bin/kill -HUP $MAINPID
PIDFile=/var/run/slurm/slurmctld.pid
LimitNOFILE=65536
TasksMax=infinity

[Install]
WantedBy=multi-user.target
EOF

# Recharger systemd
systemctl daemon-reload

# =============================================================================
# 11. DÉMARRAGE DES SERVICES
# =============================================================================
log "🚀 Démarrage des services Slurm..."

# Démarrer SlurmDBD d'abord
systemctl enable slurmdbd
systemctl start slurmdbd

# Attendre que SlurmDBD soit prêt
sleep 5

# Vérifier que SlurmDBD fonctionne
if systemctl is-active --quiet slurmdbd; then
    log "✅ SlurmDBD démarré avec succès"
else
    log "❌ Problème avec SlurmDBD"
    systemctl status slurmdbd
    exit 1
fi

# Démarrer SlurmCtld
systemctl enable slurmctld
systemctl start slurmctld

# Attendre que SlurmCtld soit prêt
sleep 5

# Vérifier que SlurmCtld fonctionne
if systemctl is-active --quiet slurmctld; then
    log "✅ SlurmCtld démarré avec succès"
else
    log "❌ Problème avec SlurmCtld"
    systemctl status slurmctld
    exit 1
fi

# =============================================================================
# 12. CONFIGURATION DU CLUSTER DANS SLURM
# =============================================================================
log "🏗️  Configuration du cluster dans la base de données..."

# Attendre que les services soient complètement initialisés
sleep 10

# Ajouter le cluster s'il n'existe pas
if ! sacctmgr -n list cluster | grep -q "hpc-cluster"; then
    sacctmgr -i add cluster Name=hpc-cluster
    log "✅ Cluster hpc-cluster ajouté"
fi

# Ajouter un compte par défaut
if ! sacctmgr -n list account | grep -q "default"; then
    sacctmgr -i add account default Cluster=hpc-cluster Description="Compte par défaut"
    log "✅ Compte default ajouté"
fi

# Ajouter l'utilisateur hpc
if ! sacctmgr -n list user | grep -q "hpc"; then
    sacctmgr -i add user hpc DefaultAccount=default Cluster=hpc-cluster
    log "✅ Utilisateur hpc ajouté"
fi

# =============================================================================
# 13. SCRIPTS ET OUTILS UTILES
# =============================================================================
log "🔧 Installation d'outils de gestion..."

# Script de status du cluster
cat > /opt/hpc/bin/cluster-status << 'EOF'
#!/bin/bash
echo "=== STATUT DU CLUSTER HPC ==="
echo
echo "Services Slurm:"
systemctl status munge slurmctld slurmdbd --no-pager -l
echo
echo "Noeuds du cluster:"
sinfo -N -l
echo
echo "Jobs en cours:"
squeue
echo
echo "Utilisation des partitions:"
sinfo -s
echo
echo "Comptes et utilisateurs:"
sacctmgr list associations format=User,Account,Cluster,QOS,Partition
EOF

chmod +x /opt/hpc/bin/cluster-status

# Script de monitoring des resources
cat > /opt/hpc/bin/cluster-monitor << 'EOF'
#!/bin/bash
while true; do
    clear
    echo "=== MONITORING CLUSTER HPC - $(date) ==="
    echo
    sinfo -p compute,gpu --format="%.20P %.5a %.10l %.6D %.6t %.8C %.8G %.10m %.30N"
    echo
    echo "Jobs actifs:"
    squeue --format="%.10i %.12u %.10P %.10T %.8M %.6D %.30j"
    echo
    sleep 30
done
EOF

chmod +x /opt/hpc/bin/cluster-monitor

# =============================================================================
# 14. CONFIGURATION DU FIREWALL
# =============================================================================
log "🔒 Configuration du firewall pour Slurm..."

# Ports Slurm
ufw allow 6817/tcp comment "SlurmCtld"
ufw allow 6818/tcp comment "SlurmdD"
ufw allow 6819/tcp comment "SlurmDBD"
ufw allow 7321/tcp comment "Slurm srun"
ufw allow 60001:63000/tcp comment "Slurm communication range"

# Ports MPI
ufw allow 12000:12999/tcp comment "MPI communication"

# =============================================================================
# 15. SAUVEGARDE DE LA CLÉ MUNGE
# =============================================================================
log "💾 Sauvegarde de la clé Munge..."

# Sauvegarder la clé munge pour distribution
cp /etc/munge/munge.key /opt/hpc/munge.key
chown hpc:hpc /opt/hpc/munge.key
chmod 400 /opt/hpc/munge.key

log "✅ Clé Munge sauvegardée dans /opt/hpc/munge.key"
log "🔗 Cette clé doit être copiée sur tous les nœuds du cluster"

# =============================================================================
# 16. TESTS FINAUX
# =============================================================================
log "🧪 Tests de fonctionnement..."

# Test Munge
if munge -n | unmunge > /dev/null 2>&1; then
    log "✅ Munge: OK"
else
    log "❌ Munge: ÉCHEC"
fi

# Test SlurmCtld
if scontrol ping > /dev/null 2>&1; then
    log "✅ SlurmCtld: OK"
else
    log "❌ SlurmCtld: ÉCHEC"
fi

# Test base de données
if sacctmgr list cluster > /dev/null 2>&1; then
    log "✅ SlurmDBD: OK"
else
    log "❌ SlurmDBD: ÉCHEC"
fi

# =============================================================================
# 17. INFORMATIONS FINALES
# =============================================================================
log "✅ Configuration Slurm Head-node terminée avec succès!"

cat << 'EOF'

=============================================================================
🎉 SLURM HEAD-NODE CONFIGURÉ AVEC SUCCÈS
=============================================================================

✅ MariaDB configuré pour SlurmDBD
✅ Munge installé et configuré
✅ SlurmDBD démarré (port 6819)
✅ SlurmCtld démarré (port 6817)
✅ Cluster "hpc-cluster" créé
✅ Partitions configurées: compute, gpu, debug, long
✅ CGroups configurés pour l'isolation des ressources
✅ GPU support configuré
✅ Firewall configuré

🔑 CLÉS ET MOTS DE PASSE:
   - Base MariaDB: root / SlurmDB2025!
   - Base Slurm: slurm / SlurmDB2025!
   - Clé Munge: /opt/hpc/munge.key (à distribuer)

🔧 COMMANDES UTILES:
   - Status cluster: /opt/hpc/bin/cluster-status
   - Monitoring: /opt/hpc/bin/cluster-monitor
   - Informations nœuds: sinfo
   - Jobs: squeue
   - Comptes: sacctmgr list associations

🔗 PROCHAINES ÉTAPES:
   1. Installer les compute nodes: bash 02-slurm-compute.sh
   2. Configurer BeeGFS storage: bash 03-beegfs-storage.sh
   3. Installer clients BeeGFS: bash 04-beegfs-client.sh
   4. Configurer GPU nodes: bash 05-gpu.sh

📊 MONITORING:
   - Netdata: http://172.16.0.200:19999
   - Slurm logs: /var/log/slurm/

⚠️  IMPORTANT: La clé Munge (/opt/hpc/munge.key) doit être copiée
    sur tous les nœuds du cluster avant de les joindre.

=============================================================================
EOF

log "🏁 Script 01-slurm-head.sh terminé"
