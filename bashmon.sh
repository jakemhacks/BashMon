#!/bin/bash

###############################################
# BashMon - A simple system monitoring script #
# Author - Jake Murray                        #
# Date - 1-5-26                               #
###############################################

### For anyone reading this, I have added TONS of comments for myself. This is purely personal as it helps me 
# review and retain what I am learning with each program.

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


#----------------------------------------------#
# Contents:
# Line ~48 - Check for failed SSH attempts
# Line ~94 - Check Sudo usage



# Initial vaiables
OUTPUT_DIR="$HOME/bashmon-logs" # Feel free to change this to desired output location
ALERT_FILE="$OUTPUT_DIR/BashMon_alert_$(date +%Y%m%d).log"
CHECK_TIME="1 hour ago" # This interval can be changed based on user needs.

# Create output directory if it doesn't exist
mkdir -p "$OUTPUT_DIR"

# This alert function takes informational text, like "checking for failed ssh attempts" below,
# adds a timestamp to it, then pipes it to tee so it is both printed to the terminal AND written
# to the alert file. Keeping consistent formatting each time, all I have to do is feed it the text
# I want written.
alert() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$ALERT_FILE"
}

###   Check for failed SSH login attempts   ###
check_ssh_attempts() {
    alert "===== Checking for Failed SSH Attempts ====="

    # count failed attempts
    local failed_count=0

    # read journalctl line by line
    # Note for myself: "IFS=" is the opposite of ".strip()" in python.
    # Bash strips whitespace by default. IFS= prevents this from happening.
    # So this basically means
    #   While there is a line to read, don't strip the whitespace, read "\" literally, and perform the loop
    #   In this case, it probably won't be needed, but if I want the line to be read exactly as-is, this is best practice.
    while IFS= read -r line; do
        # Check if line contains "Failed password"
        # here we use jq to check each line for "failed password" which is our main indicator
        if echo "$line" | jq -e 'select(.MESSAGE | contains("Failed password"))' > /dev/null 2>&1; then
            ((failed_count++))  # Increment counter
        fi
    # This line is "process substitution"
    # the <(...) structure allows you to use the output of a command as if it were a file
    # So, I am saying, "hey, do this thing, pretend the output is a file, and feed that into the while loop to be processed"
    done < <(journalctl -u sshd --since "$CHECK_TIME" -o json 2>/dev/null)

    if [ "$failed_count" -gt 0 ]; then
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
    
###   Check Sudo Usage   ###
check_sudo_usage() {
    alert "===== Checking for Sudo Command Usage ====="
    
    sudo_count=0
    while IFS= read -r line; do
        if echo "$line" | jq -e -r 'select(.MESSAGE | contains("COMMAND"))' > /dev/null 2>&1; then
            ((sudo_count++))
        fi
    done < <(journalctl -t sudo --since "$CHECK_TIME" -o json 2>/dev/null)

    if [ "$sudo_count" -gt 0 ]; then
        alert "ALERT: $sudo_count sudo commands found!"
        journalctl -t sudo --since "$CHECK_TIME" -o json 2>/dev/null | \
            jq -r 'select(.MESSAGE | contains("COMMAND")) | .MESSAGE' | \
            head -n 10 | tee -a "$ALERT_FILE"
    else
        alert "No sudo commands found"

    fi
}

check_sudo_usage
