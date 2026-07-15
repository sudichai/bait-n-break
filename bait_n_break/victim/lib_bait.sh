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

bait_generate_ssh_key() {
    local path="${BNB_BAIT_SECRETS_DIR}/id_rsa_victim"
    cat > "$path" <<'EOF'
-----BEGIN OPENSSH PRIVATE KEY-----
b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAABlwAAAAdzc2gtcn
NhAAAAAwEAAQAAAYEA0mDfakePrivateKeyDataNotRealLabBaitDoNotUse00000000000
0000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000
-----END OPENSSH PRIVATE KEY-----
EOF
    [ -s "$path" ] || return 1
    state_manifest_add "$path"
}

bait_generate_browser_creds() {
    local path="${BNB_BAIT_SECRETS_DIR}/browser_saved_logins.json"
    cat > "$path" <<'EOF'
{
  "logins": [
    {"host": "https://internal.company.com", "user": "admin", "password": "Sup3rS3cr3t!"},
    {"host": "https://mail.company.com", "user": "victim@company.local", "password": "MailP@ss2025"},
    {"host": "https://db-admin.company.com", "user": "root", "password": "mysql_root_2024"},
    {"host": "https://jenkins.company.local", "user": "svc-build", "password": "BuildDeploy123!"}
  ]
}
EOF
    [ -s "$path" ] || return 1
    state_manifest_add "$path"
}

bait_generate_bash_history() {
    local path="${BNB_BAIT_SECRETS_DIR}/.bash_history"
    cat > "$path" <<'EOF'
ssh admin@192.168.1.100
mysql -u root -proot production_db
ssh -i ~/.ssh/id_rsa admin@db-server.internal
sudo find / -name "*.conf" 2>/dev/null
curl -u admin:admin123 http://localhost:8080/admin
echo "export DB_PASSWORD=prod_db_pass_2025!" >> ~/.bashrc
cat /etc/shadow
sudo su -
wget http://fileserver.internal/backup/config.tar.gz
echo "backup done: svc-backup / B4ckup!2024"
export AWS_SECRET_ACCESS_KEY=fAkE/exampleSecretKeyDoNotUse0000000000
EOF
    [ -s "$path" ] || return 1
    state_manifest_add "$path"
}

bait_generate_git_secrets() {
    local path="${BNB_BAIT_SECRETS_DIR}/git_secrets_repo"
    local tmpdir
    tmpdir="$(mktemp -d)" || return 1
    mkdir -p "${tmpdir}/.git" "${tmpdir}/config"
    cat > "${tmpdir}/.env" <<'ENVEOF'
DB_PASSWORD=prod_db_pass_2025!
AWS_ACCESS_KEY_ID=AKIAFAKEEXAMPLE00000
AWS_SECRET_ACCESS_KEY=fAkE/exampleSecretKeyDoNotUse0000000000
JWT_SECRET=super-secret-jwt-key-2025
ENCRYPTION_KEY=0123456789abcdef0123456789abcdef
ENVEOF
    cat > "${tmpdir}/database.yml" <<'YMLEOF'
production:
  host: db.internal.company.local
  username: root
  password: mysql_root_2024
  database: production_db
YMLEOF
    tar -czf "$path" -C "$tmpdir" . 2>/dev/null || { rm -rf "$tmpdir"; return 1; }
    rm -rf "$tmpdir"
    [ -s "$path" ] || return 1
    state_manifest_add "$path"
}

bait_generate_aws_creds() {
    local path="${BNB_BAIT_SECRETS_DIR}/aws_credentials"
    cat > "$path" <<'EOF'
[default]
aws_access_key_id = AKIAFAKEEXAMPLE00000
aws_secret_access_key = fAkE/exampleSecretKeyDoNotUse0000000000
region = us-east-1

[production]
aws_access_key_id = AKIAFAKEPRODEXAMPLE
aws_secret_access_key = Pr0dFakeKey/DoNotUse/0000000000000000
region = us-east-1
EOF
    [ -s "$path" ] || return 1
    state_manifest_add "$path"
}

