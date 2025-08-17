#!/bin/bash
# =============================================================================
# 02-slurm-compute.sh - Configuration des Compute Nodes avec Slurm
# =============================================================================
# Usage: bash 02-slurm-compute.sh
# Description: Installe et configure Slurm sur un compute node
# Prérequis: 00-base.sh doit avoir été exécuté
#           La clé Munge doit être disponible depuis le head-node
# =============================================================================

set -e  # Arrêt immédiat en cas d'erreur

# Variables globales
SCRIPT_NAME="[SLURM-COMPUTE]"
LOG_FILE="/var/log/hpc-slurm-compute.log"
HEAD_NODE="172.16.0.200"
SLURM_UID=2001
SLURM_GID=2001

# Fonction de logging
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $SCRIPT_NAME $1" | tee -a "$LOG_FILE"
}

log "🚀 Début de la configuration Slurm Compute Node"

# =============================================================================
# 1. VÉRIFICATION DES PRÉREQUIS
# =============================================================================
log "🔍 Vérification des prérequis..."

if [ "$(id -u)" -ne 0 ]; then
    log "❌ Ce script doit être exécuté en tant que root"
    exit 1
fi

HOSTNAME=$(hostname)
log "📍 Configuration du nœud: $HOSTNAME"

# Vérifier la connectivité avec le head-node
if ! ping -c 1 $HEAD_NODE > /dev/null 2>&1; then
    log "❌ Impossible de joindre le head-node ($HEAD_NODE)"
    exit 1
fi

# =============================================================================
# 2. INSTALLATION DES DÉPENDANCES
# =============================================================================
log "📦 Installation des dépendances Slurm..."

export DEBIAN_FRONTEND=noninteractive
apt-get update

# Packages nécessaires pour compute node
apt-get install -y \
    munge \
    libmunge-dev \
    libmunge2 \
    slurm-wlm \
    slurm-wlm-basic-plugins \
    slurm-client \
    libpam-slurm \
    libslurm-dev \
    ntp \
    ntpdate \
    chrony \
    python3-pip \
    python3-dev \
    openmpi-bin \
    openmpi-common \
    libopenmpi-dev \
    mpich \
    libmpich-dev

# =============================================================================
# 3. CRÉATION DE L'UTILISATEUR SLURM
# =============================================================================
log "👤 Configuration de l'utilisateur Slurm..."

# Création du groupe et utilisateur slurm (mêmes IDs que le head-node)
if ! getent group slurm > /dev/null 2>&1; then
    groupadd -g $SLURM_GID slurm
fi

if ! id "slurm" &>/dev/null; then
    useradd -u $SLURM_UID -g slurm -d /var/lib/slurm -s /bin/bash slurm
fi

# Création des répertoires Slurm
mkdir -p /var/spool/slurm/slurmd /var/log/slurm /etc/slurm /var/lib/slurm /var/run/slurm
chown -R slurm:slurm /var/spool/slurm /var/log/slurm /var/lib/slurm /var/run/slurm
chmod 755 /var/spool/slurm /var/log/slurm /var/lib/slurm /var/run/slurm

# =============================================================================
# 4. RÉCUPÉRATION ET CONFIGURATION DE MUNGE
# =============================================================================
log "🔐 Configuration de Munge..."

# Création du groupe et utilisateur munge
if ! getent group munge > /dev/null 2>&1; then
    groupadd -g 997 munge
fi

if ! id "munge" &>/dev/null; then
    useradd -u 997 -g munge -d /var/lib/munge -s /sbin/nologin munge
fi

# Récupération de la clé Munge depuis le head-node
log "🔑 Récupération de la clé Munge depuis le head-node..."

# Méthode 1: Tentative via scp (si SSH configuré)
if sshpass -p "HPC2025!" scp -o StrictHostKeyChecking=no hpc@$HEAD_NODE:/opt/hpc/munge.key /tmp/munge.key 2>/dev/null; then
    log "✅ Clé Munge récupérée via scp"
    cp /tmp/munge.key /etc/munge/munge.key
    rm /tmp/munge.key
elif [ -f /opt/hpc/munge.key ]; then
    # Méthode 2: Clé déjà présente localement
    log "✅ Clé Munge trouvée localement"
    cp /opt/hpc/munge.key /etc/munge/munge.key
else
    log "❌ Impossible de récupérer la clé Munge"
    log "🔧 Solutions possibles:"
    log "   1. Copier manuellement /opt/hpc/munge.key depuis le head-node"
    log "   2. Vérifier la connectivité SSH avec le head-node"
    exit 1
fi

