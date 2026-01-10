#!/bin/bash

###############################################
# BashMon - A simple system monitoring script #
# Author - Jake Murray                        #
# Date - 1-5-26                               #
###############################################

### For anyone reading this, I have added TONS of comments for myself. This is purely personal as it helps me
# review and retain what I am learning with each program.

# Purposes
# Check for failed SSH connections
# Check sudo usage
# Check system errors
# Check for new system services
# Check for failed services
# Check kernel messages
# Check disk space

# TODO:
# 1. Allow user to input thier own output directory
# 2. Add menu to select from different systems (ex. Arch - journalctl, Ubuntu - auth.log)
# 3. Change logic from last hour to from time of last scan (just to avoid issues if a scan is skipped)
#
# JOURNALCTL Systems
# For journalctl, I'm going to use json output in order for
# it to parsed more easily than simple text output.
# add menu for user to select whether or not to update baseline services with current_services
#
# #############################################
# DEPENCDENCIES FOR JOURNALCTL
#   a) jq

#----------------------------------------------#
# Contents:
# Line ~50 - Check for failed SSH attempts
# Line ~100 - Check Sudo usage
# Line ~120 - Check for system errors
# Line ~200 - Check for new services
# Line ~240 - Check for failed services
# Line ~270 - Check for kernel Warnings
# Line ~290 - Print summary of disk space

# Initial vaiables
OUTPUT_DIR="$HOME/bashmon-logs" # Feel free to change this to desired output location
ALERT_FILE="$OUTPUT_DIR/BashMon_alert_$(date +%Y%m%d).log"
CHECK_TIME="1 hour ago" # This interval can be changed based on user needs.

# Create output directory if it doesn't exist
mkdir -p "$OUTPUT_DIR"

# This alert function takes informational text, like "checking for failed ssh attempts" below,
# adds a timestamp to it, then pipes it to tee so it is both printed to the terminal AND written
# to the alert file. Keeping consistent formatting each time, all I have to do is feed it the text
# I want written. I have 3 different alerts that change the color based on use.
alert() {
  # blue
  echo -e "\e[34m$1\e[0m" | tee -a "$ALERT_FILE"
}

pos_alert() {
  # green
  echo -e "\e[32m$1\e[0m" | tee -a "$ALERT_FILE"
}

neg_alert() {
  # red
  echo -e "\e[31m$1\e[0m" | tee -a "$ALERT_FILE"
}
###############################################
###   Check for failed SSH login attempts   ###
###############################################

check_ssh_attempts() {
  # 1. Set count for failed attempts
  # 2. Set up while loop for iteration to find lines containing "failed password"
  # 3. Feed output of all sshd events from journalctl in last hour into while loop
  # 4. Display results
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
    if echo "$line" | jq -e 'select(.MESSAGE | contains("Failed password"))' >/dev/null 2>&1; then
      ((failed_count++)) # Increment counter
    fi
    # The line below is "process substitution"
    # the <(...) structure allows you to use the output of a command as if it were a file
    # So, I am saying, "hey, do this thing, pretend the output is a file, and feed that into the while loop to be processed"
  done < <(journalctl -u sshd --since "$CHECK_TIME" -o json 2>/dev/null)

  if [ "$failed_count" -gt 0 ]; then

    neg_alert "======================================================"
    neg_alert "[ALERT: $failed_count failed SSH login attempts found!"
    neg_alert "======================================================"

    # Display failed attempts

    neg_alert "+++ Recent failed attempts +++"

    journalctl -u sshd --since "$CHECK_TIME" -o json 2>/dev/null |
      jq -r 'select(.MESSAGE | contains("Failed password")) | .MESSAGE' |
      head -n 10 | tee -a "$ALERT_FILE"

    # Extract attacking IPs
    neg_alert "+++ Top IPs with failed ssh attempts +++"
    journalctl -u sshd --since "$CHECK_TIME" -o json 2>/dev/null |
      jq -r 'select(.MESSAGE | contains("Failed password")) | .MESSAGE' |
      # grep -o flag prints only the matching part of a matching line
      # the -E flag tells grep to interpret patterns as regex
      grep -oE '\b([0-9]{1,3}\.){3}[0-9]{1,3}\b' |
      sort | uniq -c | sort -rn | head -n 5 | tee -a "$ALERT_FILE"

  else
    pos_alert "No Failed SSH attempt found since $CHECK_TIME"
  fi
}

############################
###   Check Sudo Usage   ###
############################

check_sudo_usage() {
  # 1. Set counter for sudo use
  # 2. Similar loop as above, searching for "COMMAND"
  # 3. Feed output of all sudo events in last hour into loop
  # 4. display output
  alert "===== Checking for Sudo Command Usage ====="

  local sudo_count=0
  while IFS= read -r line; do
    #### !! The jq -e flag explanation !! ####
    # without the -e flag, jq will return 0 (which in bash = True) each time it runs without error. So even if
    # the line does not have "COMMAND", since there was no error, it will return nothing which gets translated to 0.
    # the -e flag makes it return "0 if the last output was neither false nor null" and "4 if no valid result was produced"
    #
    # So, without the -e flag, as long as there is no error, jq returns 0. which the if loop
    # evaluates to true. with the -e flag. It returns exit code 4 when there is no valid result, the case when
    # jq reads a line with no match and no errors..
    if echo "$line" | jq -e -r 'select(.MESSAGE | contains("COMMAND"))' >/dev/null 2>&1; then
      ((sudo_count++))
    fi
  done < <(journalctl -t sudo --since "$CHECK_TIME" -o json 2>/dev/null)

  if [ "$sudo_count" -gt 0 ]; then

    neg_alert "======================================="
    neg_alert "ALERT: $sudo_count sudo commands found!"
    neg_alert "======================================="

    journalctl -t sudo --since "$CHECK_TIME" -o json 2>/dev/null |
      jq -r 'select(.MESSAGE | contains("COMMAND")) | .MESSAGE' |
      head -n 10 | tee -a "$ALERT_FILE"
  else
    pos_alert "No sudo commands found since $CHECK_TIME"
  fi
}