bait_generate_azure_tokens() {
    local path="${BNB_BAIT_SECRETS_DIR}/azure_tokens.json"
    cat > "$path" <<'EOF'
{
  "accessToken": "eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiIsIng1dCI6Ik...FAKE_TOKEN_DO_NOT_USE",
  "refreshToken": "AQABAAAAAADXzZ3...FAKE_REFRESH_TOKEN",
  "expiresOn": "2026-12-31T23:59:59Z",
  "subscription": "sub-fake-0000-0000-0000-000000000000",
  "tenant": "company.onmicrosoft.com",
  "resource": "https://management.azure.com/"
}
EOF
    [ -s "$path" ] || return 1
    state_manifest_add "$path"
}

bait_generate_gcp_creds() {
    local path="${BNB_BAIT_SECRETS_DIR}/gcp_service_account.json"
    cat > "$path" <<'EOF'
{
  "type": "service_account",
  "project_id": "production-project-2025",
  "private_key_id": "fakeprivatekeyid00000000000000000000000000",
  "private_key": "-----BEGIN PRIVATE KEY-----\nMIIEvfakePrivateKeyDataNotRealLabBaitDoNotUse\n-----END PRIVATE KEY-----\n",
  "client_email": "prod-sa@production-project-2025.iam.gserviceaccount.com",
  "client_id": "000000000000000000000"
}
EOF
    [ -s "$path" ] || return 1
    state_manifest_add "$path"
}

bait_generate_docker_config() {
    local path="${BNB_BAIT_SECRETS_DIR}/docker_config.json"
    cat > "$path" <<'EOF'
{
  "auths": {
    "https://index.docker.io/v1/": {
      "auth": "ZG9ja2VyLXVzZXI6ZG9ja2VyLXBhc3MxMjM="
    },
    "registry.company.internal": {
      "auth": "cHJvZC1yZWdpc3RyeTpyZWdpc3RyeS1wYXNzMjAyNQ=="
    }
  }
}
EOF
    [ -s "$path" ] || return 1
    state_manifest_add "$path"
}

bait_generate_kubeconfig() {
    local path="${BNB_BAIT_SECRETS_DIR}/kubeconfig"
    cat > "$path" <<'EOF'
apiVersion: v1
kind: Config
current-context: production
clusters:
- cluster:
    certificate-authority-data: LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCkZBS0VEQVRBCi0tLS0t...
    server: https://k8s-api.production.company.internal:6443
  name: production
contexts:
- context:
    cluster: production
    user: prod-admin
  name: production
users:
- name: prod-admin
  user:
    client-certificate-data: LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCkZBS0VEQVRBCg==
    client-key-data: LS0tLS1CRUdJTiBSU0EgUFJJVkFURSBLRVktLS0tLQpGQUtFREFUQQotLS0tLQ==
EOF
    [ -s "$path" ] || return 1
    state_manifest_add "$path"
}

bait_generate_pgp_key() {
    local path="${BNB_BAIT_SECRETS_DIR}/pgp_private.key"
    cat > "$path" <<'EOF'
-----BEGIN PGP PRIVATE KEY BLOCK-----
Version: GnuPG v2

lQdGBGfakePGPPrivateKeyDataDoNotUseLabBaitOnly0000000000000000000
000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000
=fAkE
-----END PGP PRIVATE KEY BLOCK-----
EOF
    [ -s "$path" ] || return 1
    state_manifest_add "$path"
}

bait_generate_prod_ssh_key() {
    local path="${BNB_BAIT_SECRETS_DIR}/id_rsa_prod"
    cat > "$path" <<'EOF'
-----BEGIN OPENSSH PRIVATE KEY-----
b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAABlwAAAAdzc2gtcn
NhAAAAAwEAAQAAAYEA3mGfakeProdSSHKeyDataNotRealLabBaitDoNotUse00000
0000000000000000000000000000000000000000000000000000000000000000000
-----END OPENSSH PRIVATE KEY-----
EOF
    [ -s "$path" ] || return 1
    state_manifest_add "$path"
}

