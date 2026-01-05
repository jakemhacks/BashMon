#!/bin/bash

###############################################
# BashMon - A simple system monitoring script #
# Author - Jake Murray                        #
# Date - 1-5-26                               #
###############################################

# TODO:
# 1. Allow user to input thier own output directory
# 2. Add menu to select from different systems (ex. Arch - journalctl, Ubuntu - auth.log)
# 3. Change logic from last hour to from time of last scan (just to avoid issues if a scan is skipped)
# JOURNALCTL
# For journalctl, I'm going to use json output in order for
# it to parsed more easily than simple text output.
# #############################################
# DEPENCDENCIES FOR JOURNALCTL
#   a) jq

# Initial vaiables
OUTPUT_DIR="$HOME/bashmon-logs" # Change this to desired output location
ALERT_FILE="$OUTPUT_DIR/BashMon_alert_$(date +%Y%m%d).log"
CHECK_TIME="1 hour ago"

# Create output directory if it doesn't exist
mkdir -p "$OUTPUT_DIR"

alert() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$ALERT_FILE"
}

check_ssh_attempts() {
    alert "===== Checking for Failed SSH Attempts ====="

    # count failed attempts
    local failed_count=0

    # read journalctl line by line
    while IFS= read -r line; do
        # Check if line contains "Failed password"
        if echo "$line" | jq -e 'select(.MESSAGE | contains("Failed password"))' > /dev/null 2>&1; then
            failed_count=$((failed_count + 1))  # Increment counter
        fi
    done < <(journalctl -u sshd --since "$CHECK_TIME" -o json 2>/dev/null)

    if [ "$failed_count" -gt 0 ]; then  # SPACE before ]
        alert "ALERT: $failed_count failed SSH login attempts found!"

        # Display failed attempts
        alert "Recent failed attempts:"
        journalctl -u sshd --since "$CHECK_TIME" -o json 2>/dev/null | \
            jq -r 'select(.MESSAGE | contains("Failed password")) | .MESSAGE' | \
            head -n 10 | tee -a "$ALERT_FILE"

        # Extract attacking IPs (MOVED INSIDE IF)
        alert "Top IPs with failed ssh attempts:"
        journalctl -u sshd --since "$CHECK_TIME" -o json 2>/dev/null | \
            jq -r 'select(.MESSAGE | contains("Failed password")) | .MESSAGE' | \
            grep -oE '\b([0-9]{1,3}\.){3}[0-9]{1,3}\b' | \
            sort | uniq -c | sort -rn | head -n 5 | tee -a "$ALERT_FILE"

    else
        alert "No Failed SSH attempt found"
    fi
}
    
check_ssh_attempts
