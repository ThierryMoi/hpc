#!/bin/bash
# =============================================================================
# 00-base.sh - Configuration de base pour toutes les VMs du cluster HPC
# =============================================================================
# Usage: bash 00-base.sh
# Description: Met à jour le système et installe les outils de base
# =============================================================================

set -e  # Arrêt immédiat en cas d'erreur

# Variables globales
SCRIPT_NAME="[BASE-SETUP]"
LOG_FILE="/var/log/hpc-base-setup.log"

# Fonction de logging
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $SCRIPT_NAME $1" | tee -a "$LOG_FILE"
}

log "🚀 Début de la configuration de base"

# =============================================================================
# 1. MISE À JOUR DU SYSTÈME
# =============================================================================
log "📦 Mise à jour du système Ubuntu..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get upgrade -y
apt-get autoremove -y
apt-get autoclean

# =============================================================================
# 2. INSTALLATION DES OUTILS DE BASE
# =============================================================================
log "🔧 Installation des outils de base..."
apt-get install -y \
    build-essential \
    wget \
    curl \
    git \
    vim \
    nano \
    htop \
    iotop \
    nmon \
    tree \
    unzip \
    zip \
    rsync \
    screen \
    tmux \
    net-tools \
    dnsutils \
    iputils-ping \
    traceroute \
    tcpdump \
    iftop \
    iptraf-ng \
    lsof \
    strace \
    gdb \
    valgrind \
    time \
    bc \
    jq \
    uuid-runtime \
    software-properties-common \
    apt-transport-https \
    ca-certificates \
    gnupg \
    lsb-release

# =============================================================================
# 3. CONFIGURATION RÉSEAU ET SÉCURITÉ
# =============================================================================
log "🔒 Configuration de base de la sécurité..."

# Configuration UFW (pare-feu)
ufw --force enable
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh
ufw allow from 172.16.0.0/18  # Réseau interne cluster

# Configuration SSH sécurisée
if [ ! -f /etc/ssh/sshd_config.bak ]; then
    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak
fi

# Paramètres SSH sécurisés
cat >> /etc/ssh/sshd_config << 'EOF'

# Configuration HPC Cluster
PermitRootLogin no
PasswordAuthentication yes
PubkeyAuthentication yes
X11Forwarding yes
ClientAliveInterval 300
ClientAliveCountMax 2
MaxAuthTries 3
Protocol 2
EOF

systemctl restart sshd
systemctl enable ssh

# =============================================================================
# 4. CONFIGURATION DES LIMITES SYSTÈME
# =============================================================================
log "⚙️  Configuration des limites système pour HPC..."

# Limites de fichiers et processus pour HPC
cat > /etc/security/limits.d/99-hpc.conf << 'EOF'
# Limites pour utilisateur hpc et root
* soft nofile 65536
* hard nofile 65536
* soft nproc 65536  
* hard nproc 65536
* soft memlock unlimited
* hard memlock unlimited
* soft stack unlimited
* hard stack unlimited

# Limites spécifiques HPC
hpc soft nofile 1048576
hpc hard nofile 1048576
hpc soft nproc 1048576
hpc hard nproc 1048576
hpc soft memlock unlimited
hpc hard memlock unlimited
EOF

# Configuration sysctl pour HPC
cat > /etc/sysctl.d/99-hpc.conf << 'EOF'
# Optimisations réseau pour HPC
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
net.ipv4.tcp_rmem = 4096 85000 134217728
net.ipv4.tcp_wmem = 4096 65536 134217728
net.core.netdev_max_backlog = 5000
net.ipv4.tcp_window_scaling = 1
net.ipv4.tcp_timestamps = 1
net.ipv4.tcp_sack = 1

# Optimisations mémoire
vm.swappiness = 1
vm.dirty_ratio = 15
vm.dirty_background_ratio = 5
kernel.shmmax = 68719476736
kernel.shmall = 4294967296
EOF

sysctl -p /etc/sysctl.d/99-hpc.conf

# =============================================================================
# 5. CONFIGURATION DU HOSTNAME ET HOSTS
# =============================================================================
log "🌐 Configuration réseau du cluster..."

# Configurer le fichier /etc/hosts avec tous les nœuds du cluster
cat > /etc/hosts << 'EOF'
127.0.0.1 localhost

# Cluster HPC - Réseau 172.16.0.0/18
172.16.0.200 hpc-head-node head-node
172.16.0.201 hpc-storage-node storage-node  
172.16.0.202 hpc-compute-01 compute-01
172.16.0.203 hpc-compute-02 compute-02
172.16.0.204 hpc-compute-03 compute-03
172.16.0.205 hpc-compute-04 compute-04
172.16.0.206 hpc-compute-05 compute-05
172.16.0.207 hpc-compute-06 compute-06
172.16.0.208 hpc-compute-07 compute-07
172.16.0.209 hpc-compute-08 compute-08
172.16.0.210 hpc-gpu-01 gpu-01
172.16.0.211 hpc-gpu-02 gpu-02
172.16.0.212 hpc-postgresql postgresql

# The following lines are desirable for IPv6 capable hosts
::1 ip6-localhost ip6-loopback
fe00::0 ip6-localnet
ff00::0 ip6-mcastprefix
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters
EOF

