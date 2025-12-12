#!/bin/bash

echo " "
echo "============================================="
echo " "
echo "$(date): Resuming torrent downloads ..."

qbt --config $TS_CONF_PATH/.qbt.toml torrent resume ALL
qbt --config $TS_CONF_PATH/.qbt.toml torrent reannounce ALL

echo " "
echo "============================================="
echo " "
