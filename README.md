# FastCharge EQE - Motorola Edge 50 Pro (eqe)

Magisk module to enable USB-PD/PPS negotiation and maximize charging speed for the Motorola Edge 50 Pro with **125W TurboPower** and **68W PD/PPS** charging support. Includes **KSUI WebUI** for real-time charging monitoring.

## Features

- **Dual Charging Profiles**: 125W TurboPower (20V/6.25A) + 68W USB-PD 3.0 PPS (20V/3.4A)
- **USB-PD 3.0 + PPS Support** - Forces Programmable Power Supply negotiation for 3.3V-20V at up to 6.25A
- **QC 4+/5 Compatibility** - Enables Quick Charge 5 protocol negotiation
- **Charging Throttle Removal** - Disables adaptive/slow charging, screen-on throttling, battery health modes
- **Maximum Current/Voltage Limits** - Sets input current to 6A and voltage to 20V for 125W peak
- **Thermal Tuning** - **Throttles at 44°C, resumes at 40°C** (protects battery while maximizing speed)
- **Runtime Monitoring** - Background service maintains optimal settings during charging
- **KSUI WebUI** - Real-time voltage, current, power, temperature graphs with charging history
- **Custom ROM Compatible** - Works with LineageOS, PixelOS, crDroid, and other AOSP-based ROMs
- **SELinux Policy** - Proper permissions for sysfs access

## Requirements

- Motorola Edge 50 Pro (codename: `eqe`)
- Magisk 26.0+ (rooted)
- Android 14+ (tested on stock ROM and custom ROMs)
- **KSUI** (KernelSU Manager) for WebUI access
- Compatible charger:
  - **125W**: Motorola 125W TurboPower charger (proprietary)
  - **68W**: Any USB-PD 3.0 PPS charger (65W+ recommended, e.g., 68W/100W/140W GaN chargers)

## Installation

1. Download the latest `FastCharge-EQE-v1.1-ksui.zip` from releases
2. Open Magisk app → Modules → Install from storage
3. Select the ZIP file
4. Reboot device
5. Open **KSUI app** → **Modules** → **FastCharge EQE** → Tap to open WebUI

## How It Works

### post-fs-data.sh (Early Boot)
- Enables PPS on USB Type-C controller (qcom SM8635)
- Sets PPS voltage range: 3.3V-20V, max current: 6.25A (125W) / 3.4A (68W)
- Configures QC/PD protocol negotiation to maximum
- Disables adaptive charging, slow charging, battery health modes
- **Sets thermal throttle trip points to 44°C, resume at 40°C**
- Sets persistent vendor properties for both 125W and 68W profiles

### service.sh (Late Boot)
- Re-applies critical settings after full boot
- Monitors charging status every 10 seconds
- **Dynamically throttles to 3A at 44°C+, restores 6A at 40°C**
- Ensures PPS stays enabled during active charging
- **KSUI WebUI API**: Updates `/data/adb/modules/fastcharge-eqe/webui/charge_data.json` every 2 seconds
- Logs charging metrics (voltage, current, temp) to `/data/adb/modules/fastcharge-eqe/charge.log`

### KSUI WebUI (webui/index.html)
- Real-time metrics: Voltage (V), Current (A), Power (W), Temperature (°C)
- Live charging graph (last 20 minutes) with Chart.js
- Battery info: level, health, technology, capacity, limits
- Charger details: type, negotiated voltage/current, active profile
- Thermal progress bar with 40°C/44°C markers
- Charging log with color-coded entries (throttle, resume, PPS, info)
- Responsive design, works on mobile and desktop

## Verification

After installation and reboot:

1. Check log: `cat /data/adb/modules/fastcharge-eqe/charge.log`
2. Verify PPS: `cat /sys/class/power_supply/usb/pps_enabled` (should be `1`)
3. Check current limit: `cat /sys/class/power_supply/usb/input_current_limit` (should be `6000000`)
4. Check WebUI data: `cat /data/adb/modules/fastcharge-eqe/webui/charge_data.json`
5. Open KSUI app → Modules → FastCharge EQE → View WebUI
6. Check thermal behavior: charge.log will show "THERMAL THROTTLE" / "THERMAL RESUME" messages