bait_generate_ssh_known_hosts() {
    local path="${BNB_BAIT_SECRETS_DIR}/known_hosts"
    cat > "$path" <<'EOF'
192.168.1.100 ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC...
10.0.0.50 ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQD...
db-server.internal ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQE...
jenkins.internal ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQF...
fileserver.internal ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQG...
192.168.1.200 ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQH...
EOF
    [ -s "$path" ] || return 1
    state_manifest_add "$path"
}

bait_generate_vpn_config() {
    local path="${BNB_BAIT_SECRETS_DIR}/client.ovpn"
    cat > "$path" <<'EOF'
client
dev tun
proto udp
remote vpn.company.internal 1194
resolv-retry infinite
nobind
persist-key
persist-tun
remote-cert-tls server
auth SHA512
cipher AES-256-CBC
ignore-unknown-option block-outside-dns
block-outside-dns
verb 3
<ca>
-----BEGIN CERTIFICATE-----
MIIDfFakeCertificateDataDoNotUseLabBaitOnly00000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000
-----END CERTIFICATE-----
</ca>
<cert>
-----BEGIN CERTIFICATE-----
MIIDvFakeClientCertDataDoNotUseLabBaitOnly00000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000
-----END CERTIFICATE-----
</cert>
<key>
-----BEGIN PRIVATE KEY-----
MIIEvFakePrivateKeyDataDoNotUseLabBaitOnly00000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000
-----END PRIVATE KEY-----
</key>
EOF
    [ -s "$path" ] || return 1
    state_manifest_add "$path"
}

bait_generate_npmrc() {
    local path="${BNB_BAIT_SECRETS_DIR}/.npmrc"
    cat > "$path" <<'EOF'
registry=https://registry.npmjs.org/
//registry.npmjs.org/:_authToken=npm_fAkEtOkEnDoNoTuSe000000000000000
EOF
    [ -s "$path" ] || return 1
    state_manifest_add "$path"
}

bait_generate_pypirc() {
    local path="${BNB_BAIT_SECRETS_DIR}/.pypirc"
    cat > "$path" <<'EOF'
[distutils]
index-servers = pypi

[pypi]
repository = https://upload.pypi.org/legacy/
username = __token__
password = pypi-fAkEtOkEnDoNoTuSe0000000000000000000
EOF
    [ -s "$path" ] || return 1
    state_manifest_add "$path"
}

bait_generate_git_credentials() {
    local path="${BNB_BAIT_SECRETS_DIR}/.git-credentials"
    cat > "$path" <<'EOF'
https://svc-build:BuildDeploy123!@gitlab.internal.company.com
https://victim:password123@github.com/company/private-repo
https://admin:admin123@bitbucket.internal.company.com
EOF
    [ -s "$path" ] || return 1
    state_manifest_add "$path"
}

bait_generate_gitlab_ci() {
    local path="${BNB_BAIT_SECRETS_DIR}/.gitlab-ci.yml"
    cat > "$path" <<'EOF'
stages:
  - build
  - deploy

variables:
  DB_PASSWORD: "prod_db_pass_2025!"
  AWS_ACCESS_KEY_ID: "AKIAFAKEEXAMPLE00000"
  AWS_SECRET_ACCESS_KEY: "fAkE/exampleSecretKeyDoNotUse0000000000"
  DOCKER_REGISTRY_PASS: "registry-pass-2025"

deploy:
  stage: deploy
  script:
    - docker login -u prod-deploy -p $DOCKER_REGISTRY_PASS registry.company.internal
    - docker push registry.company.internal/webapp:latest
EOF
    [ -s "$path" ] || return 1
    state_manifest_add "$path"
}

bait_generate_jenkinsfile() {
    local path="${BNB_BAIT_SECRETS_DIR}/Jenkinsfile"
    cat > "$path" <<'EOF'
pipeline {
    agent any
    environment {
        DB_PASSWORD = credentials('db-password')
        SLACK_TOKEN = 'xoxb-fAkEtOkEnDoNoTuSe000000000'
        JIRA_TOKEN  = 'fAkEjIrAtOkEnDoNoTuSe0000000'
    }
    stages {
        stage('Deploy') {
            steps {
                sh 'mysql -h db.internal -u root -proot production_db < schema.sql'
                sh 'curl -X POST -H "Authorization: Bearer $JIRA_TOKEN" https://jira.company.internal/rest/api/2/issue'
            }
        }
    }
}
EOF
    [ -s "$path" ] || return 1
    state_manifest_add "$path"
}

