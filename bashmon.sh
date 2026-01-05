#!/bin/bash

###############################################
# BashMon - A simple system monitoring script #
# Author - Jake Murray                        #
# Date - 1-5-26                               #
###############################################

# TODO:
# 1. Allow user to input thier own output directory
# 2. Add menu to select from different systems (ex. Arch - journalctl, Ubuntu - auth.log)
#
# JOURNALCTL
# For journalctl, I'm going to use json output in order for
# it to parsed more easily than simple text output.
# #############################################
# DEPENCDENCIES FOR JOURNALCTL
#   a) jq

# Initial vaiables
LOG_DIR="/var/log"
AUTH_LOG="$LOG_DIR/auth.log"
OUTPUT_DIR="$HOME/bashmon-logs" # Change this to desired output location
ALERT_FILE="OUTPUT_DIR/BashMon_alert_$(date +%Y%m%d).log"

# Create output directory if it doesn't exist
mkdir -p "$OUTPUT_DIR"

alert() {
    local message="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $message" | tee -a "$ALERT_FILE"
}

check_failed_logins() {
    alert "===== Checking for Failed Login Attempts ====="

    # search journalctl for failed password attempts.
    local failed_passwords="$(sudo journalctl -u sshd | grep "Failed password" 2>/dev/null | tail -n 10)

    if [ -n "$failed_passwords" ]; then
        alert "ALERT: BashMon detected recent failed login attempts:"
        echo "$failed_passwords" >> "$ALERT_FILE"
