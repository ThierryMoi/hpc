#!/bin/bash
# =============================================================================
# 06-packages.sh - Installation des packages scientifiques et outils HPC
# =============================================================================
# Usage: bash 06-packages.sh
# Description: Installe Python, R, outils scientifiques, et prépare Stata
# Prérequis: 00-base.sh
# =============================================================================

set -e

SCRIPT_NAME="[PACKAGES]"
LOG_FILE="/var/log/hpc-packages.log"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $SCRIPT_NAME $1" | tee -a "$LOG_FILE"
}

log "🚀 Installation des packages scientifiques"

# =============================================================================
# 1. PYTHON SCIENTIFIQUE
# =============================================================================
log "🐍 Installation de Python scientifique..."

export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y \
    python3-dev \
    python3-pip \
    python3-venv \
    python3-wheel \
    ipython3 \
    jupyter-notebook \
    python3-numpy \
    python3-scipy \
    python3-matplotlib \
    python3-pandas \
    python3-sklearn \
    python3-seaborn \
    python3-statsmodels

# Packages Python avancés via pip
pip3 install --upgrade \
    numpy \
    scipy \
    matplotlib \
    pandas \
    scikit-learn \
    seaborn \
    plotly \
    bokeh \
    statsmodels \
    sympy \
    networkx \
    biopython \
    astropy \
    xarray \
    dask \
    joblib \
    tqdm \
    jupyter \
    jupyterlab \
    ipywidgets \
    mpi4py

# =============================================================================
# 2. R ET PACKAGES
# =============================================================================
log "📊 Installation de R..."

# Ajouter repository R CRAN
wget -qO- https://cloud.r-project.org/bin/linux/ubuntu/marutter_pubkey.asc | tee -a /etc/apt/trusted.gpg.d/cran_ubuntu_key.asc
echo "deb [signed-by=/etc/apt/trusted.gpg.d/cran_ubuntu_key.asc] https://cloud.r-project.org/bin/linux/ubuntu jammy-cran40/" > /etc/apt/sources.list.d/cran.list

apt-get update
apt-get install -y \
    r-base \
    r-base-dev \
    r-recommended \
    libcurl4-openssl-dev \
    libssl-dev \
    libxml2-dev \
    libfontconfig1-dev \
    libharfbuzz-dev \
    libfribidi-dev \
    libfreetype6-dev \
    libpng-dev \
    libtiff5-dev \
    libjpeg-dev

# Installation packages R essentiels
Rscript -e "
packages <- c('tidyverse', 'ggplot2', 'dplyr', 'data.table', 'shiny', 'plotly', 'caret', 'randomForest', 'parallel', 'foreach', 'doParallel', 'Rmpi')
install.packages(packages, repos='https://cloud.r-project.org/')
"

# =============================================================================
# 3. OUTILS MATHÉMATIQUES ET SCIENTIFIQUES
# =============================================================================
log "🧮 Installation d'outils mathématiques..."

apt-get install -y \
    octave \
    maxima \
    scilab \
    gnuplot \
    imagemagick \
    ffmpeg \
    pandoc \
    texlive-full \
    texlive-latex-extra \
    texlive-fonts-recommended

# =============================================================================
# 4. BIBLIOTHÈQUES DE CALCUL HAUTES PERFORMANCES
# =============================================================================
log "⚡ Installation des bibliothèques HPC..."

apt-get install -y \
    libblas-dev \
    liblapack-dev \
    libopenblas-dev \
    libatlas-base-dev \
    libfftw3-dev \
    libgsl-dev \
    libhdf5-dev \
    libnetcdf-dev \
    libboost-all-dev \
    libeigen3-dev \
    libarmadillo-dev

# Intel MKL (si disponible)
if wget -qO- https://apt.repos.intel.com/intel-gpg-keys/GPG-PUB-KEY-INTEL-SW-PRODUCTS.PUB | apt-key add -; then
    echo "deb https://apt.repos.intel.com/oneapi all main" > /etc/apt/sources.list.d/oneAPI.list
    apt-get update
    apt-get install -y intel-basekit intel-hpckit 2>/dev/null || log "⚠️  Intel MKL non disponible"
fi

# =============================================================================
# 5. OUTILS DE BIOINFORMATIQUE
# =============================================================================
log "🧬 Installation d'outils de bioinformatique..."

apt-get install -y \
    samtools \
    bcftools \
    bwa \
    bowtie2 \
    blast2 \
    emboss \
    clustalw \
    muscle