bait_generate_terraform_state() {
    local path="${BNB_BAIT_SECRETS_DIR}/terraform.tfstate"
    cat > "$path" <<'EOF'
{
  "version": 4,
  "resources": [
    {
      "type": "aws_db_instance",
      "name": "production",
      "instances": [{
        "attributes": {
          "password": "rds_prod_password_2025!",
          "username": "admin",
          "endpoint": "prod-db.abcdefgh1234.us-east-1.rds.amazonaws.com",
          "port": 3306
        }
      }]
    }
  ]
}
EOF
    [ -s "$path" ] || return 1
    state_manifest_add "$path"
}

bait_generate_password_excel() {
    local path="${BNB_BAIT_SECRETS_DIR}/passwords_export.csv"
    cat > "$path" <<'EOF'
Service,URL,Username,Password,Notes
Production DB,db.internal,root,root,Primary database
Staging DB,staging-db.internal,admin,staging123,Test environment
Jenkins,jenkins.internal,svc-build,BuildDeploy123!,CI/CD
Jira,jira.company.internal,admin,admin123,Project management
Slack,company.slack.com,bot@company.internal,xoxb-fAkEtOkEn000000,Bot token
GitHub,github.com/company,svc-build,ghp_fAkEtOkEnDoNoTuSe000000,CI token
AWS Console,console.aws.amazon.com,admin@company.internal,AwsC0ns0le2025!,Root account
VPN,vpn.company.internal,victim,VpnP@ss2025!,Remote access
EOF
    [ -s "$path" ] || return 1
    state_manifest_add "$path"
}

bait_generate_backup_script() {
    local path="${BNB_BAIT_SECRETS_DIR}/backup_script.sh"
    cat > "$path" <<'EOFBAIT'
#!/bin/bash
# Automated backup script - runs nightly via cron
MYSQL_USER="root"
MYSQL_PASS="root"
MYSQL_HOST="db.internal"
BACKUP_DIR="/backups/mysql"

mysqldump -u $MYSQL_USER -p$MYSQL_PASS -h $MYSQL_HOST --all-databases > $BACKUP_DIR/full_backup_$(date +%Y%m%d).sql

# Upload to S3
export AWS_ACCESS_KEY_ID="AKIAFAKEEXAMPLE00000"
export AWS_SECRET_ACCESS_KEY="fAkE/exampleSecretKeyDoNotUse0000000000"
aws s3 cp $BACKUP_DIR/ s3://company-backups/mysql/ --recursive

# Cleanup old backups
find $BACKUP_DIR -name "*.sql" -mtime +30 -delete
EOFBAIT
    chmod +x "$path" 2>/dev/null || true
    [ -s "$path" ] || return 1
    state_manifest_add "$path"
}

bait_generate_keepass() {
    local path="${BNB_BAIT_SECRETS_DIR}/passwords.kdbx"
    head -c 4096 /dev/urandom 2>/dev/null > "$path" || \
    python3 -c "import os; open('$path','wb').write(os.urandom(4096))" 2>/dev/null || \
    dd if=/dev/zero of="$path" bs=1 count=4096 2>/dev/null
    [ -s "$path" ] || return 1
    state_manifest_add "$path"
}

bait_generate_app_log() {
    local path="${BNB_BAIT_SECRETS_DIR}/app_debug.log"
    cat > "$path" <<'EOF'
2025-07-10 03:15:22 [INFO] Starting application v2.3.1
2025-07-10 03:15:23 [DEBUG] DB config: host=db.internal, user=root, pass=root, db=production_db
2025-07-10 03:15:24 [INFO] Connected to database successfully
2025-07-10 08:30:15 [WARN] Slow query detected: SELECT * FROM users (took 2.3s)
2025-07-10 14:22:01 [ERROR] Login failed for user admin from 192.168.1.50
2025-07-11 09:15:00 [DEBUG] Session token generated: sess_fAkE-sEsSiOnToKeN-do-not-use
2025-07-11 09:15:01 [INFO] User admin authenticated with token sess_fAkE-sEsSiOnToKeN-do-not-use
2025-07-12 22:00:00 [INFO] Running nightly backup job (backup_script.sh)
2025-07-12 22:00:05 [DEBUG] Backup command: mysqldump -u root -proot -h db.internal --all-databases
EOF
    [ -s "$path" ] || return 1
    state_manifest_add "$path"
}

