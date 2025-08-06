#!/bin/sh

# This script configures and runs Xray as a SOCKS5/HTTP proxy.
# It can be configured using one of the following environment variables:
# 1. X_UI_LINK:      A VLESS reality or TLS link.
# 2. WIREGUARD_LINK: A multi-line WireGuard client configuration.
#
# The script prioritizes X_UI_LINK if both are set.

# This variable will hold the final JSON for the main outbound proxy
OUTBOUND_CONFIG=""

# --- Configuration Detection and Parsing ---

# Check for VLESS link first
if [ -n "$X_UI_LINK" ]; then
    echo "[*] Found X_UI_LINK. Configuring for VLESS proxy."

    echo "[*] Parsing VLESS link..."
    URI="$X_UI_LINK"
    UUID=$(echo "$URI" | sed -n 's|vless://\([^@]*\)@.*|\1|p')
    HOST=$(echo "$URI" | sed -n 's|.*@\([^:]*\):.*|\1|p')
    PORT=$(echo "$URI" | sed -n 's|.*:\([0-9]*\)?.*|\1|p')
    PARAMS=$(echo "$URI" | cut -d'?' -f2)

    TYPE=$(echo "$PARAMS" | tr '&' '\n' | grep '^type=' | cut -d= -f2)
    SECURITY=$(echo "$PARAMS" | tr '&' '\n' | grep '^security=' | cut -d= -f2)
    PBK=$(echo "$PARAMS" | tr '&' '\n' | grep '^pbk=' | cut -d= -f2)
    FP=$(echo "$PARAMS" | tr '&' '\n' | grep '^fp=' | cut -d= -f2)
    SNI=$(echo "$PARAMS" | tr '&' '\n' | grep '^sni=' | cut -d= -f2)
    SID=$(echo "$PARAMS" | tr '&' '\n' | grep '^sid=' | cut -d= -f2)
    SPX=$(echo "$PARAMS" | tr '&' '\n' | grep '^spx=' | cut -d= -f2 | sed 's/%2F/\//g')
    FLOW=$(echo "$PARAMS" | tr '&' '\n' | grep '^flow=' | cut -d= -f2)

    echo "[*] VLESS Parsed:"
    echo "  HOST=$HOST"
    echo "  PORT=$PORT"
    echo "  SECURITY=$SECURITY"
    echo "  SNI=$SNI"
    
    STREAM_SETTINGS="\"network\": \"$TYPE\""

    if [ "$SECURITY" = "reality" ]; then
      STREAM_SETTINGS="$STREAM_SETTINGS,
        \"security\": \"reality\",
        \"realitySettings\": {
          \"show\": false,
          \"serverName\": \"$SNI\",
          \"publicKey\": \"$PBK\",
          \"shortId\": \"$SID\",
          \"spiderX\": \"$SPX\"
        }"
    elif [ "$SECURITY" = "tls" ]; then
      STREAM_SETTINGS="$STREAM_SETTINGS,
        \"security\": \"tls\",
        \"tlsSettings\": {
          \"serverName\": \"$SNI\",
          \"allowInsecure\": false,
          \"fingerprint\": \"$FP\"
        },
        \"wsSettings\": {
          \"path\": \"$SPX\",
          \"headers\": {
            \"Host\": \"$SNI\"
          }
        }"
    fi

    # Define the outbound configuration for VLESS
    OUTBOUND_CONFIG="{
      \"protocol\": \"vless\",
      \"tag\": \"proxy\",
      \"settings\": {
        \"vnext\": [
          {
            \"address\": \"$HOST\",
            \"port\": $PORT,
            \"users\": [
              {
                \"id\": \"$UUID\",
                \"encryption\": \"none\",
                \"flow\": \"$FLOW\"
              }
            ]
          }
        ]
      },
      \"streamSettings\": {
        $STREAM_SETTINGS
      }
    }"

