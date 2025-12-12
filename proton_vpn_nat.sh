#!/bin/bash
while true; do
    datetime=$(date)

    # Run natpmpc for UDP and TCP, redirect output to a temporary file
    natpmpc -a 1 0 udp 60 -g 10.2.0.1 >/dev/null 2>&1 && natpmpc -a 1 0 tcp 60 -g 10.2.0.1 > /tmp/natpmpc_output || { 
        echo -e "ERROR with natpmpc command \a" 
        export PROTONVPN_NAT_PORT=0
        break
    }

    # Extract the port numbers from the output and save them in variables
    port=$(grep 'TCP' /tmp/natpmpc_output | grep -o 'Mapped public port [0-9]*' | awk '{print $4}')

    export PROTONVPN_NAT_PORT=$port
    echo "[$datetime] ProtonVPN NAT PMP port: $PROTONVPN_NAT_PORT"
    if [ "$MIKROTIK_INTEGRATION" == "true" ]; then
        rules=$(curl -s -k -u $MIKROTIK_USERNAME:$MIKROTIK_PASSWORD "$MIKROTIK_ADDRESS/rest/ip/firewall/nat?comment=$MIKROTIK_NAT_RULE_COMMENT")
        jq -r '.[].".id"' <<<"$rules" | while read -r ID; do
            curl -s -k -u $MIKROTIK_USERNAME:$MIKROTIK_PASSWORD -X PATCH "$MIKROTIK_ADDRESS/rest/ip/firewall/nat/$ID" \
              --data "{\"dst-port\": \"$PROTONVPN_NAT_PORT\"}" -H "content-type: application/json" >/dev/null
        done
    fi
    sleep 45
done