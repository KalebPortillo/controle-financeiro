#!/usr/bin/env bash
# infra/setup-oracle-app-box.sh
#
# Idempotente. Configura o oracle-app-box (Oracle Cloud Ampere A1 ARM64,
# Ubuntu 22.04) para servir o controle-financeiro via Kamal.
#
# Pré-requisitos no host:
#   - PostgreSQL 16 instalado e rodando
#   - Docker 24+ instalado
#   - netfilter-persistent instalado  (sudo apt install netfilter-persistent)
#   - Usuário `portilho` existente (com acesso sudo e .pgpass configurado)
#
# O que o script faz:
#   1. iptables: libera tráfego da rede Docker kamal (172.18.0.0/16) e
#      da rede bridge padrão (172.17.0.0/16) para o Postgres no host.
#   2. Postgres: adiciona `172.18.0.1` em listen_addresses (se ausente).
#   3. pg_hba.conf: adiciona regra scram-sha-256 para 172.18.0.0/16.
#   4. Persiste as regras com netfilter-persistent.
#   5. Recarrega o Postgres para aplicar as mudanças.
#
# Uso:
#   ssh oracle-app-box 'bash -s' < infra/setup-oracle-app-box.sh
#
# Atenção: requer sudo no host remoto.

set -euo pipefail

info()  { echo "[INFO]  $*"; }
ok()    { echo "[OK]    $*"; }
warn()  { echo "[WARN]  $*"; }

# ---------------------------------------------------------------------------
# 1. iptables — rede kamal (172.18.0.0/16) e bridge padrão (172.17.0.0/16)
# ---------------------------------------------------------------------------

add_iptables_rule() {
  local table="$1"; shift
  # Verifica se a regra já existe antes de inserir
  if ! sudo iptables -t filter -C "$table" "$@" 2>/dev/null; then
    sudo iptables -I "$table" 1 "$@"
    info "iptables $table $* → adicionada"
  else
    ok "iptables $table $* → já existe"
  fi
}

info "Configurando iptables..."

# Kamal usa a rede 'kamal' (172.18.0.0/16, gateway 172.18.0.1)
add_iptables_rule DOCKER-USER -s 172.18.0.0/16 -d 172.18.0.1 -j ACCEPT
add_iptables_rule INPUT        -s 172.18.0.0/16 -p tcp --dport 5432 -j ACCEPT

# Bridge padrão (172.17.0.0/16, gateway 172.17.0.1) — segurança extra
add_iptables_rule DOCKER-USER -s 172.17.0.0/16 -d 172.17.0.1 -j ACCEPT
add_iptables_rule INPUT        -s 172.17.0.0/16 -p tcp --dport 5432 -j ACCEPT

info "Persistindo regras com netfilter-persistent..."
sudo netfilter-persistent save
ok "iptables persistido."

# ---------------------------------------------------------------------------
# 2. PostgreSQL — listen_addresses
# ---------------------------------------------------------------------------

PG_CONF=$(sudo -u postgres psql -tAc "SHOW config_file;")
info "postgresql.conf: $PG_CONF"

# Adiciona 172.18.0.1 em listen_addresses se ainda não estiver lá
if sudo grep -q "^listen_addresses" "$PG_CONF"; then
  CURRENT=$(sudo grep "^listen_addresses" "$PG_CONF" | head -1)
  if echo "$CURRENT" | grep -q "172.18.0.1"; then
    ok "listen_addresses já contém 172.18.0.1."
  else
    # Extrai valor atual e acrescenta o novo IP
    NEW_VAL=$(echo "$CURRENT" | sed "s/'\\(.*\\)'/'\1, 172.18.0.1'/")
    sudo sed -i "s|^listen_addresses.*|$NEW_VAL|" "$PG_CONF"
    info "listen_addresses atualizado → $NEW_VAL"
  fi
else
  echo "listen_addresses = 'localhost, 172.18.0.1'" | sudo tee -a "$PG_CONF" > /dev/null
  info "listen_addresses adicionado ao postgresql.conf."
fi

# ---------------------------------------------------------------------------
# 3. PostgreSQL — pg_hba.conf
# ---------------------------------------------------------------------------

PG_HBA=$(sudo -u postgres psql -tAc "SHOW hba_file;")
info "pg_hba.conf: $PG_HBA"

HBA_RULE="host    all             portilho        172.18.0.0/16           scram-sha-256"

if sudo grep -qF "172.18.0.0/16" "$PG_HBA"; then
  ok "pg_hba.conf já contém regra para 172.18.0.0/16."
else
  echo "$HBA_RULE" | sudo tee -a "$PG_HBA" > /dev/null
  info "pg_hba.conf: regra 172.18.0.0/16 adicionada."
fi

# ---------------------------------------------------------------------------
# 4. Reload do Postgres
# ---------------------------------------------------------------------------

info "Recarregando PostgreSQL..."
sudo systemctl reload postgresql
ok "PostgreSQL recarregado."

# ---------------------------------------------------------------------------
# 5. Diretórios de dados do app (convenção newapp)
# ---------------------------------------------------------------------------

APP_DATA_BASE="$HOME/apps/controle-financeiro/data"

for dir in storage storage-staging; do
  TARGET="$APP_DATA_BASE/$dir"
  if [ -d "$TARGET" ]; then
    ok "Diretório $TARGET já existe."
  else
    mkdir -p "$TARGET"
    info "Diretório $TARGET criado."
  fi
done

ok "Setup concluído. oracle-app-box pronto para kamal deploy."
