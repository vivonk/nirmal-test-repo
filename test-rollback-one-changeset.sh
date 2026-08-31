#!/usr/bin/env bash
#
# End-to-end proof that the new openlbase `rollbackOneChangeset` / `rollbackOneChangesetSql`
# commands work against a real Postgres database:
#   1. Builds liquibase-standard + liquibase-cli from ~/harness/openlbase (the fork containing
#      the new command steps).
#   2. Spins up a disposable Postgres 16 container.
#   3. Applies the full sample.changelog.yaml (27 changesets).
#   4. Rolls back ONE non-terminal changeset by id+author+path and asserts:
#        - only that changeset's schema change was undone
#        - only that row disappeared from DATABASECHANGELOG
#        - every other changeset (including ones applied AFTER the target) is untouched
#   5. Runs the SQL-preview variant and asserts it prints DELETE/DROP SQL but mutates nothing.
#   6. Runs a not-found case (wrong author) and asserts it fails loudly and mutates nothing.
#
# Exit code 0 = every assertion passed. Any failure prints [FAIL] and aborts immediately.

set -uo pipefail

OPENLBASE_DIR="$HOME/harness/openlbase"
REPO_DIR="$HOME/harness/nirmal-test-repo"
CONTAINER_NAME="rollback-proof-pg"
DB_PORT=5433   # distinct from the default 5432 dev container so this never collides with it
PGPASSWORD_FOR_PSQL=password

PASS=0
FAIL=0

pass() { PASS=$((PASS+1)); echo "[PASS] $1"; }
fail() { FAIL=$((FAIL+1)); echo "[FAIL] $1"; }

cleanup() {
  echo "--- Cleaning up container ${CONTAINER_NAME} ---"
  docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
}
trap cleanup EXIT

psql_query() {
  docker exec -e PGPASSWORD="$PGPASSWORD_FOR_PSQL" "$CONTAINER_NAME" psql -U user -d postgres -tA -c "$1"
}

echo "=================================================================="
echo " 1. Building liquibase-standard + liquibase-cli from openlbase"
echo "=================================================================="
cd "$OPENLBASE_DIR" || { fail "openlbase directory not found"; exit 1; }

if mvn -q -pl liquibase-standard -am install -DskipTests -Dspotbugs.skip=true -Dcheckstyle.skip=true \
   && mvn -q -pl liquibase-cli install -DskipTests -Dspotbugs.skip=true -Dcheckstyle.skip=true; then
  pass "openlbase build (liquibase-standard, liquibase-cli)"
else
  fail "openlbase build"
  exit 1
fi

mvn -q -pl liquibase-cli dependency:build-classpath -Dmdep.outputFile=/tmp/rollback-proof-classpath.txt
CP="$OPENLBASE_DIR/liquibase-cli/target/classes:$OPENLBASE_DIR/liquibase-standard/target/classes:$(cat /tmp/rollback-proof-classpath.txt):$REPO_DIR/lib/postgresql-42.7.6.jar"

run_liquibase() {
  java -cp "$CP" liquibase.integration.commandline.LiquibaseCommandLine \
    --url="jdbc:postgresql://localhost:${DB_PORT}/postgres" --username=user --password=password \
    --changelog-file=sample.changelog.yaml "$@"
}

echo "=================================================================="
echo " 2. Starting disposable Postgres container (port ${DB_PORT})"
echo "=================================================================="
docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
docker run -d --name "$CONTAINER_NAME" \
  -e POSTGRES_USER=user -e POSTGRES_PASSWORD=password -e POSTGRES_DB=postgres \
  -p "${DB_PORT}:5432" postgres:16 >/dev/null

READY=0
for _ in $(seq 1 60); do
  if docker exec -e PGPASSWORD="$PGPASSWORD_FOR_PSQL" "$CONTAINER_NAME" psql -U user -d postgres -tA -c "SELECT 1;" >/dev/null 2>&1; then
    READY=1
    break
  fi
  sleep 1
done
[ "$READY" -eq 1 ] && pass "Postgres container ready" || { fail "Postgres never became ready"; exit 1; }
# The postgres image restarts once after initdb; give it a moment to settle before the JDBC driver connects.
sleep 2

cd "$REPO_DIR" || { fail "test repo directory not found"; exit 1; }

echo "=================================================================="
echo " 3. Applying sample.changelog.yaml (27 changesets)"
echo "=================================================================="
UPDATE_OUT=$(run_liquibase update 2>&1)
if echo "$UPDATE_OUT" | grep -q "Update has been successful"; then
  pass "liquibase update applied all changesets"
else
  fail "liquibase update did not report success"
  echo "$UPDATE_OUT"
  exit 1
fi

BEFORE_COUNT=$(psql_query "SELECT count(*) FROM databasechangelog;" | tr -d '[:space:]')
[ "$BEFORE_COUNT" = "27" ] && pass "DATABASECHANGELOG has 27 rows before rollback" \
  || fail "expected 27 rows in DATABASECHANGELOG before rollback, got '$BEFORE_COUNT'"

HAS_PHONE_BEFORE=$(psql_query "SELECT count(*) FROM information_schema.columns WHERE table_name='employees' AND column_name='phone_number';" | tr -d '[:space:]')
[ "$HAS_PHONE_BEFORE" = "1" ] && pass "employees.phone_number exists before rollback (changeset 16 applied)" \
  || fail "employees.phone_number missing before rollback -- test fixture assumption broken"

