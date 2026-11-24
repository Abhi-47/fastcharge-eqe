#!/system/bin/sh
# FastCharge EQE - Late-start service script
# Runs after boot completes to fine-tune charging and monitor
# Supports: 125W TurboPower + 68W PD/PPS
# Thermal tuning: throttle at 44°C, resume at 40°C
# Maintainer: AK-47
# Custom ROM compatible

MODDIR=${0%/*}

log() {
    echo "[FastCharge EQE] $1" > /dev/kmsg
    echo "[FastCharge EQE] $(date): $1" >> $MODDIR/charge.log
}

log "FastCharge EQE late-start service started (v2.0 - AK-47)"

# Wait for full boot
while [ "$(getprop sys.boot_completed)" != "1" ]; do
    sleep 1
done

log "Boot completed, applying runtime optimizations"

# Give system time to settle
sleep 5

# ============================================================
# Runtime Charging Optimization
# ============================================================

# Re-apply PPS settings (some get reset during boot)
if [ -f "/sys/class/power_supply/usb/pps_enabled" ]; then
    echo 1 > /sys/class/power_supply/usb/pps_enabled 2>/dev/null
    log "Re-enabled PPS at runtime"
fi

# Force maximum input current for active charging
if [ -f "/sys/class/power_supply/usb/input_current_limit" ]; then
    echo 6000000 > /sys/class/power_supply/usb/input_current_limit 2>/dev/null
    log "Set runtime USB input current limit to 6A"
fi

# ============================================================
# Thermal Management - 44°C Throttle / 40°C Resume
# ============================================================

THERMAL_THROTTLE_TEMP=44
THERMAL_RESUME_TEMP=40

monitor_charging() {
    while true; do
        sleep 10

        # Check if charging
        status=$(cat /sys/class/power_supply/battery/status 2>/dev/null)
        if [ "$status" = "Charging" ] || [ "$status" = "Full" ]; then
            # Get battery temp (in tenths of °C)
            temp=$(cat /sys/class/power_supply/battery/temp 2>/dev/null)
            temp_c=$((temp / 10))

            # Get current limit
            curr_limit=$(cat /sys/class/power_supply/usb/input_current_limit 2>/dev/null)
            curr_limit_a=$((curr_limit / 1000000))

            log "Charging: status=$status, temp=${temp_c}°C, current_limit=${curr_limit_a}A"

            # Thermal throttling logic
            if [ "$temp_c" -ge "$THERMAL_THROTTLE_TEMP" ] && [ "$curr_limit_a" -gt 3 ]; then
                # Throttle to 3A (~60W) at 44°C+
                echo 3000000 > /sys/class/power_supply/usb/input_current_limit 2>/dev/null
                log "THERMAL THROTTLE: Battery at ${temp_c}°C (>=${THERMAL_THROTTLE_TEMP}°C), reduced current to 3A"
            elif [ "$temp_c" -le "$THERMAL_RESUME_TEMP" ] && [ "$curr_limit_a" -lt 5 ]; then
                # Resume full speed at 40°C
                echo 6000000 > /sys/class/power_supply/usb/input_current_limit 2>/dev/null
                log "THERMAL RESUME: Battery at ${temp_c}°C (<=${THERMAL_RESUME_TEMP}°C), restored current to 6A"
            fi

            # Ensure PPS stays enabled
            if [ -f "/sys/class/power_supply/usb/pps_enabled" ]; then
                pps=$(cat /sys/class/power_supply/usb/pps_enabled 2>/dev/null)
                if [ "$pps" != "1" ]; then
                    echo 1 > /sys/class/power_supply/usb/pps_enabled 2>/dev/null
                    log "Re-enabled PPS during charging"
                fi
            fi

            # Log negotiated voltage if available
            if [ -f "/sys/class/power_supply/usb/voltage_now" ]; then
                volt=$(cat /sys/class/power_supply/usb/voltage_now 2>/dev/null)
                volt_v=$((volt / 1000000))
                log "Negotiated voltage: ${volt_v}V"
            fi

            # Log current now if available
            if [ -f "/sys/class/power_supply/battery/current_now" ]; then
                curr=$(cat /sys/class/power_supply/battery/current_now 2>/dev/null)
                curr_a=$((curr / 1000000))
                log "Battery current: ${curr_a}A"
            fi
        fi
    done
}

# Start monitoring in background
monitor_charging &

log "Runtime charging monitor with thermal management started"

# Keep service alive
while true; do
    sleep 3600
    log "Service heartbeat - still running"
done