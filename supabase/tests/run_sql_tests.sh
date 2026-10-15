#!/usr/bin/env bash
# Teste les migrations Supabase sur un Postgres 16 jetable.
#
#   supabase/tests/run_sql_tests.sh            # tout exécuter
#   KEEP=1 supabase/tests/run_sql_tests.sh    # garder le cluster (affiche comment s'y connecter)
#   PGBIN=/chemin/bin supabase/tests/run_sql_tests.sh
#
# Étapes : initdb dans un répertoire temporaire -> démarrage sur un port libre
# (socket Unix uniquement) -> faux environnement Supabase (tests/sql/00_*.sql)
# -> migrations -> seed du contenu réel -> tests/sql/[1-9]*.sql.
# Relançable à volonté : chaque exécution crée un cluster neuf.
# Postgres refusant de tourner en root, un utilisateur système dédié est utilisé
# (PG_OS_USER, défaut « pgtest », créé si besoin quand le script tourne en root).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUPA="$(dirname "$HERE")"
PGBIN="${PGBIN:-/usr/lib/postgresql/16/bin}"
PG_OS_USER="${PG_OS_USER:-pgtest}"
DB="quinze_test"

[ -x "$PGBIN/initdb" ] || { echo "initdb introuvable dans $PGBIN (variable PGBIN)" >&2; exit 2; }

WORK="$(mktemp -d /tmp/quinze-sqltest.XXXXXX)"
RUN=()
if [ "$(id -u)" = "0" ]; then
  id "$PG_OS_USER" >/dev/null 2>&1 || useradd -m -s /bin/bash "$PG_OS_USER"
  chown "$PG_OS_USER" "$WORK"
  RUN=(runuser -u "$PG_OS_USER" --)
fi
chmod 755 "$WORK"

free_port() {
  python3 - <<'PY'
import socket
s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()
PY
}
PORT="$(free_port)"

cleanup() {
  if [ "${KEEP:-0}" = "1" ]; then
    echo "Cluster conservé : psql -h $WORK -p $PORT -U postgres $DB   (arrêt : $PGBIN/pg_ctl -D $WORK/data stop)"
    return
  fi
  "${RUN[@]}" "$PGBIN/pg_ctl" -D "$WORK/data" -m immediate stop >/dev/null 2>&1 || true
  rm -rf "$WORK"
}
trap cleanup EXIT

"${RUN[@]}" "$PGBIN/initdb" -D "$WORK/data" -U postgres --auth=trust -E UTF8 --no-locale >"$WORK/initdb.log" 2>&1
"${RUN[@]}" "$PGBIN/pg_ctl" -D "$WORK/data" -l "$WORK/pg.log" -w \
  -o "-p $PORT -k $WORK -c listen_addresses='' -c fsync=off -c synchronous_commit=off -c full_page_writes=off -c max_connections=20" \
  start >/dev/null

PSQL=("$PGBIN/psql" -h "$WORK" -p "$PORT" -U postgres -X -q -v ON_ERROR_STOP=1)
"${PSQL[@]}" -d postgres -c "create database $DB" >/dev/null
export PGOPTIONS='--client-min-messages=notice'

echo "== Postgres $("$PGBIN/postgres" --version | awk '{print $3}') sur $WORK (port $PORT)"

echo "== Faux environnement Supabase"
"${PSQL[@]}" -d "$DB" -f "$HERE/sql/00_supabase_stub.sql" >/dev/null

echo "== Migrations"
for f in "$SUPA"/migrations/*.sql; do
  echo "   $(basename "$f")"
  "${PSQL[@]}" -d "$DB" -1 -f "$f" >/dev/null
done

echo "== Seed du contenu (contenu réel, 2 chargements pour vérifier l'idempotence)"
"${PSQL[@]}" -d "$DB" -f "$SUPA/seed/content_en.sql" >/dev/null
"${PSQL[@]}" -d "$DB" -f "$SUPA/seed/content_en.sql" >/dev/null
"${PSQL[@]}" -d "$DB" -f "$SUPA/seed/seed.sql" 2>&1 | grep -v '^$' || true

FAILED=0
TOTAL=0
for t in "$HERE"/sql/[1-9]*.sql; do
  name="$(basename "$t")"
  echo "== $name"
  set +e
  out="$("${PSQL[@]}" -d "$DB" -f "$t" 2>&1)"
  rc=$?
  set -e
  echo "$out" | sed -n 's/^psql:[^ ]* NOTICE:  \(ok - .*\)$/   \1/p; s/^NOTICE:  \(ok - .*\)$/   \1/p'
  n=$(echo "$out" | grep -c 'ok - ' || true)
  TOTAL=$((TOTAL + n))
  if [ $rc -ne 0 ]; then
    FAILED=$((FAILED + 1))
    echo "   ECHEC ($name) :"
    echo "$out" | grep -v 'NOTICE:  ok - ' | sed 's/^/     /'
  fi
done

echo
if [ $FAILED -eq 0 ]; then
  echo "TOUS LES TESTS SQL PASSENT ($TOTAL assertions)"
else
  echo "$FAILED fichier(s) de test en échec ($TOTAL assertions réussies)"
  exit 1
fi