###############################
### Check for System Errors ###
###############################

check_sys_errors() {
  # 1. set counter
  # 2. set up loop that prints each line
  # 3. feed in output of all error events in last hour
  # 4. print lines
  alert "===== Checking for System Errors ====="

  local error_count=0
  while IFS= read -r line; do
    if echo "$line" | jq -e -r 'select(.MESSAGE)' >/dev/null 2>&1; then
      ((error_count++))
    fi
  done < <(journalctl -p err --since "$CHECK_TIME" -o json 2>/dev/null)

  if [ "$error_count" -gt 0 ]; then

    neg_alert "=========================================================="
    neg_alert "ALERT: $error_count system errors found since $CHECK_TIME!"
    neg_alert "=========================================================="

    journalctl -p err --since "$CHECK_TIME" -o short 2>/dev/null |
      head -n 10 | tee -a "$ALERT_FILE"
  else
    pos_alert "No system errors found since $CHECK_TIME"
  fi
}

##############################
### Check for New Services ###
##############################
check_new_services() {
  # 1. Check for a baseline of normally running services
  #  a) if none, save current as baseline
  #  b) if baseline, continue with comparison
  # 2. Save currently running services
  # 3. Compare each service to what is in the baseline
  # 4. Save new services for display and to alert log
  # 5. Clear current services for next scan
  alert "===== Checking for New Services ====="

  local current_services="/tmp/current_services_$$.txt"
  local baseline_services="$OUTPUT_DIR/baseline_services.txt"

  systemctl -t service --state=active --no-pager --no-legend |
    awk '{ print $1 }' | sort >"$current_services"

  if [ -f "$baseline_services" ]; then
    # comm: -1 flag removes unique items in baseline
    # -3 flag removes items that are in both lists
    # compares the remaining servies to baseline list
    local new_services=$(comm -13 "$baseline_services" "$current_services")

    if [ -n "$new_services" ]; then
      neg_alert "=========================="
      neg_alert "ALERT: New services found!"
      neg_alert "=========================="

      echo "$new_services" | tee -a "$ALERT_FILE"
    else
      pos_alert "No new services found since $CHECK_TIME"
    fi
    # !! create menu to ask if user wants to update baseline_services
    cp "$current_services" "$baseline_services"
  else
    cp "$current_services" "$baseline_services"
    alert "Baseline services list created ($(wc -l <"$baseline_services") services)"
  fi

  rm -f "$current_services"
}

#################################
### Check for failed services ###
#################################
check_failed_services() {
  alert "===== Checking for failed services ====="
  local failed_count=0
  while IFS= read -r line; do
    if echo "$line" | jq -e -r 'select(.MESSAGE) | contains("failed"))' >/dev/null 2>&1; then
      ((failed_count++))
    fi
  done < <(systemctl list-units --state=failed --no-pager --no-legend -o short)

  if [ $failed_count -gt 0 ]; then

    neg_alert "======================================================="
    neg_alert "===== ALERT: $failed_count failed services found! ====="
    neg_alert "======================================================="

    systemctl list-units --state=failed --no-pager --no-legend |
      tee -a "$ALERT_FILE"
  else
    pos_alert "No failed services since $CHECK_TIME"
  fi
}
#############################
### Check Kernel Messages ###
#############################
check_kernel_messeges() {
  alert "===== Checking Kernel Messeges ====="
  local kernelmesg_count=$(journalctl -k -p warning --since "$CHECK_TIME" -o json 2>/dev/null |
    jq -r '.MESSAGE' 2>/dev/null |
    wc -l)

  if [ $kernelmesg_count -gt 0 ]; then

    neg_alert "===================================================="
    neg_alert "===== ALERT: $kernelmesg_count Kernel Warnings ====="
    neg_alert "===================================================="

    journalctl -k -p warning --since "$CHECK_TIME" -o short |
      head -n 10 |
      tee -a "$ALERT_FILE"
  else
    pos_alert "No Kernel Warnings Found"
  fi
}

##################
### Disk Space ###
##################
disk_usage() {
  alert "Disk Usage:"

  local disk_usage=$(df -h / | tail -n 1 | awk '{print $5}' | sed 's/%//')

  if [ "$disk_usage" -gt 80 ]; then
    neg_alert "WARNING: Disk usage is ${disk_usage}% (threshold: 80%)"
  else
    pos_alert "Disk usage okay: ${disk_usage}%"
  fi
}

alert "====================================="
alert "BashMon System Monitor"
alert "Checking logs from: $CHECK_TIME"
alert "Report can be found at $ALERT_FILE"
alert "====================================="

echo ""
check_ssh_attempts
echo ""
check_sudo_usage
echo ""
check_sys_errors
echo ""
check_new_services
echo ""
check_failed_services
echo ""
check_kernel_messeges
echo ""
disk_usage
echo ""

alert "====================================="
alert "BashMon has completed it's scan..."
alert "Full Report saved at $ALERT_FILE"
alert "====================================="
