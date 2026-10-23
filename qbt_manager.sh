#!/bin/bash

if [ -s /TS/.config.env ]; then
    set -a; . /TS/.config.env; set +a
fi

# Add QBT_ADDITIONAL_TRACKERS to the torrent with hash $1 (qbt cli can't add trackers, so use qBittorrent WebAPI)
add_trackers() {
    QBT_ADDR=$(grep -m 1 "^addr" $TS_CONF_PATH/.qbt.toml | cut -d '"' -f 2)
    QBT_LOGIN=$(grep -m 1 "^login" $TS_CONF_PATH/.qbt.toml | cut -d '"' -f 2)
    QBT_PASSWORD=$(grep -m 1 "^password" $TS_CONF_PATH/.qbt.toml | cut -d '"' -f 2)
    QBT_COOKIES=$(mktemp)

    curl -s -c $QBT_COOKIES -H "Referer: $QBT_ADDR" --data-urlencode "username=$QBT_LOGIN" --data-urlencode "password=$QBT_PASSWORD" "$QBT_ADDR/api/v2/auth/login" > /dev/null

    # Torrent may not be registered in qBittorrent right after adding, so retry a few times
    for i in {1..10}; do
        RESPONSE_CODE=$(curl -s -o /dev/null -w "%{http_code}" -b $QBT_COOKIES -H "Referer: $QBT_ADDR" --data-urlencode "hash=$1" --data-urlencode "urls=$(echo "$QBT_ADDITIONAL_TRACKERS" | tr -s ' ' '\n')" "$QBT_ADDR/api/v2/torrents/addTrackers")
        if [ "$RESPONSE_CODE" == "200" ]; then
            echo "$(date): Added trackers to torrent $1: $QBT_ADDITIONAL_TRACKERS"
            break
        fi
        sleep 1
    done
    [ "$RESPONSE_CODE" != "200" ] && echo "$(date): Failed to add trackers to torrent $1 (HTTP $RESPONSE_CODE)"

    rm -f $QBT_COOKIES
}

if [ -s $TS_STAT ]; then
    
    # POST_AUTH="Cache-Control: no-cache" - it's just a dummy header instead of an authorization header
    [ ! -z "$POST_AUTH" ] && POST_AUTH="Authorization:Basic $POST_AUTH" || POST_AUTH="Cache-Control: no-cache"
    
    QBT_TORRENTS_LIST=($(qbt --config $TS_CONF_PATH/.qbt.toml torrent list --output json | grep -w "hash" | grep -o -E "[a-zA-Z0-9]{40}"))

    for HASH in $(jq '."monitor" | keys' $TS_STAT | grep -o -E "[a-zA-Z0-9]{40}")
    do
        if [ ! -z "$HASH" ] && [[ " ${QBT_TORRENTS_LIST[*]} " =~ " ${HASH} " ]]; then
            jq '."torrents"."'"$HASH"'"."downloaded" = true' $TS_STAT | sponge $TS_STAT
            jq 'del(."monitor"."'"$HASH"'")' $TS_STAT | sponge $TS_STAT
        else
            TORRENT_SIZE=$(curl http://localhost:$TS_PORT/cache -s -X POST -H "Accept:application/json" -H "$POST_AUTH" --data @<(cat <<EOF
            {
            "action": "get",
            "hash" : "$HASH"
            }
EOF
) | jq '."PiecesCount"')

            TORRENT_POSITION=$(curl http://localhost:$TS_PORT/cache -s -X POST -H "Accept:application/json" -H "$POST_AUTH" --data @<(cat <<EOF
            {
            "action": "get",
            "hash" : "$HASH"
            }
EOF
) | jq '."Readers"[]."Reader"')

            if [ ! -z "$(echo "$TORRENT_SIZE" | grep -o -E "[0-9]+")" ] && [ ! -z "$(echo "$TORRENT_POSITION" | grep -o -E "[0-9]+")" ]; then
                TORRENT_PROGRESS=$((($TORRENT_POSITION * 100) / $TORRENT_SIZE))
            else
                TORRENT_PROGRESS=0
            fi
            if [ $TORRENT_PROGRESS -gt $QBT_DOWNLOAD_THRESHOLD ]; then
                if qbt --config $TS_CONF_PATH/.qbt.toml torrent add "$(jq -r '."torrents"."'"$HASH"'"."url"' $TS_STAT)" && [ ! -z "$QBT_ADDITIONAL_TRACKERS" ]; then
                    add_trackers $HASH
                fi
            fi
        fi
    done
fi