# Check for WireGuard link if VLESS link was not found
elif [ -n "$WIREGUARD_LINK" ]; then
    echo "[*] Found WIREGUARD_LINK. Configuring for WireGuard proxy."

    echo "[*] Parsing WireGuard config..."
    # Use xargs to trim whitespace from parsed values
    SECRET_KEY=$(echo "$WIREGUARD_LINK" | grep 'PrivateKey' | cut -d '=' -f 2 | xargs)
    PEER_PUBLIC_KEY=$(echo "$WIREGUARD_LINK" | grep 'PublicKey' | cut -d '=' -f 2 | xargs)
    PEER_PRESHARED_KEY=$(echo "$WIREGUARD_LINK" | grep 'PresharedKey' | cut -d '=' -f 2 | xargs)
    PEER_ENDPOINT=$(echo "$WIREGUARD_LINK" | grep 'Endpoint' | cut -d '=' -f 2 | xargs)
    CLIENT_ADDRESS=$(echo "$WIREGUARD_LINK" | grep 'Address' | cut -d '=' -f 2 | xargs | cut -d ',' -f 1)
    
    # Parse MTU from the config, with a fallback default of 1420
    PARSED_MTU=$(echo "$WIREGUARD_LINK" | grep 'MTU' | cut -d '=' -f 2 | xargs)
    MTU=${PARSED_MTU:-1420}

    echo "[*] WireGuard Parsed:"
    echo "  Client PrivateKey=*** (hidden)"
    echo "  Client Address=$CLIENT_ADDRESS"
    echo "  Peer PublicKey=$PEER_PUBLIC_KEY"
    echo "  Peer PresharedKey=" $( [ -n "$PEER_PRESHARED_KEY" ] && echo "*** (hidden)" || echo "N/A" )
    echo "  Peer Endpoint=$PEER_ENDPOINT"
    echo "  MTU=$MTU"

    # Add PresharedKey to JSON only if it exists to avoid syntax errors
    if [ -n "$PEER_PRESHARED_KEY" ]; then
        PSK_LINE="\"presharedKey\": \"$PEER_PRESHARED_KEY\","
    else
        PSK_LINE=""
    fi

    # Define the outbound configuration for WireGuard
    OUTBOUND_CONFIG="{
      \"protocol\": \"wireguard\",
      \"tag\": \"proxy\",
      \"settings\": {
        \"secretKey\": \"$SECRET_KEY\",
        \"address\": [\"$CLIENT_ADDRESS\"],
        \"mtu\": $MTU,
        \"peers\": [
          {
            \"publicKey\": \"$PEER_PUBLIC_KEY\",
            $PSK_LINE
            \"endpoint\": \"$PEER_ENDPOINT\",
            \"allowedIPs\": [\"0.0.0.0/0\", \"::/0\"],
            \"keepalive\": 25
          }
        ]
      }
    }"

else
    echo "[!] FATAL ERROR: No proxy configuration provided."
    echo "    Please set either the X_UI_LINK (for VLESS) or WIREGUARD_LINK (for WireGuard) environment variable."
    exit 1
fi


# --- Common Configuration Section ---

echo "[*] Preparing SOCKS/HTTP inbounds..."

SOCKS_SETTINGS='"settings": {}'
HTTP_SETTINGS='"settings": {}'

if [ -n "$PROXY_USER" ] && [ -n "$PROXY_PASSWORD" ]; then
  echo "[*] Enabling SOCKS/HTTP authentication with user: $PROXY_USER"
  SOCKS_SETTINGS="\"settings\": {\"auth\": \"password\", \"accounts\": [{\"user\": \"$PROXY_USER\", \"pass\": \"$PROXY_PASSWORD\"}], \"udp\": true, \"ip\": \"127.0.0.1\"}"
  HTTP_SETTINGS="\"settings\": {\"accounts\": [{\"user\": \"$PROXY_USER\", \"pass\": \"$PROXY_PASSWORD\"}]}"
else
  echo "[*] SOCKS/HTTP authentication not configured."
fi

echo "[*] Generating final Xray config.json..."
cat > /etc/xray/config.json <<EOF
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "port": 1080,
      "listen": "0.0.0.0",
      "protocol": "socks",
      $SOCKS_SETTINGS
    },
    {
      "port": 3128,
      "listen": "0.0.0.0",
      "protocol": "http",
      $HTTP_SETTINGS
    }
  ],
  "outbounds": [
    $OUTBOUND_CONFIG,
    {
        "protocol": "freedom",
        "tag": "direct"
    },
    {
        "protocol": "freedom",
        "tag": "local_requests",
        "settings": {
          "destinationOverride": {
            "server": {
              "address": "host.docker.internal"
            }
          }
        }
    }
  ],
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "rules": [
      {
        "type": "field",
        "domain": ["localhost"],
        "outboundTag": "local_requests"
      },
      {
        "type": "field",
        "ip": ["127.0.0.1/32"],
        "outboundTag": "local_requests"
      },
      {
        "type": "field",
        "ip": [ "geoip:private" ],
        "outboundTag": "direct"
      },
      {
        "type": "field",
        "ip": [ "0.0.0.0/0", "::/0" ],
        "outboundTag": "proxy"
      }
    ]
  }
}
EOF

echo "[*] Configuration complete. Starting Xray..."
exec xray run -config /etc/xray/config.json