# Conda pour la bioinformatique
wget -O /tmp/miniconda.sh https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh
bash /tmp/miniconda.sh -b -p /opt/miniconda3
ln -sf /opt/miniconda3/bin/conda /usr/local/bin/conda
rm /tmp/miniconda.sh

# Bioconda
/opt/miniconda3/bin/conda config --add channels defaults
/opt/miniconda3/bin/conda config --add channels bioconda
/opt/miniconda3/bin/conda config --add channels conda-forge

# =============================================================================
# 6. PRÉPARATION POUR STATA
# =============================================================================
log "📈 Préparation pour Stata..."

# Créer répertoire pour Stata
mkdir -p /opt/stata
chmod 755 /opt/stata

# Documentation pour l'installation de Stata
cat > /opt/stata/INSTALLATION_STATA.md << 'EOF'
# Installation de Stata pour HPC

## Prérequis
- Licence Stata/MP (recommandée pour HPC)
- Fichier d'installation (.tar.gz)
- Licence réseau (optionnel)

## Étapes d'installation

1. Copier l'archive Stata dans /opt/stata/
2. Extraire: tar -xzf Stata17Linux64.tar.gz
3. Installer: ./install
4. Activer la licence réseau si disponible

## Configuration pour Slurm
Ajouter Stata aux modules disponibles pour les jobs.

## Contact Support
Pour obtenir un devis Stata HPC:
- Site: https://www.stata.com
- Distributeur France: Datavenir
- Email: support@datavenir.com

## Tarification (estimation)
- Stata/BE: 595€/an (édition de base)
- Stata/SE: 1,195€/an (édition standard)  
- Stata/MP: 2,395€/an (multiprocessing, recommandée HPC)
- Licence réseau: +30-50% du prix de base
EOF

# Script de test pour quand Stata sera installé
cat > /opt/stata/test-stata.do << 'EOF'
* Test script pour Stata sur cluster HPC
version 17
set processors 8
display "Stata version: " c(stata_version)
display "Processors available: " c(processors)
display "Memory: " c(memory)
display "Test completed successfully"
EOF

# =============================================================================
# 7. OUTILS DE DÉVELOPPEMENT
# =============================================================================
log "🔧 Installation d'outils de développement..."

apt-get install -y \
    gcc \
    g++ \
    gfortran \
    cmake \
    make \
    autotools-dev \
    automake \
    libtool \
    pkg-config \
    git \
    subversion \
    mercurial \
    valgrind \
    gdb \
    lldb \
    clang \
    clang++ \
    golang \
    rustc \
    cargo

# =============================================================================
# 8. MODULES ENVIRONMENT
# =============================================================================
log "📦 Configuration des modules d'environnement..."

apt-get install -y environment-modules

# Configuration des modules
mkdir -p /opt/modulefiles/{python,r,stata,cuda,intel}

# Module Python
cat > /opt/modulefiles/python/3.10 << 'EOF'
#%Module1.0
proc ModulesHelp { } {
    puts stderr "Python 3.10 with scientific packages"
}
module-whatis "Python 3.10 scientific stack"
set root /usr
prepend-path PATH $root/bin
prepend-path LD_LIBRARY_PATH $root/lib
prepend-path PYTHONPATH /usr/local/lib/python3.10/site-packages
EOF

# Module R
cat > /opt/modulefiles/r/4.3 << 'EOF'
#%Module1.0
proc ModulesHelp { } {
    puts stderr "R 4.3 with statistical packages"
}
module-whatis "R statistical computing"
set root /usr
prepend-path PATH $root/bin
prepend-path LD_LIBRARY_PATH $root/lib/R/lib
EOF

# Configuration globale des modules
echo "/opt/modulefiles" >> /etc/environment-modules/modulespath

# =============================================================================
# 9. SCRIPTS ET OUTILS
# =============================================================================
log "🔧 Installation d'outils de gestion..."

mkdir -p /opt/hpc/examples

# Exemple Python HPC
cat > /opt/hpc/examples/example-python-hpc.py << 'EOF'
#!/usr/bin/env python3
"""
Exemple de script Python pour HPC avec MPI
Usage: mpirun -n 4 python3 example-python-hpc.py
"""
import numpy as np
import time
from mpi4py import MPI

