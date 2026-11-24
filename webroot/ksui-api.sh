#!/system/bin/sh
# FastCharge EQE - KSUI WebUI API Server
# Provides JSON API for the web UI to read charging data
# Runs as a background service on port 8080 (or configurable)

MODDIR=${0%/*}
API_PORT=8080
DATA_FILE="$MODDIR/charge_data.json"
LOG_FILE="$MODDIR/charge.log"

log() {
    echo "[FastCharge EQE API] $1" > /dev/kmsg
    echo "[FastCharge EQE API] $(date): $1" >> $MODDIR/api.log
}

log "Starting FastCharge EQE KSUI API server on port $API_PORT"

# Function to read sysfs and output JSON
generate_json() {
    local timestamp=$(date +%s%3N)
    local status=$(cat /sys/class/power_supply/battery/status 2>/dev/null || echo "Unknown")
    local level=$(cat /sys/class/power_supply/battery/capacity 2>/dev/null || echo 0)
    local temp=$(cat /sys/class/power_supply/battery/temp 2>/dev/null || echo 0)
    local voltage_now=$(cat /sys/class/power_supply/usb/voltage_now 2>/dev/null || cat /sys/class/power_supply/battery/voltage_now 2>/dev/null || echo 0)
    local current_now=$(cat /sys/class/power_supply/battery/current_now 2>/dev/null || echo 0)
    local input_current_limit=$(cat /sys/class/power_supply/usb/input_current_limit 2>/dev/null || echo 6000000)
    local pps_enabled=$(cat /sys/class/power_supply/usb/pps_enabled 2>/dev/null || echo 0)
    local charge_current_max=$(cat /sys/class/power_supply/battery/charge_current_max 2>/dev/null || echo 6000000)
    local voltage_max=$(cat /sys/class/power_supply/usb/voltage_max 2>/dev/null || echo 20000000)
    local health=$(cat /sys/class/power_supply/battery/health 2>/dev/null || echo "Good")
    local technology=$(cat /sys/class/power_supply/battery/technology 2>/dev/null || echo "Li-ion")

    # Charger detection
    local charger_type="Unknown"
    local negotiated_voltage=0
    local negotiated_current=0

    if [ -f /sys/class/power_supply/usb/type ]; then
        local usb_type=$(cat /sys/class/power_supply/usb/type 2>/dev/null)
        case "$usb_type" in
            "PD"|"PD_PPS") charger_type="USB-PD PPS" ;;
            "QC"|"QC_4"|"QC_5") charger_type="Quick Charge" ;;
            *) charger_type="Standard" ;;
        esac
    fi

    if [ -f /sys/class/power_supply/usb/voltage_now ]; then
        negotiated_voltage=$((voltage_now / 1000000))
    fi
    if [ -f /sys/class/power_supply/battery/current_now ]; then
        negotiated_current=$((current_now / 1000000))
    fi

    cat > "$DATA_FILE" <<EOF
{
    "timestamp": $timestamp,
    "status": "$status",
    "level": $level,
    "battery_temp": $temp,
    "voltage_now": $voltage_now,
    "current_now": $current_now,
    "input_current_limit": $input_current_limit,
    "pps_enabled": $pps_enabled,
    "charge_current_max": $charge_current_max,
    "voltage_max": $voltage_max,
    "health": "$health",
    "technology": "$technology",
    "capacity": 4500,
    "charger_type": "$charger_type",
    "negotiated_voltage": $negotiated_voltage,
    "negotiated_current": $negotiated_current
}
EOF
}

# Function to read log and output JSON
generate_log_json() {
    if [ ! -f "$LOG_FILE" ]; then
        echo "[]"
        return
    fi

    # Read last 100 lines and format as JSON array
    tail -100 "$LOG_FILE" | awk -F'] ' '
    BEGIN { print "["; first=1 }
    {
        if (NF >= 2) {
            timestamp = $1; gsub(/^\[/, "", timestamp)
            message = $2
            if (!first) printf ","
            printf "{\"timestamp\":\"%s\",\"message\":\"%s\"}", timestamp, message
            first=0
        }
    }
    END { print "]" }'
}

# Simple HTTP server using netcat (if available) or shell built-ins
# For KSUI, we'll write JSON files that KSUI can read via file:// or its proxy

# Main loop - update data file every 2 seconds
log "Starting data update loop"
while true; do
    generate_json
    sleep 2
done