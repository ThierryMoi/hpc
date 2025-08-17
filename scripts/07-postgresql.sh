#!/bin/bash
# =============================================================================
# 07-postgresql.sh - Installation et configuration de PostgreSQL pour HPC
# =============================================================================
# Usage: bash 07-postgresql.sh
# Description: Installe PostgreSQL avec optimisations HPC et bases de données
# Prérequis: 00-base.sh
# =============================================================================

set -e

SCRIPT_NAME="[POSTGRESQL]"
LOG_FILE="/var/log/hpc-postgresql.log"
PG_VERSION="15"
DB_PASSWORD="PostgresHPC2025!"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $SCRIPT_NAME $1" | tee -a "$LOG_FILE"
}

log "🚀 Installation de PostgreSQL pour HPC"

# =============================================================================
# 1. INSTALLATION DE POSTGRESQL
# =============================================================================
log "📦 Installation de PostgreSQL $PG_VERSION..."

export DEBIAN_FRONTEND=noninteractive

# Repository officiel PostgreSQL
wget -qO- https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add -
echo "deb http://apt.postgresql.org/pub/repos/apt/ jammy-pgdg main" > /etc/apt/sources.list.d/pgdg.list

apt-get update
apt-get install -y \
    postgresql-$PG_VERSION \
    postgresql-client-$PG_VERSION \
    postgresql-contrib-$PG_VERSION \
    postgresql-server-dev-$PG_VERSION \
    postgresql-plpython3-$PG_VERSION \
    postgresql-$PG_VERSION-postgis-3 \
    pgadmin4 \
    python3-psycopg2

# =============================================================================
# 2. CONFIGURATION POSTGRESQL POUR HPC
# =============================================================================
log "⚙️  Configuration PostgreSQL pour charges HPC..."

# Arrêter PostgreSQL pour configuration
systemctl stop postgresql

# Configuration optimisée pour HPC
PG_CONFIG="/etc/postgresql/$PG_VERSION/main/postgresql.conf"
PG_HBA="/etc/postgresql/$PG_VERSION/main/pg_hba.conf"

# Backup des fichiers de configuration
cp $PG_CONFIG $PG_CONFIG.backup
cp $PG_HBA $PG_HBA.backup

# Configuration principale PostgreSQL
cat > $PG_CONFIG << EOF
# PostgreSQL Configuration pour HPC Cluster
# Version: $PG_VERSION

#------------------------------------------------------------------------------
# CONNEXIONS ET AUTHENTIFICATION
#------------------------------------------------------------------------------
listen_addresses = '*'
port = 5432
max_connections = 500
superuser_reserved_connections = 5

#------------------------------------------------------------------------------
# MÉMOIRE
#------------------------------------------------------------------------------
shared_buffers = 4GB                   # 25% de la RAM (16GB total)
effective_cache_size = 12GB            # 75% de la RAM
work_mem = 32MB                        # Mémoire par opération
maintenance_work_mem = 1GB             # Maintenance (VACUUM, etc.)
max_wal_size = 4GB
min_wal_size = 1GB

#------------------------------------------------------------------------------
# PERFORMANCES REQUÊTES
#------------------------------------------------------------------------------
random_page_cost = 1.1                 # SSD optimisé
effective_io_concurrency = 200         # Concurrent I/O (SSD)
max_worker_processes = 16              # Processus parallèles
max_parallel_workers = 16              # Workers parallèles max
max_parallel_workers_per_gather = 8    # Workers par requête
max_parallel_maintenance_workers = 4   # Maintenance parallèle

#------------------------------------------------------------------------------
# ÉCRITURE ET DURABILITÉ
#------------------------------------------------------------------------------
synchronous_commit = off               # Performance vs durabilité
wal_buffers = 64MB
checkpoint_completion_target = 0.9
checkpoint_timeout = 15min

#------------------------------------------------------------------------------
# LOGGING ET MONITORING
#------------------------------------------------------------------------------
logging_collector = on
log_directory = '/var/log/postgresql'
log_filename = 'postgresql-%Y-%m-%d.log'
log_statement = 'ddl'                  # Log DDL statements
log_duration = on
log_line_prefix = '%t [%p]: [%l-1] user=%u,db=%d,app=%a,client=%h '
log_min_duration_statement = 1000     # Log requêtes > 1s

#------------------------------------------------------------------------------
# STATISTIQUES ET AUTOVACUUM
#------------------------------------------------------------------------------
shared_preload_libraries = 'pg_stat_statements'
track_activities = on
track_counts = on
track_io_timing = on
autovacuum = on
autovacuum_max_workers = 4
autovacuum_naptime = 30s

