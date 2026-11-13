#!/usr/bin/env bash
set -uo pipefail

action="${1:-status}"
address="${2:-}"
scan_timeout="${3:-5}"
smart_fallback="${4:-1}"

if [[ ! "$scan_timeout" =~ ^[0-9]+$ ]] || (( scan_timeout < 2 )); then
  scan_timeout=5
elif (( scan_timeout > 30 )); then
  scan_timeout=30
fi

is_valid_mac() {
  [[ "${1:-}" =~ ^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$ ]]
}

power_on() {
  if [[ "$(timeout 2s bluetoothctl show 2>/dev/null || true)" == *"Powered: yes"* ]]; then
    return 0
  fi
  echo "STEP:powering_on"
  if command -v omarchy-bluetooth-power >/dev/null 2>&1; then
    omarchy-bluetooth-power on >/dev/null 2>&1 || true
  fi
  timeout 3s bluetoothctl power on >/dev/null 2>&1 || true
}

cycle_adapter_power() {
  echo "STEP:cycling_power"
  if command -v omarchy-bluetooth-power >/dev/null 2>&1; then
    omarchy-bluetooth-power off >/dev/null 2>&1 || true
    sleep 1
    omarchy-bluetooth-power on >/dev/null 2>&1 || true
  else
    timeout 3s bluetoothctl power off >/dev/null 2>&1 || true
    sleep 1
    timeout 3s bluetoothctl power on >/dev/null 2>&1 || true
  fi
  sleep 1
}

is_connected_with_audio() {
  local info
  info="$(timeout 3s bluetoothctl info "$address" 2>/dev/null || true)"
  [[ "$info" == *"Connected: yes"* ]] && [[ \
    "$info" == *"0000110b-0000-1000-8000-00805f9b34fb"* || \
    "$info" == *"0000110d-0000-1000-8000-00805f9b34fb"* || \
    "$info" == *"0000111e-0000-1000-8000-00805f9b34fb"* || \
    "$info" == *"00001108-0000-1000-8000-00805f9b34fb"* \
  ]]
}

has_audio_uuid() {
  local info
  info="$(timeout 3s bluetoothctl info "$address" 2>/dev/null || true)"
  [[ \
    "$info" == *"0000110b-0000-1000-8000-00805f9b34fb"* || \
    "$info" == *"0000110d-0000-1000-8000-00805f9b34fb"* || \
    "$info" == *"0000111e-0000-1000-8000-00805f9b34fb"* || \
    "$info" == *"00001108-0000-1000-8000-00805f9b34fb"* \
  ]]
}

is_connected_any() {
  local info
  info="$(timeout 3s bluetoothctl info "$address" 2>/dev/null || true)"
  [[ "$info" == *"Connected: yes"* ]]
}

device_known() {
  local info
  info="$(timeout 2s bluetoothctl info "$address" 2>/dev/null || true)"
  [[ "$info" == *"Device $address"* ]]
}

do_bredr_scan() {
  echo "STEP:scanning_bredr"
  timeout "$((scan_timeout + 3))s" bluetoothctl --timeout "$scan_timeout" scan bredr >/dev/null 2>&1 \
    || timeout "$((scan_timeout + 3))s" bluetoothctl --timeout "$scan_timeout" scan on >/dev/null 2>&1 \
    || true
}

