#!/usr/bin/env bash
# Generates dummy bait files (decoys) into .state/bait/* and records them
# in the bait manifest. All content is fake/dummy data - never real secrets.
# Sourced, not executed - deliberately does not set shell options (see
# shared/config.sh for why).

bait_generate_env() {
    local path="${BNB_BAIT_DECEPTION_DIR}/.env"
    cat > "$path" <<'EOF'
# WARNING: dummy lab credentials - not real, safe to leak
APP_ENV=production
DB_HOST=127.0.0.1
DB_USER=admin
DB_PASSWORD=SuperSecretPass123!
AWS_ACCESS_KEY_ID=AKIAFAKEEXAMPLE00000
AWS_SECRET_ACCESS_KEY=fAkE/exampleSecretKeyDoNotUse0000000000
STRIPE_API_KEY=stripe_test_FAKE000000000000000000
EOF
    [ -s "$path" ] || return 1
    state_manifest_add "$path"
}

bait_generate_passwords() {
    local path="${BNB_BAIT_BACKUPS_DIR}/passwords.txt"
    cat > "$path" <<'EOF'
# dummy leaked credential list - lab bait, not real accounts
admin:admin123
root:toor
svc-backup:B4ckup!2024
EOF
    [ -s "$path" ] || return 1
    state_manifest_add "$path"
}

bait_generate_shadow_dump() {
    local path="${BNB_BAIT_BACKUPS_DIR}/shadow.bak"
    cat > "$path" <<'EOF'
root:$6$fakesalt$FAKEHASHDONOTUSE0000000000000000000000000000000000000000000000000000000000:19000:0:99999:7:::
admin:$6$fakesalt$FAKEHASHDONOTUSE1111111111111111111111111111111111111111111111111111111111:19000:0:99999:7:::
EOF
    [ -s "$path" ] || return 1
    state_manifest_add "$path"
}

bait_generate_db_dump() {
    local path="${BNB_BAIT_BACKUPS_DIR}/production_dump.sql"
    cat > "$path" <<'EOF'
-- dummy DB backup, lab bait
CREATE TABLE users (id INT, username TEXT, password TEXT);
INSERT INTO users VALUES (1, 'admin', 'admin123');
INSERT INTO users VALUES (2, 'jdoe', 'Password1!');
EOF
    [ -s "$path" ] || return 1
    state_manifest_add "$path"
}

bait_generate_source_backup() {
    local path="${BNB_BAIT_BACKUPS_DIR}/website_backup.tar.gz"
    local tmpdir
    tmpdir="$(mktemp -d)" || return 1
    [ -n "$tmpdir" ] || return 1
    echo "<?php // dummy leaked source file ?>" > "${tmpdir}/config.php"
    tar -czf "$path" -C "$tmpdir" . || { rm -rf "$tmpdir"; return 1; }
    rm -rf "$tmpdir"
    [ -s "$path" ] || return 1
    state_manifest_add "$path"
}

bait_generate_payroll() {
    local path="${BNB_BAIT_SECRETS_DIR}/payroll_2025.csv"
    cat > "$path" <<'EOF'
employee_id,name,salary,ssn
1001,Jane Doe,95000,000-00-0000
1002,John Smith,88000,000-00-0001
EOF
    [ -s "$path" ] || return 1
    state_manifest_add "$path"
}

bait_generate_employee_db() {
    local path="${BNB_BAIT_SECRETS_DIR}/employee_records.db"
    if command -v sqlite3 >/dev/null 2>&1; then
        sqlite3 "$path" "CREATE TABLE employees (id INTEGER, name TEXT, dept TEXT); INSERT INTO employees VALUES (1,'Jane Doe','Finance');"
    else
        echo "SQLite placeholder - dummy employee records" > "$path"
    fi
    [ -s "$path" ] || return 1
    state_manifest_add "$path"
}

bait_generate_all() {
    local rc=0
    state_manifest_clear
    bait_generate_env            || { rc=1; state_incident_append "bait" "FAILED: .env"; }
    bait_generate_passwords      || { rc=1; state_incident_append "bait" "FAILED: passwords.txt"; }
    bait_generate_shadow_dump    || { rc=1; state_incident_append "bait" "FAILED: shadow.bak"; }
    bait_generate_db_dump        || { rc=1; state_incident_append "bait" "FAILED: production_dump.sql"; }
    bait_generate_source_backup  || { rc=1; state_incident_append "bait" "FAILED: website_backup.tar.gz"; }
    bait_generate_payroll        || { rc=1; state_incident_append "bait" "FAILED: payroll_2025.csv"; }
    bait_generate_employee_db    || { rc=1; state_incident_append "bait" "FAILED: employee_records.db"; }
    return "$rc"
}