#------------------------------------------------------------------------------
# SÉCURITÉ
#------------------------------------------------------------------------------
ssl = on
ssl_cert_file = '/etc/ssl/certs/ssl-cert-snakeoil.pem'
ssl_key_file = '/etc/ssl/private/ssl-cert-snakeoil.key'

# Timezone
timezone = 'Europe/Paris'
EOF

# Configuration des accès (pg_hba.conf)
cat > $PG_HBA << 'EOF'
# PostgreSQL HBA Configuration pour HPC
# TYPE  DATABASE        USER            ADDRESS                 METHOD

# Local connections
local   all             postgres                                peer
local   all             all                                     md5

# IPv4 connections from HPC cluster
host    all             all             172.16.0.0/18           md5
host    all             all             127.0.0.1/32            md5

# IPv6 local
host    all             all             ::1/128                 md5

# Replication (si nécessaire)
local   replication     postgres                                peer
host    replication     postgres        172.16.0.0/18           md5
EOF

# =============================================================================
# 3. DÉMARRAGE ET CONFIGURATION INITIALE
# =============================================================================
log "🚀 Démarrage de PostgreSQL..."

systemctl start postgresql
systemctl enable postgresql

# Attendre que PostgreSQL soit prêt
sleep 5

# Configuration du mot de passe postgres
sudo -u postgres psql -c "ALTER USER postgres PASSWORD '$DB_PASSWORD';"

# =============================================================================
# 4. CRÉATION DES BASES DE DONNÉES HPC
# =============================================================================
log "🗄️  Création des bases de données HPC..."

# Base de données pour les résultats HPC
sudo -u postgres createdb hpc_results -O postgres
sudo -u postgres psql hpc_results << EOF
COMMENT ON DATABASE hpc_results IS 'Base de données pour les résultats des calculs HPC';

-- Table pour les jobs Slurm
CREATE TABLE slurm_jobs (
    job_id BIGINT PRIMARY KEY,
    user_name VARCHAR(50),
    job_name VARCHAR(255),
    partition VARCHAR(50),
    account VARCHAR(50),
    state VARCHAR(20),
    nodes TEXT,
    cpus INTEGER,
    submit_time TIMESTAMP,
    start_time TIMESTAMP,
    end_time TIMESTAMP,
    elapsed_time INTERVAL,
    working_directory TEXT,
    exit_code INTEGER,
    CONSTRAINT valid_state CHECK (state IN ('PENDING', 'RUNNING', 'COMPLETED', 'FAILED', 'CANCELLED'))
);

-- Index pour les requêtes fréquentes
CREATE INDEX idx_slurm_jobs_user ON slurm_jobs(user_name);
CREATE INDEX idx_slurm_jobs_submit_time ON slurm_jobs(submit_time);
CREATE INDEX idx_slurm_jobs_state ON slurm_jobs(state);