# Configuration des permissions Munge
chown munge:munge /etc/munge/munge.key
chmod 400 /etc/munge/munge.key
chown -R munge:munge /etc/munge /var/lib/munge /var/log/munge /run/munge
chmod 700 /etc/munge /var/lib/munge /var/log/munge
chmod 755 /run/munge

# Démarrage de Munge
systemctl enable munge
systemctl start munge

# Test de Munge
sleep 2
if munge -n | unmunge > /dev/null 2>&1; then
    log "✅ Munge fonctionne correctement"
else
    log "❌ Problème avec Munge"
    exit 1
fi

# =============================================================================
# 5. RÉCUPÉRATION DE LA CONFIGURATION SLURM
# =============================================================================
log "📋 Récupération de la configuration Slurm..."

# Récupérer slurm.conf depuis le head-node
if sshpass -p "HPC2025!" scp -o StrictHostKeyChecking=no hpc@$HEAD_NODE:/etc/slurm/slurm.conf /etc/slurm/slurm.conf 2>/dev/null; then
    log "✅ Configuration Slurm récupérée"
elif [ -f /opt/hpc/slurm.conf ]; then
    cp /opt/hpc/slurm.conf /etc/slurm/slurm.conf
    log "✅ Configuration Slurm trouvée localement"
else
    log "❌ Impossible de récupérer slurm.conf"
    log "🔧 Création d'une configuration minimale..."
    
    # Configuration minimale en cas d'échec
    cat > /etc/slurm/slurm.conf << EOF
ClusterName=hpc-cluster
ControlMachine=hpc-head-node
ControlAddr=$HEAD_NODE
AuthType=auth/munge
SlurmdPort=6818
SlurmctldPort=6817
StateSaveLocation=/var/lib/slurm/slurmctld
SlurmdSpoolDir=/var/spool/slurm/slurmd
SlurmdLogFile=/var/log/slurm/slurmd.log
SlurmctldLogFile=/var/log/slurm/slurmctld.log
SelectType=select/cons_tres
SelectTypeParameters=CR_Core_Memory
ProctrackType=proctrack/cgroup
TaskPlugin=task/cgroup
MpiDefault=pmix_v4

# Ce nœud (sera mis à jour automatiquement)
NodeName=$HOSTNAME NodeAddr=$(hostname -I | awk '{print $1}') CPUs=$(nproc) RealMemory=$(free -m | awk '/^Mem:/{print $2}') State=UNKNOWN

# Partition par défaut
PartitionName=compute Nodes=$HOSTNAME Default=YES State=UP
EOF
fi

chown slurm:slurm /etc/slurm/slurm.conf
chmod 644 /etc/slurm/slurm.conf

# =============================================================================
# 6. CONFIGURATION DES CGROUPS
# =============================================================================
log "🔧 Configuration des CGroups..."

# Récupérer cgroup.conf depuis le head-node ou créer une configuration de base
if ! sshpass -p "HPC2025!" scp -o StrictHostKeyChecking=no hpc@$HEAD_NODE:/etc/slurm/cgroup.conf /etc/slurm/cgroup.conf 2>/dev/null; then
    cat > /etc/slurm/cgroup.conf << 'EOF'
CgroupMountpoint="/sys/fs/cgroup"
CgroupAutomount=yes
CgroupReleaseAgentDir="/etc/slurm/cgroup"
ConstrainCores=yes
ConstrainDevices=yes
ConstrainRAMSpace=yes
ConstrainSwapSpace=yes
AllowedDevicesFile="/etc/slurm/cgroup_allowed_devices_file.conf"
EOF
fi

# Fichier des devices autorisés
if ! sshpass -p "HPC2025!" scp -o StrictHostKeyChecking=no hpc@$HEAD_NODE:/etc/slurm/cgroup_allowed_devices_file.conf /etc/slurm/cgroup_allowed_devices_file.conf 2>/dev/null; then
    cat > /etc/slurm/cgroup_allowed_devices_file.conf << 'EOF'
