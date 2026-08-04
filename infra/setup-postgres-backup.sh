#!/usr/bin/env bash
# infra/setup-postgres-backup.sh
#
# Idempotente. Instala o backup diário do Postgres de PRODUÇÃO no
# oracle-app-box: script de dump + systemd timer + retenção.
#
# Contexto: o Postgres roda na MESMA VM da app e, até 2026-08-03, não havia
# backup nenhum (sem pg_dump agendado, `archive_mode = off`). Os dados não são
# reconstruíveis pelo Pluggy — título melhorado, tags, vínculos (RF23), estornos
# (RF10) e consolidação são trabalho manual do usuário.
#
# ⚠️ ESCOPO: isto é backup LOCAL, no mesmo disco do banco. Protege contra
# migration ruim, bug da app, DELETE acidental e drop de tabela. NÃO protege
# contra perda da VM. Para isso, configure o envio off-site — ver BACKUP_REMOTE
# em /etc/default/controle-financeiro-backup (seção no fim deste script).
#
# O que instala:
#   1. /usr/local/bin/controle-financeiro-backup  — dump + verificação + retenção
#   2. /etc/default/controle-financeiro-backup     — config (retenção, destino off-site)
#   3. systemd service + timer                     — diário às 05:00 UTC (02:00 BRT)
#
# Uso:
#   ssh oracle-app-box 'bash -s' < infra/setup-postgres-backup.sh
#
# Restore: ver docs/deploy-runbook.md, seção "Restore do banco".
#
# Atenção: requer sudo no host remoto.

set -euo pipefail

info() { echo "[INFO]  $*"; }
ok()   { echo "[OK]    $*"; }
warn() { echo "[WARN]  $*"; }

BACKUP_DIR=/var/backups/controle-financeiro
BIN=/usr/local/bin/controle-financeiro-backup
DEFAULTS=/etc/default/controle-financeiro-backup

# ---------------------------------------------------------------------------
# 1. Diretório de destino
# ---------------------------------------------------------------------------

info "Criando $BACKUP_DIR"
sudo mkdir -p "$BACKUP_DIR"
sudo chown postgres:postgres "$BACKUP_DIR"
sudo chmod 700 "$BACKUP_DIR"   # dump tem dado financeiro: só o dono lê
ok "$BACKUP_DIR pronto"

# ---------------------------------------------------------------------------
# 2. Config
# ---------------------------------------------------------------------------

if [ -f "$DEFAULTS" ]; then
  info "$DEFAULTS já existe — preservando (não sobrescreve config do usuário)"
else
  info "Escrevendo $DEFAULTS"
  sudo tee "$DEFAULTS" >/dev/null <<'EOF'
# Config do backup do Postgres — controle-financeiro.

# Quantos dumps diários manter. 14 dias ≈ 500 MB com o volume atual (~30 MB/dump).
RETENTION_DAYS=14

# Envio OFF-SITE (o que protege contra perda da VM). Vazio = só backup local.
#
# Aceita qualquer destino de `rsync` — ex.: "user@host:/caminho/backups".
# Requer rsync instalado e chave SSH sem passphrase para o destino.
# Alternativa: instale o `oci` CLI e troque o hook por `oci os object put`.
BACKUP_REMOTE=""
EOF
  ok "$DEFAULTS escrito (BACKUP_REMOTE vazio — configure para ter off-site)"
fi

# ---------------------------------------------------------------------------
# 3. Script de backup
# ---------------------------------------------------------------------------
#
# Só o banco principal. Os outros três (_cache, _queue, _cable) são do
# solid_cache/solid_queue/solid_cable: estado efêmero, recriado pelo db:prepare
# no boot. Fazer dump deles só gastaria disco.

info "Instalando $BIN"
sudo tee "$BIN" >/dev/null <<'EOF'
#!/usr/bin/env bash
# Dump diário do Postgres de produção. Instalado por infra/setup-postgres-backup.sh.
set -euo pipefail

DB=controle_financeiro_production
BACKUP_DIR=/var/backups/controle-financeiro
RETENTION_DAYS=14
BACKUP_REMOTE=""

# shellcheck disable=SC1091
[ -f /etc/default/controle-financeiro-backup ] && . /etc/default/controle-financeiro-backup

stamp=$(date -u +%Y%m%dT%H%M%SZ)
dest="$BACKUP_DIR/${DB}_${stamp}.dump"

echo "Dump de $DB -> $dest"