## Compatibility Notes

| ROM Type | Support |
|----------|---------|
| **Stock Motorola ROM** | Fully supported |
| **LineageOS / AOSP-based** | Fully supported (custom ROM nodes enabled) |
| **PixelOS / crDroid / Evolution X** | Fully supported |
| **GSI / Other** | May need sysfs path adjustments |

- **Non-Motorola chargers**: Works with any PD 3.0 PPS charger (65W+ for 68W, 100W+ for 125W)
- **Safety**: Module raises thermal thresholds but does NOT disable hardware safety cutoffs (PMIC/charger IC protection remains active)

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Module not loading | Check Magisk version ≥ 26.0, reinstall |
| No PPS negotiation | Verify charger supports PPS, check cable (must be USB-C 3.0+ rated, 5A capable) |
| Charging still slow | Check `charge.log` for errors, verify sysfs nodes exist on your ROM |
| Overheating | Module throttles at 44°C automatically; use lower wattage charger if persistent |
| WebUI not showing | Ensure KSUI is installed and updated; reboot after module install |
| Bootloop | Disable module via Magisk recovery mode (hold Vol+ during boot) |

## Uninstall

1. Magisk app → Modules → FastCharge EQE → Remove
2. Reboot

## Technical Details

### Sysfs Nodes Modified
```
/sys/class/power_supply/usb/pps_enabled
/sys/class/power_supply/usb/pps_max_voltage (20V)
/sys/class/power_supply/usb/pps_min_voltage (3.3V)
/sys/class/power_supply/usb/pps_max_current (6.25A / 3.4A)
/sys/class/power_supply/usb/input_current_limit (6A / 3A throttled)
/sys/class/power_supply/usb/voltage_max (20V)
/sys/class/power_supply/battery/charge_current_max
/sys/class/power_supply/battery/input_current_max
/sys/class/power_supply/battery/charge_temp_limit (44°C)
/sys/class/power_supply/battery/cool_down_temp (40°C)
/sys/class/typec/port*/drp
/sys/class/typec/port*/pd_revision (3.0)
/sys/class/typec/port*/pps_supported
/thermal/thermal_zone*/trip_point_*_temp (battery/charger zones)
```

### Persistent Properties Set
```
persist.vendor.fastcharge.enable=1
persist.vendor.pps.enable=1
persist.vendor.usb.pd.pps=1
persist.vendor.charge.max_current=6000
persist.vendor.charge.max_voltage=20000
persist.vendor.qc.mode=5
persist.vendor.thermal.throttle_temp=44
persist.vendor.thermal.resume_temp=40
persist.vendor.charge.profile_125w=1
persist.vendor.charge.profile_68w=1
```

### WebUI Data File
```
/data/adb/modules/fastcharge-eqe/webui/charge_data.json (updated every 2s)
```

## Changelog

### v1.1 (Current)
- Added **68W USB-PD 3.0 PPS** support (20V/3.4A)
- Added **thermal tuning: throttle at 44°C, resume at 40°C**
- Added **custom ROM compatibility** (extra sysfs nodes)
- Runtime thermal management in service.sh (10s monitoring)
- **KSUI WebUI** with real-time graphs and monitoring
- Maintainer: **AK-47**
- Enhanced logging (voltage, current, temperature)

### v1.0
- Initial release with 125W TurboPower support
- Basic PPS enable and throttle removal

## Disclaimer

**Use at your own risk.** This module modifies charging parameters beyond stock limits. While hardware safety mechanisms (battery PMIC, charger IC) remain active, sustained high-wattage charging may reduce long-term battery health. The 44°C thermal throttle helps mitigate this. Monitor battery temperature and avoid charging in hot environments.

## Credits

- Motorola Edge 50 Pro community
- Magisk @topjohnwu
- KernelSU / KSUI team
- USB-PD/PPS specification contributors
- Chart.js for graphing
- **Maintainer: AK-47**

## License

MIT License - Feel free to modify and distribute.