def main():
    comm = MPI.COMM_WORLD
    rank = comm.Get_rank()
    size = comm.Get_size()
    
    # Calcul parallèle simple
    n = 1000000
    local_n = n // size
    
    start_time = time.time()
    
    # Calcul local
    local_sum = np.sum(np.random.random(local_n))
    
    # Réduction globale
    global_sum = comm.reduce(local_sum, op=MPI.SUM, root=0)
    
    end_time = time.time()
    
    if rank == 0:
        print(f"Somme globale: {global_sum}")
        print(f"Temps: {end_time - start_time:.2f}s")
        print(f"Processeurs: {size}")

if __name__ == "__main__":
    main()
EOF

chmod +x /opt/hpc/examples/example-python-hpc.py

# Exemple R HPC
cat > /opt/hpc/examples/example-r-hpc.R << 'EOF'
#!/usr/bin/env Rscript
# Exemple de script R pour HPC avec parallélisation
library(parallel)
library(foreach)
library(doParallel)

# Configuration du cluster parallèle
cl <- makeCluster(detectCores())
registerDoParallel(cl)

# Calcul parallèle
result <- foreach(i=1:8, .combine=c) %dopar% {
  # Simulation Monte Carlo
  n <- 1000000
  x <- runif(n, -1, 1)
  y <- runif(n, -1, 1)
  pi_est <- 4 * sum(x^2 + y^2 <= 1) / n
  return(pi_est)
}

# Arrêt du cluster
stopCluster(cl)

cat("Estimations de Pi:", result, "\n")
cat("Moyenne:", mean(result), "\n")
cat("Écart-type:", sd(result), "\n")
EOF

chmod +x /opt/hpc/examples/example-r-hpc.R

# Script de test des packages
cat > /opt/hpc/bin/test-packages << 'EOF'
#!/bin/bash
echo "=== TEST DES PACKAGES SCIENTIFIQUES ==="
echo
echo "Python:"
python3 -c "import numpy, scipy, matplotlib, pandas; print('✅ Python packages OK')"
echo
echo "R:"
Rscript -e "library(tidyverse); cat('✅ R packages OK\n')"
echo
echo "Modules:"
module avail 2>&1 | head -10
echo
echo "MPI:"
mpirun --version | head -1
echo
echo "Bibliothèques:"
ldconfig -p | grep -E "(blas|lapack|fftw)" | wc -l && echo "bibliothèques trouvées"
EOF

chmod +x /opt/hpc/bin/test-packages

# =============================================================================
# 10. OPTIMISATIONS FINALES
# =============================================================================
log "⚡ Optimisations finales..."

# Cache des bibliothèques
ldconfig

# Configuration de Jupyter pour accès distant
mkdir -p /etc/jupyter
cat > /etc/jupyter/jupyter_notebook_config.py << 'EOF'
c.NotebookApp.ip = '0.0.0.0'
c.NotebookApp.port = 8888
c.NotebookApp.open_browser = False
c.NotebookApp.allow_root = True
c.NotebookApp.token = ''
c.NotebookApp.password = ''
EOF

# =============================================================================
# 11. INFORMATIONS FINALES
# =============================================================================
log "✅ Installation des packages scientifiques terminée!"

cat << 'EOF'

=============================================================================
🎉 PACKAGES SCIENTIFIQUES INSTALLÉS
=============================================================================

✅ Python 3.10 + packages scientifiques (NumPy, SciPy, Pandas, etc.)
✅ R 4.3 + Tidyverse et packages statistiques
✅ Octave, Maxima, Scilab
✅ LaTeX complet pour publications
✅ Bibliothèques HPC (BLAS, LAPACK, FFTW, GSL)
✅ Outils de bioinformatique + Conda/Bioconda
✅ Outils de développement (GCC, Clang, CMake)
✅ Environment Modules configuré
✅ Jupyter Lab configuré

📊 STATA:
   - Répertoire préparé: /opt/stata/
   - Documentation: /opt/stata/INSTALLATION_STATA.md
   - Script de test: /opt/stata/test-stata.do

🔧 COMMANDES UTILES:
   - Test packages: /opt/hpc/bin/test-packages
   - Modules: module avail
   - Jupyter: jupyter lab --allow-root
   - Exemples: /opt/hpc/examples/

📚 EXEMPLES HPC:
   - Python MPI: /opt/hpc/examples/example-python-hpc.py
   - R parallèle: /opt/hpc/examples/example-r-hpc.R

🔗 USAGE SLURM:
   srun -n 4 python3 /opt/hpc/examples/example-python-hpc.py
   srun Rscript /opt/hpc/examples/example-r-hpc.R

=============================================================================
EOF

log "🏁 Script 06-packages.sh terminé"