# -Fc: formato custom (comprimido, permite restore seletivo com pg_restore).
# Escreve em .partial e só renomeia no fim — assim um dump interrompido nunca
# é confundido com um bom pela retenção nem pelo restore.
pg_dump -Fc --no-password "$DB" > "${dest}.partial"

# Um dump truncado ainda é um arquivo: valida que o catálogo é legível ANTES de
# promover. Sem isso, 14 dias de lixo passariam por 14 dias de backup.
if ! pg_restore --list "${dest}.partial" >/dev/null 2>&1; then
  echo "ERRO: dump ilegível (pg_restore --list falhou) — descartando" >&2
  rm -f "${dest}.partial"
  exit 1
fi

size=$(stat -c %s "${dest}.partial")
if [ "$size" -lt 100000 ]; then
  echo "ERRO: dump suspeito de tão pequeno (${size} bytes) — descartando" >&2
  rm -f "${dest}.partial"
  exit 1
fi

mv "${dest}.partial" "$dest"
chmod 600 "$dest"
echo "OK: $(du -h "$dest" | cut -f1)"

# Off-site. Falha aqui NÃO invalida o backup local — avisa e sai não-zero pro
# journal/systemd marcar, mas o dump já está no disco.
if [ -n "$BACKUP_REMOTE" ]; then
  echo "Enviando para $BACKUP_REMOTE"
  if rsync -a --timeout=300 "$dest" "$BACKUP_REMOTE/"; then
    echo "OK: off-site enviado"
  else
    echo "ERRO: envio off-site falhou (backup local está OK)" >&2
    offsite_failed=1
  fi
else
  echo "AVISO: BACKUP_REMOTE vazio — backup só LOCAL, não protege contra perda da VM" >&2
fi

# Retenção: remove dumps completos antigos. `.partial` órfão (queda de energia
# no meio do dump) sai junto, senão acumularia pra sempre.
find "$BACKUP_DIR" -name "${DB}_*.dump" -type f -mtime "+${RETENTION_DAYS}" -print -delete
find "$BACKUP_DIR" -name "*.partial" -type f -mtime +1 -print -delete

echo "Retidos: $(find "$BACKUP_DIR" -name "${DB}_*.dump" | wc -l) dumps"
exit "${offsite_failed:-0}"
EOF

sudo chmod 755 "$BIN"
ok "$BIN instalado"

# ---------------------------------------------------------------------------
# 4. systemd service + timer
# ---------------------------------------------------------------------------
#
# Roda como `postgres` (peer auth no socket local — sem senha em lugar nenhum).

info "Instalando unidades systemd"
sudo tee /etc/systemd/system/controle-financeiro-backup.service >/dev/null <<EOF
[Unit]
Description=Backup do Postgres de producao (controle-financeiro)
After=postgresql.service
Requires=postgresql.service

[Service]
Type=oneshot
User=postgres
ExecStart=$BIN
# Dump comprimido é CPU-bound; a VM é compartilhada com a app.
Nice=10
IOSchedulingClass=idle
EOF

# 05:00 UTC = 02:00 BRT: fora do sync noturno do Pluggy (~22:45 UTC) e do
# pull horário. RandomizedDelaySec espalha pra não bater sempre no mesmo minuto.
sudo tee /etc/systemd/system/controle-financeiro-backup.timer >/dev/null <<'EOF'
[Unit]
Description=Backup diario do Postgres (controle-financeiro)

[Timer]
OnCalendar=*-*-* 05:00:00 UTC
RandomizedDelaySec=300
Persistent=true

[Install]
WantedBy=timers.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now controle-financeiro-backup.timer
ok "timer habilitado"

# ---------------------------------------------------------------------------
# 5. Primeiro backup agora (valida o caminho inteiro)
# ---------------------------------------------------------------------------

info "Rodando o primeiro backup para validar"
if sudo systemctl start controle-financeiro-backup.service; then
  ok "backup executado"
else
  warn "backup falhou — ver: journalctl -u controle-financeiro-backup.service"
fi

echo
info "Estado:"
sudo systemctl list-timers controle-financeiro-backup.timer --no-pager || true
sudo ls -lh "$BACKUP_DIR" || true

echo
if grep -q 'BACKUP_REMOTE=""' "$DEFAULTS" 2>/dev/null; then
  warn "BACKUP_REMOTE está vazio: o backup é LOCAL, no mesmo disco do banco."
  warn "Isso cobre migration ruim / DELETE acidental, mas NÃO perda da VM."
  warn "Configure em $DEFAULTS para fechar essa lacuna."
fi