echo "=================================================================="
echo " 4. rollbackOneChangeset: target changeset 16::dbe_team (non-terminal)"
echo "=================================================================="
ROLLBACK_OUT=$(run_liquibase rollback-one-changeset \
  --changeset-id=16 --changeset-author=dbe_team --changeset-path=sample.changelog.yaml 2>&1)
if echo "$ROLLBACK_OUT" | grep -q "was executed successfully"; then
  pass "rollback-one-changeset command executed successfully"
else
  fail "rollback-one-changeset command did not report success"
  echo "$ROLLBACK_OUT"
fi

HAS_PHONE_AFTER=$(psql_query "SELECT count(*) FROM information_schema.columns WHERE table_name='employees' AND column_name='phone_number';" | tr -d '[:space:]')
[ "$HAS_PHONE_AFTER" = "0" ] && pass "employees.phone_number was dropped (targeted changeset rolled back)" \
  || fail "employees.phone_number still present after rollback"

AFTER_COUNT=$(psql_query "SELECT count(*) FROM databasechangelog;" | tr -d '[:space:]')
[ "$AFTER_COUNT" = "26" ] && pass "DATABASECHANGELOG dropped from 27 to 26 rows (exactly one changeset removed)" \
  || fail "expected 26 rows in DATABASECHANGELOG after rollback, got '$AFTER_COUNT'"

STILL_HAS_16=$(psql_query "SELECT count(*) FROM databasechangelog WHERE id='16' AND author='dbe_team';" | tr -d '[:space:]')
[ "$STILL_HAS_16" = "0" ] && pass "changeset 16::dbe_team removed from DATABASECHANGELOG" \
  || fail "changeset 16::dbe_team still present in DATABASECHANGELOG"

# Prove changesets applied AFTER the rolled-back one were left completely alone.
SURVIVORS=$(psql_query "SELECT count(*) FROM databasechangelog WHERE id IN ('17','18','19','20','21');" | tr -d '[:space:]')
[ "$SURVIVORS" = "5" ] && pass "changesets 17-21 (applied AFTER the rolled-back changeset) are all still present" \
  || fail "one or more of changesets 17-21 were unexpectedly affected (got count=$SURVIVORS)"

PROJECTS_ROW=$(psql_query "SELECT count(*) FROM projects WHERE id=1;" | tr -d '[:space:]')
[ "$PROJECTS_ROW" = "1" ] && pass "projects row from changeset 17 (later changeset) still intact" \
  || fail "projects row from changeset 17 was unexpectedly affected"

echo "=================================================================="
echo " 5. rollbackOneChangesetSql: preview-only for changeset 17::dbe_team"
echo "=================================================================="
SQL_OUT=$(run_liquibase rollback-one-changeset-sql \
  --changeset-id=17 --changeset-author=dbe_team --changeset-path=sample.changelog.yaml 2>&1)
if echo "$SQL_OUT" | grep -q "DELETE FROM public.projects WHERE id = 1;"; then
  pass "rollback-one-changeset-sql printed the expected DELETE statement"
else
  fail "rollback-one-changeset-sql did not print the expected SQL"
  echo "$SQL_OUT"
fi

STILL_27_PRESENT=$(psql_query "SELECT count(*) FROM databasechangelog WHERE id='17';" | tr -d '[:space:]')
[ "$STILL_27_PRESENT" = "1" ] && pass "SQL preview did NOT mutate DATABASECHANGELOG (changeset 17 still present)" \
  || fail "SQL preview unexpectedly mutated DATABASECHANGELOG"

PROJECTS_ROW_AFTER_PREVIEW=$(psql_query "SELECT count(*) FROM projects WHERE id=1;" | tr -d '[:space:]')
[ "$PROJECTS_ROW_AFTER_PREVIEW" = "1" ] && pass "SQL preview did NOT mutate projects table" \
  || fail "SQL preview unexpectedly deleted data"

echo "=================================================================="
echo " 6. Not-found case: correct id, wrong author -- must fail loudly, mutate nothing"
echo "=================================================================="
NOTFOUND_OUT=$(run_liquibase rollback-one-changeset \
  --changeset-id=17 --changeset-author=wrong_author --changeset-path=sample.changelog.yaml 2>&1)
if echo "$NOTFOUND_OUT" | grep -q "was not found in the database's ran-changeset history"; then
  pass "not-found case produced the expected diagnostic error"
else
  fail "not-found case did not produce the expected diagnostic error"
  echo "$NOTFOUND_OUT"
fi

STILL_27_PRESENT_2=$(psql_query "SELECT count(*) FROM databasechangelog WHERE id='17';" | tr -d '[:space:]')
[ "$STILL_27_PRESENT_2" = "1" ] && pass "not-found case did NOT mutate DATABASECHANGELOG" \
  || fail "not-found case unexpectedly mutated DATABASECHANGELOG"

echo "=================================================================="
echo " SUMMARY: ${PASS} passed, ${FAIL} failed"
echo "=================================================================="
if [ "$FAIL" -eq 0 ]; then
  echo "ALL ASSERTIONS PASSED"
  exit 0
else
  echo "ONE OR MORE ASSERTIONS FAILED"
  exit 1
fi
