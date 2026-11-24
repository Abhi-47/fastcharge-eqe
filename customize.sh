#!/system/bin/sh
# FastCharge EQE - Installation customization script
# Runs during Magisk module installation
# Maintainer: AK-47

MODDIR=${0%/*}

ui_print " "
ui_print "*****************************************************"
ui_print "*  FastCharge EQE - Motorola Edge 50 Pro (eqe)      *"
ui_print "*  USB-PD/PPS Optimization for 125W + 68W           *"
ui_print "*  Maintainer: AK-47                                *"
ui_print "*****************************************************"
ui_print " "

# Check device
device=$(getprop ro.product.device)
model=$(getprop ro.product.model)
ui_print "- Device: $model ($device)"

if [ "$device" != "eqe" ]; then
    ui_print "! WARNING: This module is designed for Motorola Edge 50 Pro (eqe)"
    ui_print "! Your device is: $device"
    ui_print "! Continuing anyway - but functionality may be limited"
    ui_print " "
fi

# Check Android version
android_ver=$(getprop ro.build.version.release)
ui_print "- Android version: $android_ver"

# Check Magisk version
magisk_ver=$(getprop ro.magisk.version 2>/dev/null || echo "unknown")
ui_print "- Magisk version: $magisk_ver"

# Check if custom ROM
build_type=$(getprop ro.build.type)
build_tags=$(getprop ro.build.tags)
rom_name=$(getprop ro.rom.name 2>/dev/null || getprop ro.product.name 2>/dev/null || echo "stock")
ui_print "- ROM: $rom_name (type: $build_type)"

ui_print " "
ui_print "- Installing FastCharge EQE v2.0 module..."
ui_print " "

# Set permissions
set_perm_recursive $MODDIR 0 0 0755 0644
set_perm $MODDIR/post-fs-data.sh 0 0 0755
set_perm $MODDIR/service.sh 0 0 0755

ui_print "- Setting up sysfs nodes for USB-PD/PPS..."
ui_print "- Configuring 125W TurboPower (20V/6.25A) profile..."
ui_print "- Configuring 68W PD/PPS (20V/3.4A) profile..."
ui_print "- Configuring charging current/voltage limits..."
ui_print "- Disabling adaptive/slow charging throttles..."
ui_print "- Enabling QC 5 / PD 3.0 PPS negotiation..."
ui_print "- Setting thermal throttle at 44°C / resume at 40°C..."
ui_print "- Custom ROM compatibility enabled..."
ui_print " "

ui_print "*****************************************************"
ui_print "*  Installation complete!                           *"
ui_print "*  Reboot to activate all optimizations.            *"
ui_print "*  Log file: /data/adb/modules/fastcharge-eqe/charge.log"
ui_print "*****************************************************"
ui_print " "