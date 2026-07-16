#!/usr/bin/env bash
# Shared configuration and path constants for bait-n-break.
# Sourced by every module. Must have no side effects beyond variable exports.
# Deliberately does NOT set shell options (set -u/-e/pipefail) - this file
# is sourced, not executed, and mutating the caller's shell options is a
# side effect the "no side effects on source" constraint forbids. Only
# run.sh and setup.sh (executed directly) set shell options.

BNB_ROOT="${BNB_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"

BNB_STATE_DIR="${BNB_ROOT}/.state"
BNB_VICTIM_DIR="${BNB_ROOT}/bait_n_break/victim"
BNB_WEBAPP_DIR="${BNB_VICTIM_DIR}/webapp"

BNB_STATE_FILE="${BNB_STATE_DIR}/victim_status"
BNB_BAIT_MANIFEST="${BNB_STATE_DIR}/bait_manifest.txt"
BNB_INCIDENT_LOG="${BNB_STATE_DIR}/incident_log.txt"
BNB_BAIT_ACCESS_LOG="${BNB_STATE_DIR}/bait_access.log"

BNB_ATTACK_RESULTS="${BNB_STATE_DIR}/attack_results.txt"
BNB_TARGET_FILE="${BNB_STATE_DIR}/attacker_target"

BNB_BAIT_BACKUPS_DIR="${BNB_STATE_DIR}/bait/backups"
BNB_BAIT_SECRETS_DIR="${BNB_STATE_DIR}/bait/secrets"
BNB_BAIT_DECEPTION_DIR="${BNB_STATE_DIR}/bait/deception"

# TARGET_IP/PORT: consumed by Phase 2 attacker scripts. Empty TARGET_IP
# means "not configured yet" - Phase 1 does not require it.
TARGET_IP="${TARGET_IP:-}"
TARGET_PORT="${TARGET_PORT:-8080}"

BNB_CVE_APACHE_41773_PORT=8081
BNB_CVE_SHELLSHOCK_PORT=8082
BNB_CVE_PROFTPD_PORT=2122
BNB_CVE_WEBMIN_PORT=10000
BNB_CVE_TOMCAT_HTTP_PORT=8083
BNB_CVE_TOMCAT_AJP_PORT=8009
