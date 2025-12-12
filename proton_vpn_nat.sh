#!/bin/bash
while true; do
    date

    # Run natpmpc for UDP and TCP, redirect output to a temporary file
    natpmpc -a 1 0 udp 60 -g 10.2.0.1 >/dev/null 2>&1 && natpmpc -a 1 0 tcp 60 -g 10.2.0.1 > /tmp/natpmpc_output || { 
        echo -e "ERROR with natpmpc command \a" 
        export PROTONVPN_NAT_PORT=0
        break
    }

    # Extract the port numbers from the output and save them in variables
    port=$(grep 'TCP' /tmp/natpmpc_output | grep -o 'Mapped public port [0-9]*' | awk '{print $4}')

    export PROTONVPN_NAT_PORT=$port
    echo "Port heartbeat: $PROTONVPN_NAT_PORT"
    curl -s --cookie "SID=$SID" \
      --data "json={\"listen_port\":$PROTONVPN_NAT_PORT,\"upnp\":false}" \
      "http://localhost:$QBT_WEBUI_PORT/api/v2/app/setPreferences"
    sleep 45
done