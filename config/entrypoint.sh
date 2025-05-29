#!/bin/sh

echo "[*] Parsing VLESS link..."

# Corrected environment variable name here
URI="$X_UI_LINK"
echo "Environment X_UI_LINK is: $X_UI_LINK" # Corrected from 3X_UI_LINK

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

echo "[*] Parsed:"
echo "  UUID=$UUID"
echo "  HOST=$HOST"
echo "  PORT=$PORT"
echo "  TYPE=$TYPE"
echo "  SECURITY=$SECURITY"
echo "  FLOW=$FLOW"
# Add other parsed params if needed for debugging
echo "  PBK=$PBK"
echo "  FP=$FP"
echo "  SNI=$SNI"
echo "  SID=$SID"
echo "  SPX=$SPX"

echo "[*] Generating config..."

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
    },
    \"tcpSettings\": {
      \"header\": {
        \"type\": \"none\"
      }
    }"
elif [ "$SECURITY" = "tls" ]; then
  # Assuming wsSettings for TLS, adjust if it's different (e.g., tcpSettings with tls)
  STREAM_SETTINGS="$STREAM_SETTINGS,
    \"security\": \"tls\",
    \"tlsSettings\": {
      \"serverName\": \"$SNI\",
      \"allowInsecure\": false,
      \"alpn\": [\"http/1.1\"],
      \"fingerprint\": \"$FP\"
    },
    \"wsSettings\": {
      \"path\": \"$SPX\",
      \"headers\": {
        \"Host\": \"$SNI\"
      }
    }"
fi

# Prepare SOCKS and HTTP settings based on PROXY_USER and PROXY_PASSWORD
SOCKS_SETTINGS='"settings": {}'
HTTP_SETTINGS='"settings": {}'

# Check if both PROXY_USER and PROXY_PASSWORD are set and not empty
if [ -n "$PROXY_USER" ] && [ -n "$PROXY_PASSWORD" ]; then
  echo "[*] Enabling SOCKS/HTTP authentication with user: $PROXY_USER"
  SOCKS_SETTINGS="\"settings\": {
        \"auth\": \"password\",
        \"accounts\": [
          {
            \"user\": \"$PROXY_USER\",
            \"pass\": \"$PROXY_PASSWORD\"
          }
        ],
        \"udp\": true,
        \"ip\": \"127.0.0.1\"
      }"
  HTTP_SETTINGS="\"settings\": {
        \"accounts\": [
          {
            \"user\": \"$PROXY_USER\",
            \"pass\": \"$PROXY_PASSWORD\"
          }
        ]
      }"
else
  echo "[*] SOCKS/HTTP authentication not configured (PROXY_USER or PROXY_PASSWORD not set/empty)."
fi


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
    {
      "protocol": "vless",
      "tag": "proxy",
      "settings": {
        "vnext": [
          {
            "address": "$HOST",
            "port": $PORT,
            "users": [
              {
                "id": "$UUID",
                "encryption": "none",
                "flow": "$FLOW"
              }
            ]
          }
        ]
      },
      "streamSettings": {
        $STREAM_SETTINGS
      }
    },
    {
        "protocol": "freedom",
        "tag": "direct"
    }
  ],
  "routing": {
        "domainStrategy": "IPIfNonMatch",
        "rules": [
            {
                "type": "field",
                "ip": [
                    "geoip:private"
                ],
                "outboundTag": "direct"
            },
            {
              "type": "field",
              "ip": ["0.0.0.0/0", "::/0"],
              "outboundTag": "proxy"
            }
        ]
    }
}
EOF

# echo "[*] Generated config:"
# cat /etc/xray/config.json # For debugging, you might want to remove this in production

echo "[*] Starting Xray..."
exec xray run -config /etc/xray/config.json