/dev/null
/dev/urandom
/dev/zero
/dev/sda*
/dev/nvme*
/dev/cpu/*/*
/dev/pts/*
/dev/nvidia*
/dev/dri/*
EOF
fi

chown slurm:slurm /etc/slurm/cgroup.conf /etc/slurm/cgroup_allowed_devices_file.conf
chmod 644 /etc/slurm/cgroup.conf /etc/slurm/cgroup_allowed_devices_file.conf

# =============================================================================
# 7. DÉTECTION ET CONFIGURATION DES RESSOURCES
# =============================================================================
log "🔍 Détection des ressources du nœud..."

# Détection du matériel
CPU_COUNT=$(nproc)
MEMORY_MB=$(free -m | awk '/^Mem:/{print $2}')
MEMORY_KB=$((MEMORY_MB * 1024))
SOCKET_COUNT=$(lscpu | grep "Socket(s):" | awk '{print $2}')
CORES_PER_SOCKET=$((CPU_COUNT / SOCKET_COUNT))
NODE_IP=$(hostname -I | awk '{print $1}')

log "💻 Ressources détectées:"
log "   - CPUs: $CPU_COUNT"
log "   - Mémoire: ${MEMORY_MB} MB"
log "   - Sockets: $SOCKET_COUNT"
log "   - Cores par socket: $CORES_PER_SOCKET"
log "   - IP: $NODE_IP"

# Détection des GPUs (si présents)
GPU_COUNT=0
if command -v nvidia-smi &> /dev/null; then
    GPU_COUNT=$(nvidia-smi -L | wc -l)
    log "   - GPUs NVIDIA: $GPU_COUNT"
    
    # Configuration GRES pour GPU
    cat > /etc/slurm/gres.conf << EOF
AutoDetect=nvml
NodeName=$HOSTNAME Name=gpu Type=nvidia File=/dev/nvidia[0-$((GPU_COUNT-1))]
EOF
    chown slurm:slurm /etc/slurm/gres.conf
    chmod 644 /etc/slurm/gres.conf
fi

# =============================================================================
# 8. CONFIGURATION DU SERVICE SLURMD
# =============================================================================
log "🔄 Configuration du service SlurmdD..."

cat > /etc/systemd/system/slurmd.service << 'EOF'
[Unit]
Description=Slurm Compute Node Daemon
After=network.target munge.service
Requires=munge.service

[Service]
Type=notify
User=slurm
Group=slurm
ExecStart=/usr/sbin/slurmd -D
ExecReload=/bin/kill -HUP $MAINPID
PIDFile=/var/run/slurm/slurmd.pid
LimitNOFILE=65536
TasksMax=infinity
Delegate=yes

[Install]
WantedBy=multi-user.target
EOF

# Recharger systemd
systemctl daemon-reload

# =============================================================================
# 9. CONFIGURATION DES OPTIMISATIONS SYSTÈME
# =============================================================================
log "⚡ Configuration des optimisations système..."

# Optimisations pour les calculs parallèles
cat >> /etc/sysctl.d/99-hpc-compute.conf << 'EOF'
# Optimisations spécifiques aux compute nodes
kernel.numa_balancing = 0
vm.zone_reclaim_mode = 1
kernel.sched_migration_cost_ns = 5000000
kernel.sched_autogroup_enabled = 0

# Optimisations IPC (Inter-Process Communication)
kernel.msgmax = 65536
kernel.msgmnb = 65536
kernel.shmmni = 4096
EOF

sysctl -p /etc/sysctl.d/99-hpc-compute.conf

# =============================================================================
# 10. INSTALLATION D'OUTILS SCIENTIFIQUES DE BASE
# =============================================================================
log "🧮 Installation d'outils scientifiques de base..."

# Bibliothèques scientifiques essentielles
apt-get install -y \
    libblas3 \
    liblapack3 \
    libblas-dev \
    liblapack-dev \
    libfftw3-3 \
    libfftw3-dev \
    libgsl25 \
    libgsl-dev \
    libhdf5-103 \
    libhdf5-dev \
    libnetcdf19 \
    libnetcdf-dev

# Outils Python scientifiques de base
pip3 install --upgrade \
    numpy \
    scipy \
    matplotlib \
    pandas \
    numba \
    mpi4py

# =============================================================================
# 11. DÉMARRAGE DU SERVICE SLURMD
# =============================================================================
log "🚀 Démarrage du service SlurmdD..."

systemctl enable slurmd
systemctl start slurmd

# Attendre que le service soit prêt
sleep 5

# Vérifier que SlurmdD fonctionne
if systemctl is-active --quiet slurmd; then
    log "✅ SlurmdD démarré avec succès"
else
    log "❌ Problème avec SlurmdD"
    systemctl status slurmd
    exit 1
fi

# =============================================================================
# 12. CONFIGURATION DU FIREWALL
# =============================================================================
log "🔒 Configuration du firewall..."

# Ports Slurm
ufw allow 6818/tcp comment "SlurmdD"
ufw allow 7321/tcp comment "Slurm srun"
ufw allow 60001:63000/tcp comment "Slurm communication range"

# Ports MPI
ufw allow 12000:12999/tcp comment "MPI communication"

# =============================================================================
# 13. SCRIPTS ET OUTILS UTILES
# =============================================================================
log "🔧 Installation d'outils de gestion..."

mkdir -p /opt/hpc/bin

# Script de status du nœud
cat > /opt/hpc/bin/node-status << 'EOF'
#!/bin/bash
echo "=== STATUT DU NŒUD $(hostname) ==="
echo
echo "Service Slurm:"
systemctl status munge slurmd --no-pager -l
echo
echo "Informations du nœud:"
sinfo -N -n $(hostname)
echo
echo "Jobs sur ce nœud:"
squeue -w $(hostname)
echo
echo "Utilisation des ressources:"
echo "CPU: $(nproc) cores"
echo "Mémoire: $(free -h | awk '/^Mem:/{print $3 "/" $2}')"
if command -v nvidia-smi &> /dev/null; then
    echo "GPU:"
    nvidia-smi --query-gpu=index,name,utilization.gpu,memory.used,memory.total --format=csv,noheader,nounits
fi
echo
echo "Load average: $(uptime | awk -F'load average:' '{print $2}')"
EOF

chmod +x /opt/hpc/bin/node-status

# Script de monitoring en temps réel
cat > /opt/hpc/bin/node-monitor << 'EOF'
#!/bin/bash
while true; do
    clear
    echo "=== MONITORING NŒUD $(hostname) - $(date) ==="
    echo
    echo "Jobs actifs sur ce nœud:"
    squeue -w $(hostname) --format="%.10i %.12u %.10P %.10T %.8M %.6D %.30j"
    echo
    echo "Charge système:"
    uptime
    echo
    echo "Utilisation CPU/Mémoire:"
    top -bn1 | head -5 | tail -1
    free -h
    echo
    if command -v nvidia-smi &> /dev/null; then
        echo "Utilisation GPU:"
        nvidia-smi --query-gpu=index,utilization.gpu,memory.used,memory.total --format=csv,noheader,nounits
        echo
    fi
    sleep 10
done
EOF

chmod +x /opt/hpc/bin/node-monitor

# =============================================================================
# 14. TEST DE CONNEXION AU CLUSTER
# =============================================================================
log "🧪 Test de connexion au cluster..."

# Test de connexion au head-node
if sinfo > /dev/null 2>&1; then
    log "✅ Connexion au cluster: OK"
    
    # Afficher le statut du nœud
    NODE_STATE=$(sinfo -N -n $HOSTNAME -h -o "%T")
    log "📊 État du nœud dans Slurm: $NODE_STATE"
    
    if [ "$NODE_STATE" = "UNKNOWN" ] || [ "$NODE_STATE" = "DOWN" ]; then
        log "⚠️  Le nœud doit être activé par l'administrateur sur le head-node"
        log "🔧 Commande à exécuter sur le head-node:"
        log "    scontrol update NodeName=$HOSTNAME State=IDLE"
    fi
else
    log "❌ Impossible de se connecter au cluster"
    log "🔧 Vérifier la configuration réseau et Slurm"
fi

# =============================================================================
# 15. INFORMATIONS FINALES
# =============================================================================
log "✅ Configuration Slurm Compute Node terminée avec succès!"

cat << EOF

=============================================================================
🎉 SLURM COMPUTE NODE CONFIGURÉ AVEC SUCCÈS
=============================================================================

📍 Nœud: $HOSTNAME
🌐 IP: $NODE_IP
💻 Ressources: $CPU_COUNT CPUs, ${MEMORY_MB} MB RAM
$([ $GPU_COUNT -gt 0 ] && echo "🎮 GPUs: $GPU_COUNT NVIDIA")

✅ Munge configuré et démarré
✅ SlurmdD configuré et démarré
✅ CGroups configurés pour l'isolation
✅ Optimisations système appliquées
✅ Outils scientifiques de base installés
✅ Firewall configuré

🔧 COMMANDES UTILES:
   - Status nœud: /opt/hpc/bin/node-status
   - Monitoring: /opt/hpc/bin/node-monitor
   - Jobs sur ce nœud: squeue -w $HOSTNAME
   - Infos nœud: sinfo -N -n $HOSTNAME

📊 MONITORING:
   - Netdata: http://$NODE_IP:19999
   - Slurm logs: /var/log/slurm/slurmd.log

🔗 PROCHAINES ÉTAPES:
   1. Sur le head-node, activer ce nœud:
      scontrol update NodeName=$HOSTNAME State=IDLE
   2. Tester avec un job simple:
      srun -w $HOSTNAME hostname

⚠️  NOTES:
   - Le nœud apparaît initialement en état UNKNOWN
   - L'administrateur doit l'activer depuis le head-node
   - Vérifier la synchronisation des clés Munge

=============================================================================
EOF

log "🏁 Script 02-slurm-compute.sh terminé"