bait_generate_world_writable_script() {
    local path="${BNB_BAIT_DECEPTION_DIR}/cleanup.sh"
    cat > "$path" <<'EOFBAIT'
#!/bin/bash
# World-writable cleanup script (runs as root via cron)
# WARNING: This script is world-writable - any user can modify it!

TEMP_DIR="/tmp/cleanup_$(date +%s)"
mkdir -p "$TEMP_DIR"

# Remove old temp files
find /tmp -name "*.tmp" -mtime +1 -delete 2>/dev/null
find /var/tmp -name "*.tmp" -mtime +7 -delete 2>/dev/null

echo "Cleanup completed at $(date)" >> /var/log/cleanup.log
EOFBAIT
    chmod 777 "$path" 2>/dev/null || true
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
    bait_generate_ssh_key        || { rc=1; state_incident_append "bait" "FAILED: id_rsa_victim"; }
    bait_generate_browser_creds  || { rc=1; state_incident_append "bait" "FAILED: browser_saved_logins.json"; }
    bait_generate_bash_history   || { rc=1; state_incident_append "bait" "FAILED: .bash_history"; }
    bait_generate_git_secrets    || { rc=1; state_incident_append "bait" "FAILED: git_secrets_repo"; }
    bait_generate_aws_creds      || { rc=1; state_incident_append "bait" "FAILED: aws_credentials"; }
    bait_generate_azure_tokens   || { rc=1; state_incident_append "bait" "FAILED: azure_tokens.json"; }
    bait_generate_gcp_creds      || { rc=1; state_incident_append "bait" "FAILED: gcp_service_account.json"; }
    bait_generate_docker_config  || { rc=1; state_incident_append "bait" "FAILED: docker_config.json"; }
    bait_generate_kubeconfig     || { rc=1; state_incident_append "bait" "FAILED: kubeconfig"; }
    bait_generate_pgp_key        || { rc=1; state_incident_append "bait" "FAILED: pgp_private.key"; }
    bait_generate_prod_ssh_key   || { rc=1; state_incident_append "bait" "FAILED: id_rsa_prod"; }
    bait_generate_ssh_known_hosts|| { rc=1; state_incident_append "bait" "FAILED: known_hosts"; }
    bait_generate_vpn_config     || { rc=1; state_incident_append "bait" "FAILED: client.ovpn"; }
    bait_generate_npmrc          || { rc=1; state_incident_append "bait" "FAILED: .npmrc"; }
    bait_generate_pypirc         || { rc=1; state_incident_append "bait" "FAILED: .pypirc"; }
    bait_generate_git_credentials|| { rc=1; state_incident_append "bait" "FAILED: .git-credentials"; }
    bait_generate_gitlab_ci      || { rc=1; state_incident_append "bait" "FAILED: .gitlab-ci.yml"; }
    bait_generate_jenkinsfile    || { rc=1; state_incident_append "bait" "FAILED: Jenkinsfile"; }
    bait_generate_terraform_state|| { rc=1; state_incident_append "bait" "FAILED: terraform.tfstate"; }
    bait_generate_password_excel || { rc=1; state_incident_append "bait" "FAILED: passwords_export.csv"; }
    bait_generate_backup_script  || { rc=1; state_incident_append "bait" "FAILED: backup_script.sh"; }
    bait_generate_keepass        || { rc=1; state_incident_append "bait" "FAILED: passwords.kdbx"; }
    bait_generate_app_log        || { rc=1; state_incident_append "bait" "FAILED: app_debug.log"; }
    bait_generate_world_writable_script || { rc=1; state_incident_append "bait" "FAILED: cleanup.sh"; }
    return "$rc"
}
