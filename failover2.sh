#!/bin/bash
### This script must be on node3 (backup server2).Execute every 1 minutes via cron.

LOGFILE='/var/log/failover.log'
if [ ! -f "$LOGFILE" ]; then
    touch "$LOGFILE"
    echo "--- Log Created: $(date) ---" > "$LOGFILE"
fi
# --- CONFIGURATION ---
API_TOKEN=""
ZONE_ID=""
RECORD_ID=""
RECORD_NAME="app.example.com"
HOSTNAME=$(hostname)

PRIMARY_IP="188.xxx.xxx.xxx"
BACKUP1_IP="188.yyy.yyy.yyy"
BACKUP2_IP="159.zzz.zzz.zzz"

# Notification Config (Fill one or both)
TELEGRAM_TOKEN=""
TELEGRAM_CHAT_ID=""
DISCORD_WEBHOOK=""

# --- NOTIFICATION FUNCTION ---
notify() {
    local MESSAGE=$1
    # Telegram
    if [ ! -z "$TELEGRAM_TOKEN" ]; then
       curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_TOKEN/sendMessage" \
     -d "chat_id=$TELEGRAM_CHAT_ID" \
     -d "text=$MESSAGE" \
     -d "parse_mode=HTML" > /dev/nulll
    fi
    # Discord
    if [ ! -z "$DISCORD_WEBHOOK" ]; then
        curl -s -H "Content-Type: application/json" -X POST \
             -d "{\"content\": \"$MESSAGE\"}" "$DISCORD_WEBHOOK" > /dev/null
    fi
}

# --- HEALTH CHECK FUNCTION ---
check_health() {
    # Returns 0 if server responds with HTTP 200, else 1
    status=$(curl -o /dev/null -s -w "%{http_code}" --connect-timeout 5 "http://$1:8080/status.php")
    if [ "$status" == "200" ]; then return 0; else return 1; fi
}

# Retry health check 3 times with a 5s delay
check_with_retry() {
    for i in {1..3}; do
        if check_health "$1"; then return 0; fi
        sleep 5
    done
    return 1
}

# --- FAILOVER LOGIC ---
if check_health "$PRIMARY_IP"; then
    TARGET_IP=$PRIMARY_IP

elif check_health "$BACKUP1_IP"; then
    exit 0
else
    TARGET_IP=$BACKUP2_IP
fi


# --- UPDATE CLOUDFLARE ---
# Fetch current DNS record IP to avoid unnecessary API calls
CURRENT_IP=$(curl -X GET "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records?type=A&name=app.nchome.eu" \
     -H "Authorization: Bearer $API_TOKEN" \
     -H "Content-Type: application/json" | jq -r '.result[0].content')

if [ "$TARGET_IP" != "$CURRENT_IP" ]; then
    echo "$(date) Failing over from $CURRENT_IP to $TARGET_IP at '$(date +"%Y/%m/%d-%H:%M:%S")' from '$HOSTNAME'" | tee -a $LOGFILE
    UPDATE=$(curl https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records/$RECORD_ID \
    -X PUT \
    -H 'Content-Type: application/json' \
    -H "Authorization: Bearer $API_TOKEN" \
    -d '{
          "name": "'"$RECORD_NAME"'",
          "ttl": 1,
          "type": "A",
          "comment": "Record changed at '$(date +"%Y/%m/%d-%H:%M:%S")' from '$HOSTNAME' ",
          "content": "'"$TARGET_IP"'",
          "proxied": true
        }')
    if echo "$UPDATE" | grep -q '"success":true'; then
        notify "⚠️ Nextcloud Failover: DNS updated from $CURRENT_IP to $TARGET_IP on $(date +"%Y/%m/%d-%H:%M:%S") from $HOSTNAME"
    else
        notify "❌ ERROR: Cloudflare update failed for $RECORD_NAME"
    fi
fi
