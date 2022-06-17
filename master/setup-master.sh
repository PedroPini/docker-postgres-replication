#!/bin/bash
#allow connection with md5 encryption password
echo "host replication all 0.0.0.0/0 md5" >> "$PGDATA/pg_hba.conf"

set -e
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    CREATE USER $PG_REP_USER REPLICATION LOGIN CONNECTION LIMIT 100 ENCRYPTED PASSWORD '$PG_REP_PASSWORD';
EOSQL

cat >> ${PGDATA}/postgresql.conf <<EOF

listen_addresses = '*'
wal_level = replica
max_worker_processes = 23
max_locks_per_transaction = 1000
max_wal_senders = 8
max_replication_slots = 1
synchronous_commit = off
EOF