# =============================================================================
# 6. CRÉATION DE L'UTILISATEUR HPC
# =============================================================================
log "👤 Configuration de l'utilisateur hpc..."

# Créer le groupe hpc s'il n'existe pas
if ! getent group hpc > /dev/null 2>&1; then
    groupadd -g 2000 hpc
fi

# Vérifier si l'utilisateur hpc existe déjà (créé par cloud-init)
if id "hpc" &>/dev/null; then
    log "✅ Utilisateur hpc existe déjà"
    # S'assurer qu'il est dans le bon groupe
    usermod -g hpc -G sudo,hpc hpc
else
    # Créer l'utilisateur hpc s'il n'existe pas
    useradd -u 2000 -g hpc -G sudo -m -s /bin/bash hpc
    echo "hpc:HPC2025!" | chpasswd
    log "✅ Utilisateur hpc créé"
fi

# Configuration du répertoire home
mkdir -p /home/hpc/.ssh
chown hpc:hpc /home/hpc/.ssh
chmod 700 /home/hpc/.ssh

# Création des répertoires de travail HPC
mkdir -p /opt/hpc/{apps,data,scratch,logs}
chown -R hpc:hpc /opt/hpc
chmod -R 755 /opt/hpc

# =============================================================================
# 7. CONFIGURATION DES ENVIRONNEMENTS DE DÉVELOPPEMENT
# =============================================================================
log "🔧 Configuration des environnements de développement..."

# Variables d'environnement pour HPC
cat > /etc/environment << 'EOF'
PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/opt/hpc/apps/bin"
HPC_HOME="/opt/hpc"
HPC_APPS="/opt/hpc/apps"
HPC_DATA="/opt/hpc/data"
HPC_SCRATCH="/opt/hpc/scratch"
EOF

# Profil bash pour l'utilisateur hpc
cat > /home/hpc/.bashrc << 'EOF'
# ~/.bashrc: executed by bash(1) for non-login shells.

# If not running interactively, don't do anything
case $- in
    *i*) ;;
      *) return;;
esac

# Histoire bash
HISTCONTROL=ignoreboth
HISTSIZE=10000
HISTFILESIZE=20000
shopt -s histappend
shopt -s checkwinsize

# Couleurs
if [ -x /usr/bin/dircolors ]; then
    test -r ~/.dircolors && eval "$(dircolors -b ~/.dircolors)" || eval "$(dircolors -b)"
    alias ls='ls --color=auto'
    alias grep='grep --color=auto'
    alias fgrep='fgrep --color=auto'
    alias egrep='egrep --color=auto'
fi

# Alias utiles pour HPC
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'
alias ..='cd ..'
alias ...='cd ../..'
alias h='history'
alias c='clear'
alias df='df -h'
alias du='du -h'
alias free='free -h'
alias ps='ps aux'
alias top='htop'

# Variables d'environnement HPC
export HPC_HOME="/opt/hpc"
export HPC_APPS="/opt/hpc/apps"
export HPC_DATA="/opt/hpc/data"
export HPC_SCRATCH="/opt/hpc/scratch"
export PATH="$HPC_APPS/bin:$PATH"

# Prompt coloré
PS1='\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '

# Charger les modules si disponibles
if [ -f /etc/profile.d/modules.sh ]; then
    source /etc/profile.d/modules.sh
fi
EOF

chown hpc:hpc /home/hpc/.bashrc

# =============================================================================
# 8. INSTALLATION D'OUTILS DE MONITORING
# =============================================================================
log "📊 Installation des outils de monitoring..."

# Installation de netdata pour monitoring en temps réel
apt-get install -y netdata
systemctl enable netdata
systemctl start netdata

# Configuration netdata
cat > /etc/netdata/netdata.conf << 'EOF'
[global]
    hostname = $(hostname)
    default port = 19999
    bind socket to IP = 0.0.0.0
    
[web]
    allow connections from = localhost 172.16.0.0/18
EOF

systemctl restart netdata

# =============================================================================
# 9. NETTOYAGE FINAL
# =============================================================================
log "🧹 Nettoyage final..."

apt-get autoremove -y
apt-get autoclean
updatedb &

# =============================================================================
# 10. INFORMATIONS FINALES
# =============================================================================
log "✅ Configuration de base terminée avec succès!"

cat << 'EOF'

=============================================================================
🎉 CONFIGURATION DE BASE TERMINÉE
=============================================================================

✅ Système mis à jour
✅ Outils de base installés  
✅ Sécurité configurée (UFW, SSH)
✅ Limites système optimisées pour HPC
✅ Utilisateur hpc configuré
✅ Répertoires HPC créés (/opt/hpc/*)
✅ Environnements de développement configurés
✅ Monitoring installé (Netdata sur port 19999)

🔗 Prochaines étapes:
   - Head-node: bash 01-slurm-head.sh
   - Storage-node: bash 03-beegfs-storage.sh  
   - Compute nodes: bash 02-slurm-compute.sh
   - GPU nodes: bash 05-gpu.sh
   - PostgreSQL: bash 07-postgresql.sh
   - Packages: bash 06-packages.sh

🌐 Monitoring: http://$(hostname -I | awk '{print $1}'):19999

=============================================================================
EOF

log "🏁 Script 00-base.sh terminé"