do_bredr_repair() {
  # If the device is cached without any Classic Audio UUID (trapped in BLE cache),
  # remove the stale BLE entry first so BlueZ performs fresh BR/EDR SDP discovery.
  if device_known && ! has_audio_uuid; then
    echo "STEP:removing"
    timeout 5s bluetoothctl disconnect "$address" >/dev/null 2>&1 || true
    timeout 6s bluetoothctl remove "$address" >/dev/null 2>&1 || true
  fi

  do_bredr_scan

  if ! device_known; then
    echo "STEP:scanning"
    timeout "$((scan_timeout + 3))s" bluetoothctl --timeout "$scan_timeout" scan on >/dev/null 2>&1 || true
  fi

  echo "STEP:pairing"
  timeout 15s bluetoothctl pair "$address" >/dev/null 2>&1 || true

  echo "STEP:trusting"
  timeout 5s bluetoothctl trust "$address" >/dev/null 2>&1 || true

  echo "STEP:connecting"
  timeout 15s bluetoothctl connect "$address" >/dev/null 2>&1 || true

  if is_connected_with_audio; then
    echo "RESULT:ok:connected"
    return 0
  elif is_connected_any; then
    echo "RESULT:ok:connected_ble"
    return 0
  else
    echo "RESULT:fail:connect_failed"
    return 1
  fi
}

case "$action" in
  status)
    count=0
    while read -r _ dev_mac _; do
      if is_valid_mac "$dev_mac"; then
        echo "===DEVICE==="
        timeout 2s bluetoothctl info "$dev_mac" 2>/dev/null || true
        count=$((count + 1))
        if (( count >= 24 )); then
          break
        fi
      fi
    done < <(timeout 3s bluetoothctl devices 2>/dev/null || true)
    ;;

  scan_bredr)
    power_on
    do_bredr_scan
    echo "RESULT:ok:scan_complete"
    exit 0
    ;;

  connect)
    if ! is_valid_mac "$address"; then
      echo "RESULT:fail:invalid_mac"
      exit 1
    fi
    power_on
    echo "STEP:connecting"
    timeout 5s bluetoothctl trust "$address" >/dev/null 2>&1 || true
    timeout 12s bluetoothctl connect "$address" >/dev/null 2>&1 || true

    if is_connected_with_audio; then
      echo "RESULT:ok:connected"
      exit 0
    fi

    if [[ "$smart_fallback" == "1" ]]; then
      echo "STEP:fallback_repair"
      if is_connected_any; then
        timeout 5s bluetoothctl disconnect "$address" >/dev/null 2>&1 || true
      fi
      do_bredr_repair
      exit $?
    fi

    if is_connected_any; then
      echo "RESULT:ok:connected_ble"
      exit 0
    fi

    echo "RESULT:fail:connect_failed"
    exit 1
    ;;

  disconnect)
    if ! is_valid_mac "$address"; then
      echo "RESULT:fail:invalid_mac"
      exit 1
    fi
    echo "STEP:disconnecting"
    if timeout 8s bluetoothctl disconnect "$address" >/dev/null 2>&1; then
      echo "RESULT:ok:disconnected"
      exit 0
    fi
    echo "RESULT:fail:disconnect_failed"
    exit 1
    ;;

  repair)
    if ! is_valid_mac "$address"; then
      echo "RESULT:fail:invalid_mac"
      exit 1
    fi
    power_on
    do_bredr_repair
    exit $?
    ;;

  reset)
    # Layer 1: User-space rfkill/power cycle (no root needed)
    cycle_adapter_power

    # Layer 2: Kernel module btusb reload (via passwordless sudo or Polkit pkexec)
    echo "STEP:reloading_btusb"
    if sudo -n true 2>/dev/null; then
      sudo -n sh -c 'modprobe -r btusb && modprobe btusb' >/dev/null 2>&1 || {
        echo "RESULT:fail:btusb_reload_failed"
        exit 1
      }
    else
      pkexec sh -c 'modprobe -r btusb && modprobe btusb' >/dev/null 2>&1 || {
        echo "RESULT:fail:auth_failed"
        exit 1
      }
    fi

    echo "STEP:waiting_adapter"
    sleep 2
    power_on

    if is_valid_mac "$address"; then
      echo "STEP:removing"
      timeout 8s bluetoothctl remove "$address" >/dev/null 2>&1 || true
      do_bredr_repair
      exit $?
    else
      do_bredr_scan
      echo "RESULT:ok:reset_complete"
      exit 0
    fi
    ;;

  *)
    echo "RESULT:fail:invalid_mac"
    exit 1
    ;;
esac
