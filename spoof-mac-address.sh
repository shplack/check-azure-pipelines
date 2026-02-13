#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR" || exit 1

# check if current MAC address is already the one specified in mac-address.txt
current_mac=$(ifconfig wlan0 | grep -oE '([[:xdigit:]]{2}:){5}[[:xdigit:]]{2}')
target_mac=$(cat mac-address.txt)
if [ "$current_mac" == "$target_mac" ]; then
  echo "MAC address is already spoofed."
  exit 0
fi

# Spoof the MAC address of wlan0 to the one specified in mac-address.txt
sudo ifconfig wlan0 down
sudo ifconfig wlan0 hw ether $(cat mac-address.txt)
sudo ifconfig wlan0 up

# Timeout after 5 seconds if the connection is not established
timeout 5 bash -c "until ping -c1 google.com &>/dev/null; do sleep 1; done"

# Check if the connection is established
if ping -c1 google.com &>/dev/null; then
  echo "Connection established with spoofed MAC address."
  exit 0
else
  echo "Failed to establish connection with spoofed MAC address."
  exit 1
fi