-- Table pour les résultats scientifiques
CREATE TABLE scientific_results (
    result_id SERIAL PRIMARY KEY,
    job_id BIGINT REFERENCES slurm_jobs(job_id),
    experiment_name VARCHAR(255),
    parameters JSONB,
    results JSONB,
    output_files TEXT[],
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Index pour recherche dans JSON
CREATE INDEX idx_scientific_results_params ON scientific_results USING gin(parameters);
CREATE INDEX idx_scientific_results_results ON scientific_results USING gin(results);

GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO postgres;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO postgres;
EOF

# Base de données pour les données partagées
sudo -u postgres createdb hpc_shared_data -O postgres
sudo -u postgres psql hpc_shared_data << EOF
COMMENT ON DATABASE hpc_shared_data IS 'Base de données pour les données partagées du cluster';

-- Table pour les datasets
CREATE TABLE datasets (
    dataset_id SERIAL PRIMARY KEY,
    name VARCHAR(255) UNIQUE NOT NULL,
    description TEXT,
    file_path TEXT,
    size_bytes BIGINT,
    format VARCHAR(50),
    owner VARCHAR(50),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    last_accessed TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    access_count INTEGER DEFAULT 0
);

-- Table pour les métadonnées
CREATE TABLE dataset_metadata (
    metadata_id SERIAL PRIMARY KEY,
    dataset_id INTEGER REFERENCES datasets(dataset_id),
    key VARCHAR(255),
    value TEXT,
    data_type VARCHAR(50)
);

-- Table pour les références bibliographiques
CREATE TABLE references (
    ref_id SERIAL PRIMARY KEY,
    dataset_id INTEGER REFERENCES datasets(dataset_id),
    title TEXT,
    authors TEXT,
    journal VARCHAR(255),
    year INTEGER,
    doi VARCHAR(255),
    url TEXT
);

GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO postgres;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO postgres;
EOF

# =============================================================================
# 5. CRÉATION DES UTILISATEURS
# =============================================================================
log "👤 Création des utilisateurs PostgreSQL..."

# Utilisateur pour Slurm accounting
sudo -u postgres psql << EOF
CREATE USER slurm_acct WITH PASSWORD '$DB_PASSWORD';
GRANT CONNECT ON DATABASE hpc_results TO slurm_acct;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO slurm_acct;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO slurm_acct;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO slurm_acct;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO slurm_acct;
EOF

# Utilisateur pour les données partagées
sudo -u postgres psql << EOF
CREATE USER hpc_data WITH PASSWORD '$DB_PASSWORD';
GRANT CONNECT ON DATABASE hpc_shared_data TO hpc_data;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO hpc_data;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO hpc_data;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO hpc_data;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO hpc_data;
EOF

# Utilisateur lecture seule pour consultation
sudo -u postgres psql << EOF
CREATE USER hpc_readonly WITH PASSWORD '$DB_PASSWORD';
GRANT CONNECT ON DATABASE hpc_results, hpc_shared_data TO hpc_readonly;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO hpc_readonly;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO hpc_readonly;
EOF

# =============================================================================
# 6. INSTALLATION D'EXTENSIONS
# =============================================================================
log "🔧 Installation des extensions PostgreSQL..."

# Extensions utiles pour HPC
sudo -u postgres psql hpc_results << EOF
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
CREATE EXTENSION IF NOT EXISTS btree_gin;
CREATE EXTENSION IF NOT EXISTS btree_gist;
CREATE EXTENSION IF NOT EXISTS hstore;
CREATE EXTENSION IF NOT EXISTS uuid-ossp;
EOF

sudo -u postgres psql hpc_shared_data << EOF
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS hstore;
CREATE EXTENSION IF NOT EXISTS uuid-ossp;
EOF

# =============================================================================
# 7. SCRIPTS DE GESTION
# =============================================================================
log "🔧 Installation des scripts de gestion..."

mkdir -p /opt/hpc/postgresql

# Script de backup
cat > /opt/hpc/postgresql/backup.sh << 'EOF'
#!/bin/bash
BACKUP_DIR="/opt/hpc/backups/postgresql"
DATE=$(date +%Y%m%d_%H%M%S)

mkdir -p $BACKUP_DIR

echo "Backup PostgreSQL HPC - $DATE"
sudo -u postgres pg_dumpall > $BACKUP_DIR/full_backup_$DATE.sql
sudo -u postgres pg_dump hpc_results > $BACKUP_DIR/hpc_results_$DATE.sql
sudo -u postgres pg_dump hpc_shared_data > $BACKUP_DIR/hpc_shared_data_$DATE.sql

# Compression
gzip $BACKUP_DIR/*_$DATE.sql

# Nettoyage (garder 30 jours)
find $BACKUP_DIR -name "*.sql.gz" -mtime +30 -delete

echo "Backup terminé: $BACKUP_DIR"
EOF

chmod +x /opt/hpc/postgresql/backup.sh

# Script de monitoring
cat > /opt/hpc/bin/postgres-monitor << 'EOF'
#!/bin/bash
echo "=== MONITORING POSTGRESQL ==="
echo
echo "Status du service:"
systemctl status postgresql --no-pager
echo
echo "Connexions actives:"
sudo -u postgres psql -c "SELECT datname, usename, application_name, client_addr, state FROM pg_stat_activity WHERE state = 'active';"
echo
echo "Statistiques des bases:"
sudo -u postgres psql -c "SELECT datname, numbackends, xact_commit, xact_rollback, blks_read, blks_hit FROM pg_stat_database;"
echo
echo "Requêtes lentes (top 10):"
sudo -u postgres psql hpc_results -c "SELECT query, calls, total_time, mean_time FROM pg_stat_statements ORDER BY total_time DESC LIMIT 10;" 2>/dev/null || echo "Extension pg_stat_statements non activée"
EOF

chmod +x /opt/hpc/bin/postgres-monitor

# Script de test
cat > /opt/hpc/postgresql/test.sh << 'EOF'
#!/bin/bash
echo "=== TEST POSTGRESQL HPC ==="
echo
echo "Test de connexion:"
sudo -u postgres psql -c "SELECT version();"
echo
echo "Test des bases de données:"
sudo -u postgres psql -l
echo
echo "Test insertion dans hpc_results:"
sudo -u postgres psql hpc_results -c "
INSERT INTO slurm_jobs (job_id, user_name, job_name, partition, state, submit_time) 
VALUES (999999, 'test', 'test_job', 'compute', 'COMPLETED', NOW());
SELECT * FROM slurm_jobs WHERE job_id = 999999;
DELETE FROM slurm_jobs WHERE job_id = 999999;
"
echo "Test terminé avec succès!"
EOF

chmod +x /opt/hpc/postgresql/test.sh

# =============================================================================
# 8. CONFIGURATION DU FIREWALL
# =============================================================================
log "🔒 Configuration du firewall..."

ufw allow 5432/tcp comment "PostgreSQL"

# =============================================================================
# 9. INTÉGRATION AVEC PYTHON/R
# =============================================================================
log "🔧 Configuration pour Python/R..."

# Installation des drivers
pip3 install psycopg2-binary sqlalchemy pandas

# Script Python d'exemple
cat > /opt/hpc/examples/postgres_example.py << 'EOF'
#!/usr/bin/env python3
"""
Exemple d'utilisation de PostgreSQL avec Python pour HPC
"""
import psycopg2
import pandas as pd
from sqlalchemy import create_engine

# Configuration de connexion
DB_CONFIG = {
    'host': '172.16.0.212',
    'database': 'hpc_results',
    'user': 'hpc_data',
    'password': 'PostgresHPC2025!'
}

def connect_to_db():
    """Connexion à PostgreSQL"""
    conn = psycopg2.connect(**DB_CONFIG)
    return conn

def insert_job_result(job_id, experiment_name, parameters, results):
    """Insérer un résultat d'expérience"""
    conn = connect_to_db()
    cur = conn.cursor()
    
    query = """
    INSERT INTO scientific_results (job_id, experiment_name, parameters, results)
    VALUES (%s, %s, %s, %s)
    """
    
    cur.execute(query, (job_id, experiment_name, parameters, results))
    conn.commit()
    cur.close()
    conn.close()

def get_results_as_dataframe():
    """Récupérer les résultats sous forme de DataFrame"""
    engine = create_engine(f"postgresql://{DB_CONFIG['user']}:{DB_CONFIG['password']}@{DB_CONFIG['host']}/{DB_CONFIG['database']}")
    
    query = "SELECT * FROM scientific_results ORDER BY created_at DESC LIMIT 100"
    df = pd.read_sql(query, engine)
    
    return df

if __name__ == "__main__":
    print("Test connexion PostgreSQL")
    conn = connect_to_db()
    print("✅ Connexion réussie")
    conn.close()
EOF

chmod +x /opt/hpc/examples/postgres_example.py

# =============================================================================
# 10. CRON JOBS POUR MAINTENANCE
# =============================================================================
log "⏰ Configuration des tâches de maintenance..."

# Backup quotidien
echo "0 2 * * * root /opt/hpc/postgresql/backup.sh" >> /etc/crontab

# Analyse des statistiques
echo "0 3 * * 0 postgres vacuumdb --all --analyze" >> /etc/crontab

# =============================================================================
# 11. INFORMATIONS FINALES
# =============================================================================
log "✅ Configuration PostgreSQL terminée!"

cat << EOF

=============================================================================
🎉 POSTGRESQL HPC CONFIGURÉ AVEC SUCCÈS
=============================================================================

📍 Serveur: 172.16.0.212:5432
🗄️  Bases de données:
   - hpc_results (résultats des calculs)
   - hpc_shared_data (données partagées)

👤 UTILISATEURS:
   - postgres / $DB_PASSWORD (admin)
   - slurm_acct / $DB_PASSWORD (comptabilité Slurm)
   - hpc_data / $DB_PASSWORD (données partagées)
   - hpc_readonly / $DB_PASSWORD (lecture seule)

✅ Extensions installées (PostGIS, hstore, pg_stat_statements)
✅ Tables créées pour jobs Slurm et résultats scientifiques
✅ Optimisations HPC appliquées
✅ Scripts de backup et monitoring
✅ Firewall configuré

🔧 COMMANDES UTILES:
   - Monitoring: /opt/hpc/bin/postgres-monitor
   - Backup: /opt/hpc/postgresql/backup.sh
   - Test: /opt/hpc/postgresql/test.sh
   - Connexion: psql -h 172.16.0.212 -U hpc_data hpc_results

📊 MONITORING:
   - Netdata: http://172.16.0.212:19999
   - Logs: /var/log/postgresql/

🔗 INTÉGRATION:
   - Python: voir /opt/hpc/examples/postgres_example.py
   - Slurm accounting: configuré pour connexion automatique

📈 PERFORMANCE:
   - Mémoire partagée: 4GB
   - Cache effectif: 12GB  
   - Connexions max: 500
   - Workers parallèles: 16

=============================================================================
EOF

log "🏁 Script 07-postgresql.sh terminé"
