#!/bin/bash
# =============================================================================
# 05-gpu.sh - Configuration des nœuds GPU avec CUDA et frameworks
# =============================================================================
# Usage: bash 05-gpu.sh
# Description: Installe NVIDIA drivers, CUDA, et frameworks GPU (TensorFlow, PyTorch)
# Prérequis: 00-base.sh et 02-slurm-compute.sh
# =============================================================================

set -e

SCRIPT_NAME="[GPU-SETUP]"
LOG_FILE="/var/log/hpc-gpu-setup.log"
CUDA_VERSION="12.3"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $SCRIPT_NAME $1" | tee -a "$LOG_FILE"
}

log "🚀 Configuration des nœuds GPU"

# =============================================================================
# 1. VÉRIFICATION ET INSTALLATION DES DRIVERS NVIDIA
# =============================================================================
log "🎮 Installation des drivers NVIDIA..."

export DEBIAN_FRONTEND=noninteractive

# Ajouter repository NVIDIA
wget -qO - https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/3bf863cc.pub | apt-key add -
echo "deb https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/ /" > /etc/apt/sources.list.d/cuda.list

apt-get update

# Installation des drivers et CUDA
apt-get install -y \
    nvidia-driver-545 \
    nvidia-utils-545 \
    cuda-toolkit-12-3 \
    nvidia-cuda-toolkit \
    nvidia-container-toolkit

# =============================================================================
# 2. CONFIGURATION POST-INSTALLATION
# =============================================================================
log "⚙️  Configuration post-installation CUDA..."

# Variables d'environnement CUDA
cat >> /etc/environment << 'EOF'
CUDA_HOME=/usr/local/cuda
PATH="/usr/local/cuda/bin:$PATH"
LD_LIBRARY_PATH="/usr/local/cuda/lib64:$LD_LIBRARY_PATH"
EOF

# Profil CUDA pour tous les utilisateurs
cat > /etc/profile.d/cuda.sh << 'EOF'
export CUDA_HOME=/usr/local/cuda
export PATH=$CUDA_HOME/bin:$PATH
export LD_LIBRARY_PATH=$CUDA_HOME/lib64:$LD_LIBRARY_PATH
EOF

# Liens symboliques
if [ ! -L /usr/local/cuda ]; then
    ln -sf /usr/local/cuda-12.3 /usr/local/cuda
fi

# =============================================================================
# 3. INSTALLATION DES FRAMEWORKS GPU
# =============================================================================
log "🤖 Installation des frameworks d'IA..."

# Mise à jour pip
pip3 install --upgrade pip setuptools wheel

# PyTorch avec support GPU
pip3 install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu121

# TensorFlow GPU
pip3 install tensorflow[and-cuda]

# Autres bibliothèques utiles
pip3 install \
    cupy-cuda12x \
    numba \
    scikit-cuda \
    pycuda \
    cudf-cu12 \
    cuml-cu12 \
    jupyter \
    jupyterlab

# =============================================================================
# 4. CONFIGURATION SLURM POUR GPU
# =============================================================================
log "🔧 Configuration Slurm pour GPU..."

# Configuration GRES pour les GPUs
GPU_COUNT=$(nvidia-smi -L | wc -l)
cat > /etc/slurm/gres.conf << EOF
AutoDetect=nvml
NodeName=$(hostname) Name=gpu Type=nvidia File=/dev/nvidia[0-$((GPU_COUNT-1))]
EOF

# Script de test GPU pour Slurm
mkdir -p /opt/hpc/tests
cat > /opt/hpc/tests/gpu-test.py << 'EOF'
#!/usr/bin/env python3
import torch
import tensorflow as tf

print("=== TEST GPU ===")
print(f"PyTorch version: {torch.__version__}")
print(f"CUDA available: {torch.cuda.is_available()}")
if torch.cuda.is_available():
    print(f"GPU count: {torch.cuda.device_count()}")
    for i in range(torch.cuda.device_count()):
        print(f"GPU {i}: {torch.cuda.get_device_name(i)}")

print(f"\nTensorFlow version: {tf.__version__}")
print("GPU devices:", tf.config.list_physical_devices('GPU'))
EOF

chmod +x /opt/hpc/tests/gpu-test.py

# =============================================================================
# 5. MONITORING ET SCRIPTS
# =============================================================================
log "📊 Installation d'outils de monitoring GPU..."

# Script de monitoring GPU
cat > /opt/hpc/bin/gpu-monitor << 'EOF'
#!/bin/bash
while true; do
    clear
    echo "=== GPU MONITORING - $(date) ==="
    nvidia-smi
    echo
    echo "Processus GPU:"
    nvidia-smi pmon -c 1
    sleep 5
done
EOF

chmod +x /opt/hpc/bin/gpu-monitor

# Script de test de performance
cat > /opt/hpc/bin/gpu-benchmark << 'EOF'
#!/bin/bash
echo "=== GPU BENCHMARK ==="
echo "Test CUDA:"
/usr/local/cuda/extras/demo_suite/deviceQuery
echo
echo "Test PyTorch:"
python3 /opt/hpc/tests/gpu-test.py
EOF

chmod +x /opt/hpc/bin/gpu-benchmark

# Redémarrage requis pour les drivers
log "⚠️  Redémarrage requis pour activer les drivers GPU"
log "✅ Configuration GPU terminée - Redémarrer le système"

cat << 'EOF'

=============================================================================
🎮 CONFIGURATION GPU TERMINÉE
=============================================================================

✅ Drivers NVIDIA installés
✅ CUDA Toolkit configuré  
✅ PyTorch GPU installé
✅ TensorFlow GPU installé
✅ Slurm configuré pour GPU
✅ Outils de monitoring installés

🔧 COMMANDES UTILES:
   - Monitoring: /opt/hpc/bin/gpu-monitor
   - Benchmark: /opt/hpc/bin/gpu-benchmark
   - Test: python3 /opt/hpc/tests/gpu-test.py
   - Info GPU: nvidia-smi

⚠️  REDÉMARRAGE REQUIS pour activer les drivers GPU

🔗 Après redémarrage, tester avec:
   srun --gres=gpu:1 python3 /opt/hpc/tests/gpu-test.py

=============================================================================
EOF
