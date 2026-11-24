#!/system/bin/sh
# FastCharge EQE - Post-fs-data script
# Runs at early boot to configure USB-PD/PPS and charging optimizations
# Supports: 125W TurboPower (20V/6.25A) + 68W PD/PPS (20V/3.4A)
# Thermal tuning: throttle at 44°C
# Maintainer: AK-47
# Custom ROM compatible

MODDIR=${0%/*}

log() {
    echo "[FastCharge EQE] $1" > /dev/kmsg
    echo "[FastCharge EQE] $1" >> $MODDIR/charge.log
}

log "Starting FastCharge EQE module for Motorola Edge 50 Pro (eqe)"
log "Version 1.1 - Maintainer: AK-47 - Custom ROM support enabled"

# Wait for USB subsystem to be ready
sleep 3

# ============================================================
# USB-PD / PPS Negotiation Optimization
# ============================================================

# Force PPS enable on USB Type-C controller (qcom,sm8650-usb)
# Motorola Edge 50 Pro uses SM8635 (Snapdragon 7 Gen 3) with qcom USB controller

# Enable PPS (Programmable Power Supply) mode
pps_nodes=(
    "/sys/class/power_supply/usb/pps_enabled"
    "/sys/class/power_supply/usb/pps_max_voltage"
    "/sys/class/power_supply/usb/pps_min_voltage"
    "/sys/class/power_supply/usb/pps_max_current"
    "/sys/class/typec/port0/pps_enabled"
    "/sys/class/typec/port1/pps_enabled"
    "/sys/bus/typec/devices/typec-port0/pps_enabled"
    "/sys/bus/typec/devices/typec-port1/pps_enabled"
)

for node in "${pps_nodes[@]}"; do
    if [ -f "$node" ]; then
        echo 1 > "$node" 2>/dev/null && log "Enabled PPS: $node"
    fi
done

# ============================================================
# PPS Voltage/Current Profiles
# ============================================================
# Dual profile support:
# - 125W TurboPower: 5V-20V @ 6.25A (proprietary Motorola)
# - 68W PD/PPS: 5V-20V @ 3.4A (standard USB-PD 3.0 PPS)
# We set max limits to support both; charger negotiates best match

# 125W TurboPower max (20V * 6.25A = 125W)
if [ -f "/sys/class/power_supply/usb/pps_max_voltage" ]; then
    echo 20000000 > /sys/class/power_supply/usb/pps_max_voltage 2>/dev/null  # 20V in uV
    log "Set PPS max voltage to 20V (125W/68W)"
fi

if [ -f "/sys/class/power_supply/usb/pps_min_voltage" ]; then
    echo 3300000 > /sys/class/power_supply/usb/pps_min_voltage 2>/dev/null  # 3.3V in uV (PPS min)
    log "Set PPS min voltage to 3.3V"
fi

if [ -f "/sys/class/power_supply/usb/pps_max_current" ]; then
    echo 6250000 > /sys/class/power_supply/usb/pps_max_current 2>/dev/null  # 6.25A in uA (125W)
    log "Set PPS max current to 6.25A (125W TurboPower)"
fi

# Also set 68W profile nodes if they exist (some ROMs expose separate profiles)
if [ -f "/sys/class/power_supply/usb/pps_68w_max_current" ]; then
    echo 3400000 > /sys/class/power_supply/usb/pps_68w_max_current 2>/dev/null  # 3.4A for 68W
    log "Set 68W PPS max current to 3.4A"
fi

# ============================================================
# USB Type-C Port Configuration
# ============================================================

# Force DRP (Dual Role Port) mode and enable all alternate modes
typec_ports="/sys/class/typec/port*"
for port in $typec_ports; do
    if [ -f "$port/drp" ]; then
        echo "on" > "$port/drp" 2>/dev/null && log "Enabled DRP on $port"
    fi
    if [ -f "$port/alt_modes" ]; then
        echo 1 > "$port/alt_modes" 2>/dev/null && log "Enabled alt modes on $port"
    fi
    # Force PD revision 3.0 with PPS support
    if [ -f "$port/pd_revision" ]; then
        echo 3 > "$port/pd_revision" 2>/dev/null && log "Set PD revision 3.0 on $port"
    fi
    # Enable PPS on port level
    if [ -f "$port/pps_supported" ]; then
        echo 1 > "$port/pps_supported" 2>/dev/null && log "Enabled PPS support on $port"
    fi
done

# ============================================================
# Charging Current / Voltage Limits
# ============================================================

# Motorola-specific charging control nodes (common on Moto devices)
moto_charge_nodes=(
    "/sys/class/power_supply/battery/charge_current_max"
    "/sys/class/power_supply/battery/input_current_max"
    "/sys/class/power_supply/battery/constant_charge_current_max"
    "/sys/class/power_supply/usb/input_current_limit"
    "/sys/class/power_supply/usb/voltage_max"
    "/sys/class/power_supply/battery/voltage_max"
)

# Set maximum charging current (6A for 125W, 3.4A for 68W - we set high to allow negotiation)
for node in "${moto_charge_nodes[@]}"; do
    if [ -f "$node" ]; then
        echo 6000000 > "$node" 2>/dev/null && log "Set max current on $node"
    fi
done

# Set voltage max to 20V for PPS negotiation (both 125W and 68W use 20V)
for node in "/sys/class/power_supply/usb/voltage_max" "/sys/class/power_supply/battery/voltage_max"; do
    if [ -f "$node" ]; then
        echo 20000000 > "$node" 2>/dev/null && log "Set voltage max to 20V on $node"
    fi
done

# ============================================================
# Thermal Tuning - 44°C Throttle Point
# ============================================================
# When battery/skin temp reaches 44°C, reduce charging current to protect battery

THERMAL_THROTTLE_TEMP=44000  # 44°C in millidegrees
THERMAL_RESUME_TEMP=40000    # 40°C resume full speed

log "Configuring thermal tuning: throttle at 44°C, resume at 40°C"

# Find battery and charger thermal zones
for zone in /sys/class/thermal/thermal_zone*; do
    if [ -f "$zone/type" ]; then
        type=$(cat "$zone/type" 2>/dev/null)
        case "$type" in
            battery*|skin*|charger*|usb*|pmic*|bq25*|smb*)
                log "Found thermal zone: $zone (type: $type)"

                # Set trip point for throttling (passive cooling)
                for trip in "$zone"/trip_point_*_temp; do
                    if [ -f "$trip" ]; then
                        current=$(cat "$trip" 2>/dev/null)
                        trip_name=$(basename "$trip")
                        # Look for passive/critical trip points
                        case "$trip_name" in
                            *passive*|*hot*|*throttle*)
                                if [ "$current" -lt "$THERMAL_THROTTLE_TEMP" ]; then
                                    echo "$THERMAL_THROTTLE_TEMP" > "$trip" 2>/dev/null
                                    log "Set thermal throttle trip $trip_name to 44°C (was $((current/1000))°C)"
                                fi
                                ;;
                        esac
                    fi
                done

                # Set cooling device binding if available
                if [ -d "$zone/cooling_device"* ]; then
                    for cdev in "$zone"/cooling_device*; do
                        if [ -f "$cdev/type" ]; then
                            ctype=$(cat "$cdev/type" 2>/dev/null)
                            case "$ctype" in
                                *charg*|*battery*|*usb*)
                                    echo 1 > "$cdev/enable" 2>/dev/null
                                    log "Enabled cooling device: $cdev ($ctype)"
                                    ;;
                            esac
                        fi
                    done
                fi
                ;;
        esac
    fi
done

# Battery-specific thermal limits
if [ -f "/sys/class/power_supply/battery/charge_temp_limit" ]; then
    echo "$THERMAL_THROTTLE_TEMP" > /sys/class/power_supply/battery/charge_temp_limit 2>/dev/null
    log "Set battery charge temp limit to 44°C"
fi

if [ -f "/sys/class/power_supply/battery/cool_down_temp" ]; then
    echo "$THERMAL_RESUME_TEMP" > /sys/class/power_supply/battery/cool_down_temp 2>/dev/null
    log "Set battery cool-down resume temp to 40°C"
fi

# ============================================================
# Disable Charging Throttles
# ============================================================

# Motorola-specific throttle disable
if [ -f "/sys/class/power_supply/battery/charging_disabled" ]; then
    echo 0 > /sys/class/power_supply/battery/charging_disabled 2>/dev/null && log "Ensured charging not disabled"
fi

# Disable input current limit throttling when screen on
if [ -f "/sys/class/power_supply/usb/input_current_limit" ]; then
    echo 6000000 > /sys/class/power_supply/usb/input_current_limit 2>/dev/null && log "Set USB input current limit to 6A"
fi

# ============================================================
# QC/PD Protocol Negotiation
# ============================================================

# Force QC 4+/5 and PD 3.0 PPS capability advertisement
qc_nodes=(
    "/sys/class/power_supply/usb/qc_mode"
    "/sys/class/power_supply/usb/pd_mode"
    "/sys/class/power_supply/usb/fast_charge_mode"
)

for node in "${qc_nodes[@]}"; do
    if [ -f "$node" ]; then
        echo 5 > "$node" 2>/dev/null && log "Set QC/PD mode to max on $node"
    fi
done

# ============================================================
# Battery Health / Charging Algorithm
# ============================================================

# Disable adaptive/slow charging features that limit speed
adaptive_nodes=(
    "/sys/class/power_supply/battery/adaptive_charging_enabled"
    "/sys/class/power_supply/battery/slow_charging_enabled"
    "/sys/class/power_supply/battery/battery_health_mode"
    "/sys/class/power_supply/battery/charge_optimization_enabled"
)

for node in "${adaptive_nodes[@]}"; do
    if [ -f "$node" ]; then
        echo 0 > "$node" 2>/dev/null && log "Disabled adaptive/slow charging: $node"
    fi
done

# Force charging algorithm to "fast" mode
if [ -f "/sys/class/power_supply/battery/charging_algorithm" ]; then
    echo "fast" > /sys/class/power_supply/battery/charging_algorithm 2>/dev/null && log "Set charging algorithm to fast"
fi

# Custom ROM compatibility: some ROMs use different node names
custom_rom_nodes=(
    "/sys/class/power_supply/battery/fast_charge_enable"
    "/sys/class/power_supply/battery/rapid_charge_enable"
    "/sys/class/power_supply/usb/fast_charge_enable"
    "/sys/module/smb1380/parameters/fastchg_enable"
    "/sys/module/bq25980/parameters/fastchg_enable"
    "/sys/module/qcom_battery/parameters/fast_charge_enable"
)

for node in "${custom_rom_nodes[@]}"; do
    if [ -f "$node" ]; then
        echo 1 > "$node" 2>/dev/null && log "Enabled custom ROM fast charge node: $node"
    fi
done

# ============================================================
# Persist Settings via setprop (for services that read props)
# ============================================================

setprop persist.vendor.fastcharge.enable 1
setprop persist.vendor.pps.enable 1
setprop persist.vendor.usb.pd.pps 1
setprop persist.vendor.charge.max_current 6000
setprop persist.vendor.charge.max_voltage 20000
setprop persist.vendor.qc.mode 5
setprop persist.vendor.thermal.throttle_temp 44
setprop persist.vendor.thermal.resume_temp 40
setprop persist.vendor.charge.profile_125w 1
setprop persist.vendor.charge.profile_68w 1

log "FastCharge EQE initialization complete"

# ============================================================
# Background Monitor - Re-apply settings + Thermal Management
# ============================================================

(
    while true; do
        sleep 30

        # Re-check critical nodes and re-apply if needed
        if [ -f "/sys/class/power_supply/usb/pps_enabled" ]; then
            curr=$(cat /sys/class/power_supply/usb/pps_enabled 2>/dev/null)
            [ "$curr" != "1" ] && echo 1 > /sys/class/power_supply/usb/pps_enabled 2>/dev/null
        fi

        if [ -f "/sys/class/power_supply/usb/input_current_limit" ]; then
            curr=$(cat /sys/class/power_supply/usb/input_current_limit 2>/dev/null)
            [ "$curr" -lt 5000000 ] && echo 6000000 > /sys/class/power_supply/usb/input_current_limit 2>/dev/null
        fi

        # Thermal monitoring: check battery temp and throttle if needed
        if [ -f "/sys/class/power_supply/battery/temp" ]; then
            bat_temp=$(cat /sys/class/power_supply/battery/temp 2>/dev/null)
            bat_temp_c=$((bat_temp / 10))

            # Get current limit
            curr_limit=$(cat /sys/class/power_supply/usb/input_current_limit 2>/dev/null)
            curr_limit_a=$((curr_limit / 1000000))

            if [ "$bat_temp_c" -ge 44 ] && [ "$curr_limit_a" -gt 3 ]; then
                # Throttle to 3A (approx 60W) at 44°C+
                echo 3000000 > /sys/class/power_supply/usb/input_current_limit 2>/dev/null
                log "THERMAL THROTTLE: Battery at ${bat_temp_c}°C, reduced current to 3A"
            elif [ "$bat_temp_c" -le 40 ] && [ "$curr_limit_a" -lt 5 ]; then
                # Resume full speed at 40°C
                echo 6000000 > /sys/class/power_supply/usb/input_current_limit 2>/dev/null
                log "THERMAL RESUME: Battery at ${bat_temp_c}°C, restored current to 6A"
            fi
        fi
    done
) &

log "Background monitor with thermal management started"