#!/usr/bin/env bash
# infra/setup-postgres-backup-mirror.sh
#
# Idempotente. Instala no **oracle-dev-box** (VM de desenvolvimento) o espelho
# OFF-SITE dos dumps de produção — a peça que faltava em
# infra/setup-postgres-backup.sh, que só fazia backup local.
#
# São duas VMs separadas: o banco vive no oracle-app-box, o espelho fica aqui.
# Perder a VM de produção deixa de ser perda total.
#
# ## Por que PULL e não push
#
# O oracle-app-box NÃO guarda credencial nenhuma para alcançar esta VM. Quem
# inicia a cópia é o destino. Isso importa: num comprometimento da produção, o
# atacante não encontra chave para apagar ou corromper as cópias off-site —
# que é exatamente o cenário em que o backup precisa existir.
#
# ## Por que ssh+cat e não rsync
#
# rsync não está instalado em nenhuma das duas VMs, e instalar pacote na
# produção é mudança que não precisa acontecer. Os dumps são imutáveis e
# datados: só precisamos buscar os que ainda não temos — nunca sincronizar
# deleções. `ssh sudo cat` resolve sem dependência nova.
#
# Uso (rodar NESTA VM, a de dev):
#   bash infra/setup-postgres-backup-mirror.sh
#
# Restore a partir do espelho: ver docs/deploy-runbook.md.

set -euo pipefail

info() { echo "[INFO]  $*"; }
ok()   { echo "[OK]    $*"; }
warn() { echo "[WARN]  $*"; }

MIRROR_DIR=/home/portilho/apps/controle-financeiro/backups
BIN=/usr/local/bin/controle-financeiro-pull-backups
REMOTE_HOST=oracle-app-box
REMOTE_DIR=/var/backups/controle-financeiro

# ---------------------------------------------------------------------------
# 1. Destino
# ---------------------------------------------------------------------------
#
# NÃO usar ~/apps/controle-financeiro/postgres-{production,staging}/data: apesar
# do nome, são data dirs VIVOS de containers Postgres rodando nesta VM, não
# pastas de backup. Escrever ali seria corromper banco, não guardar cópia.

info "Criando $MIRROR_DIR"
mkdir -p "$MIRROR_DIR"
chmod 700 "$MIRROR_DIR"   # dump tem dado financeiro
ok "$MIRROR_DIR pronto"

# ---------------------------------------------------------------------------
# 2. Script de pull
# ---------------------------------------------------------------------------

info "Instalando $BIN"
sudo tee "$BIN" >/dev/null <<'EOF'
#!/usr/bin/env bash
# Espelha os dumps de producao do oracle-app-box para esta VM.
# Instalado por infra/setup-postgres-backup-mirror.sh.
set -euo pipefail

MIRROR_DIR=/home/portilho/apps/controle-financeiro/backups
REMOTE_HOST=oracle-app-box
REMOTE_DIR=/var/backups/controle-financeiro
RETENTION_DAYS=30          # o espelho guarda mais que a origem (14d)
STALE_HOURS=48             # sem dump novo além disso = alarme

mkdir -p "$MIRROR_DIR"

# O diretório remoto é 700/postgres, então o glob precisa rodar sob sudo.
remote_list=$(ssh -o BatchMode=yes -o ConnectTimeout=30 "$REMOTE_HOST" \
  "sudo bash -c 'ls -1 $REMOTE_DIR/*.dump 2>/dev/null'" || true)

if [ -z "$remote_list" ]; then
  echo "ERRO: nenhum dump encontrado em $REMOTE_HOST:$REMOTE_DIR" >&2
  exit 1
fi

novos=0
while IFS= read -r remote_file; do
  [ -n "$remote_file" ] || continue
  base=$(basename "$remote_file")
  dest="$MIRROR_DIR/$base"

  [ -f "$dest" ] && continue   # dumps sao imutaveis: ja temos, pula

  echo "Puxando $base"
  if ! ssh -o BatchMode=yes -o ConnectTimeout=30 "$REMOTE_HOST" \
        "sudo cat '$remote_file'" > "${dest}.partial"; then
    echo "ERRO: falha ao copiar $base" >&2
    rm -f "${dest}.partial"
    continue
  fi

  # Verifica AQUI, no destino: uma copia truncada no meio do caminho ainda e um
  # arquivo. Sem isso o espelho acumularia lixo com cara de backup.
  if ! pg_restore --list "${dest}.partial" >/dev/null 2>&1; then
    echo "ERRO: $base chegou ilegivel (pg_restore --list falhou) — descartando" >&2
    rm -f "${dest}.partial"
    continue
  fi

  mv "${dest}.partial" "$dest"
  chmod 600 "$dest"
  echo "OK: $base ($(du -h "$dest" | cut -f1))"
  novos=$((novos + 1))
done <<< "$remote_list"

echo "novos: $novos"

# Retencao + limpeza de copias interrompidas.
find "$MIRROR_DIR" -name "*.dump" -type f -mtime "+${RETENTION_DAYS}" -print -delete
find "$MIRROR_DIR" -name "*.partial" -type f -mtime +1 -print -delete

total=$(find "$MIRROR_DIR" -name "*.dump" | wc -l)
echo "espelhados: $total dumps"

# Alarme de obsolescencia: backup que para de chegar em silencio e o mesmo que
# nao ter backup. Sai != 0 pro systemd marcar a unidade como falha.
recente=$(find "$MIRROR_DIR" -name "*.dump" -mmin "-$((STALE_HOURS * 60))" | wc -l)
if [ "$recente" -eq 0 ]; then
  echo "ALARME: nenhum dump novo em ${STALE_HOURS}h — backup de producao pode estar quebrado" >&2
  exit 1
fi

exit 0
EOF

sudo chmod 755 "$BIN"
ok "$BIN instalado"

# ---------------------------------------------------------------------------
# 3. systemd timer
# ---------------------------------------------------------------------------
#
# 06:00 UTC = 1h depois do dump na produção (05:00 UTC), pra o arquivo do dia
# já existir quando o pull rodar.

info "Instalando unidades systemd"
sudo tee /etc/systemd/system/controle-financeiro-backup-mirror.service >/dev/null <<EOF
[Unit]
Description=Espelho off-site dos dumps de producao (controle-financeiro)
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
User=portilho
Environment=HOME=/home/portilho
ExecStart=$BIN
EOF

sudo tee /etc/systemd/system/controle-financeiro-backup-mirror.timer >/dev/null <<'EOF'
[Unit]
Description=Espelho diario dos dumps de producao (controle-financeiro)

[Timer]
OnCalendar=*-*-* 06:00:00 UTC
RandomizedDelaySec=600
Persistent=true

[Install]
WantedBy=timers.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now controle-financeiro-backup-mirror.timer
ok "timer habilitado"

# ---------------------------------------------------------------------------
# 4. Primeira execução (valida o caminho inteiro)
# ---------------------------------------------------------------------------

info "Rodando o primeiro espelhamento"
if sudo systemctl start controle-financeiro-backup-mirror.service; then
  ok "espelhamento executado"
else
  warn "falhou — ver: journalctl -u controle-financeiro-backup-mirror.service"
fi

echo
info "Estado:"
systemctl list-timers controle-financeiro-backup-mirror.timer --no-pager || true
ls -lh "$MIRROR_DIR" || true
