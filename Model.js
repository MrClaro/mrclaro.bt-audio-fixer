var MAX_TEXT_LEN = 120
var MAX_INFO_BYTES = 65536
var MAX_INFO_LINES = 200
var MAX_DEVICES = 24
var MAX_UUIDS = 64
var MIN_SCAN_TIMEOUT = 2
var MAX_SCAN_TIMEOUT = 30
var AUTO_HEAL_COOLDOWN_MS = 60000

var AUDIO_UUIDS = {
  "0000110b-0000-1000-8000-00805f9b34fb": true, // Audio Sink
  "0000110d-0000-1000-8000-00805f9b34fb": true, // Advanced Audio Distribution (A2DP)
  "0000111e-0000-1000-8000-00805f9b34fb": true, // Handsfree (HFP)
  "00001108-0000-1000-8000-00805f9b34fb": true  // Headset (HSP)
}

var HID_UUIDS = {
  "00001124-0000-1000-8000-00805f9b34fb": true, // Classic HID
  "00001812-0000-1000-8000-00805f9b34fb": true  // BLE HOGP (Mouse/Keyboard)
}

var KNOWN_STEPS = {
  "powering_on": true,
  "cycling_power": true,
  "reloading_btusb": true,
  "waiting_adapter": true,
  "removing": true,
  "scanning_bredr": true,
  "scanning": true,
  "pairing": true,
  "trusting": true,
  "connecting": true,
  "disconnecting": true,
  "fallback_repair": true
}

var KNOWN_RESULTS = {
  "connected": true,
  "connected_ble": true,
  "disconnected": true,
  "scan_complete": true,
  "reset_complete": true,
  "connect_failed": true,
  "disconnect_failed": true,
  "auth_failed": true,
  "btusb_reload_failed": true,
  "invalid_mac": true
}

// Neutralizes markup-shaped input before it can reach any shared QML Text or
// tooltip sink that might default to Text.AutoText, and bounds length.
function plainText(value, maxLen) {
  if (value === undefined || value === null) return ""
  var limit = (typeof maxLen === "number" && isFinite(maxLen) && maxLen > 0)
    ? Math.floor(maxLen)
    : MAX_TEXT_LEN
  var str = typeof value === "string" ? value : String(value)
  var cleaned = str
    .replace(/[<>]/g, "")
    .replace(/[\u0000-\u001F\u007F]/g, " ")
    .replace(/\s+/g, " ")
    .trim()
  return cleaned.length > limit ? cleaned.slice(0, limit) : cleaned
}

function isValidMac(value) {
  var text = String(value === undefined || value === null ? "" : value).trim()
  return /^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$/.test(text)
}

function normalizeMac(value, fallback) {
  var candidate = String(value === undefined || value === null ? "" : value).trim()
  if (isValidMac(candidate)) return candidate.toUpperCase()
  var fb = String(fallback === undefined || fallback === null ? "" : fallback).trim()
  return isValidMac(fb) ? fb.toUpperCase() : ""
}

function normalizedAddressHex(value) {
  return String(value || "").trim().toLowerCase().replace(/[^0-9a-f]/g, "")
}

function clampScanTimeout(value, fallback) {
  var num = Number(value)
  if (!isFinite(num)) {
    num = Number(fallback)
    if (!isFinite(num)) num = 5
  }
  var rounded = Math.round(num)
  if (rounded < MIN_SCAN_TIMEOUT) return MIN_SCAN_TIMEOUT
  if (rounded > MAX_SCAN_TIMEOUT) return MAX_SCAN_TIMEOUT
  return rounded
}

function parseBluetoothInfo(raw, fallbackAddress, fallbackName) {
  var state = {
    address: normalizeMac(fallbackAddress, ""),
    name: plainText(fallbackName || "", MAX_TEXT_LEN),
    known: false,
    connected: false,
    paired: false,
    bonded: false,
    trusted: false,
    hasAudioSink: false,
    isInputPeripheral: false,
    isAudioDevice: false,
    bleOnly: false,
    battery: -1,
    uuidCount: 0,
    addressType: "",
    iconType: ""
  }
  if (raw === undefined || raw === null) return state

  var text = String(raw)
  if (text.length > MAX_INFO_BYTES) text = text.slice(0, MAX_INFO_BYTES)
  if (text.indexOf("not available") !== -1 && text.indexOf("Device ") === -1) {
    return state
  }

  var lines = text.split(/\r?\n/)
  var maxLines = Math.min(lines.length, MAX_INFO_LINES)
  var aliasName = ""
  var deviceName = ""
  var uuidCount = 0

  for (var i = 0; i < maxLines; i++) {
    var line = lines[i].trim()
    if (!line) continue

    var headerMatch = /^Device\s+([0-9A-Fa-f:]{17})(?:\s+\(([^)]+)\))?/.exec(line)
    if (headerMatch) {
      state.known = true
      state.address = normalizeMac(headerMatch[1], state.address)
      state.addressType = plainText(headerMatch[2] || "", 24).toLowerCase()
      continue
    }

    if (line.indexOf("Alias:") === 0) {
      aliasName = plainText(line.slice(6), MAX_TEXT_LEN)
    } else if (line.indexOf("Name:") === 0) {
      deviceName = plainText(line.slice(5), MAX_TEXT_LEN)
    } else if (line.indexOf("Icon:") === 0) {
      state.iconType = plainText(line.slice(5), 48).toLowerCase()
    } else if (line.indexOf("Connected:") === 0) {
      state.connected = line.slice(10).trim().toLowerCase() === "yes"
    } else if (line.indexOf("Paired:") === 0) {
      state.paired = line.slice(7).trim().toLowerCase() === "yes"
    } else if (line.indexOf("Bonded:") === 0) {
      state.bonded = line.slice(7).trim().toLowerCase() === "yes"
    } else if (line.indexOf("Trusted:") === 0) {
      state.trusted = line.slice(8).trim().toLowerCase() === "yes"
    } else if (line.indexOf("UUID:") === 0) {
      if (uuidCount < MAX_UUIDS) {
        uuidCount += 1
        var uuidMatch = /\(([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})\)/.exec(line)
        if (uuidMatch) {
          var uuid = uuidMatch[1].toLowerCase()
          if (Object.prototype.hasOwnProperty.call(AUDIO_UUIDS, uuid)) {
            state.hasAudioSink = true
          }
          if (Object.prototype.hasOwnProperty.call(HID_UUIDS, uuid)) {
            state.isInputPeripheral = true
          }
        }
      }
    } else if (line.indexOf("Battery Percentage:") === 0) {
      var batMatch = /\((\d{1,3})\)/.exec(line)
      if (batMatch) {
        var pct = Number(batMatch[1])
        if (isFinite(pct) && pct >= 0 && pct <= 100) {
          state.battery = Math.round(pct)
        }
      }
    }
  }

  state.uuidCount = uuidCount
  if (
    state.iconType.indexOf("input-mouse") === 0 ||
    state.iconType.indexOf("input-keyboard") === 0 ||
    state.iconType.indexOf("input-tablet") === 0
  ) {
    state.isInputPeripheral = true
  }

  var resolvedName = aliasName || deviceName
  if (resolvedName && !isValidMac(resolvedName.replace(/-/g, ":"))) {
    state.name = resolvedName
  } else if (!state.name) {
    state.name = state.address
  }

  // A dual-mode audio device stuck on BLE has GATT UUIDs or random LE address
  // (or is connected) without any Classic Audio UUID, and is not an HID peripheral.
  state.bleOnly = state.known &&
    !state.isInputPeripheral &&
    !state.hasAudioSink &&
    (uuidCount > 0 || state.addressType === "random" || state.connected)

  state.isAudioDevice = state.hasAudioSink ||
    state.iconType.indexOf("audio") === 0 ||
    state.bleOnly

  return state
}

function devicePriority(d) {
  if (!d) return 99
  if (d.bleOnly && d.connected) return 0
  if (d.bleOnly) return 1
  if (d.connected && d.hasAudioSink) return 2
  if (d.hasAudioSink && (d.paired || d.bonded || d.trusted)) return 3
  if (d.isAudioDevice && (d.paired || d.bonded || d.trusted)) return 4
  if (d.isAudioDevice) return 5
  if (d.connected) return 6
  if (d.paired || d.bonded || d.trusted) return 7
  return 8
}

function parseDeviceCatalog(raw) {
  if (raw === undefined || raw === null) return []
  var text = String(raw)
  if (text.length > MAX_INFO_BYTES) text = text.slice(0, MAX_INFO_BYTES)

  var blocks = text.split("===DEVICE===")
  var seen = ({})
  var devices = []

  for (var i = 0; i < blocks.length && devices.length < MAX_DEVICES; i++) {
    var block = blocks[i].trim()
    if (!block) continue
    var parsed = parseBluetoothInfo(block, "", "")
    if (!parsed.known || !isValidMac(parsed.address)) continue
    if (seen[parsed.address]) continue
    if (parsed.name === parsed.address && !parsed.paired && !parsed.connected) continue
    seen[parsed.address] = true
    devices.push(parsed)
  }

  devices.sort(function(a, b) {
    var pa = devicePriority(a)
    var pb = devicePriority(b)
    if (pa !== pb) return pa - pb
    return String(a.name || "").localeCompare(String(b.name || ""))
  })

  return devices
}

function pickTargetDevice(devices, selectedAddress, preferredAddress) {
  var list = Array.isArray(devices) ? devices : []
  if (list.length === 0) return null

  var sel = normalizeMac(selectedAddress, "")
  if (sel) {
    for (var i = 0; i < list.length; i++) {
      if (list[i] && list[i].address === sel) return list[i]
    }
  }

  var pref = normalizeMac(preferredAddress, "")
  if (pref) {
    for (var j = 0; j < list.length; j++) {
      if (list[j] && list[j].address === pref) return list[j]
    }
  }

  return list[0]
}

function hasAnyBleOnly(devices) {
  var list = Array.isArray(devices) ? devices : []
  for (var i = 0; i < list.length; i++) {
    if (list[i] && list[i].bleOnly) return true
  }
  return false
}

function findConnectedBleOnlyDevice(devices, cooldownMap, nowMs) {
  var list = Array.isArray(devices) ? devices : []
  var cooldowns = cooldownMap || ({})
  var now = typeof nowMs === "number" && isFinite(nowMs) ? nowMs : Date.now()

  for (var i = 0; i < list.length; i++) {
    var d = list[i]
    if (!d || !d.connected || !d.bleOnly || !isValidMac(d.address)) continue
    var lastAttempt = Number(cooldowns[d.address] || 0)
    if (!isFinite(lastAttempt) || now - lastAttempt >= AUTO_HEAL_COOLDOWN_MS) {
      return d
    }
  }
  return null
}

function parseCtlLine(line) {
  var clean = plainText(line, 160)
  if (!clean) return null

  if (clean.indexOf("STEP:") === 0) {
    var step = clean.slice(5).trim()
    if (Object.prototype.hasOwnProperty.call(KNOWN_STEPS, step)) {
      return { kind: "step", step: step }
    }
    return null
  }

  if (clean.indexOf("RESULT:") === 0) {
    var rest = clean.slice(7).trim()
    var parts = rest.split(":")
    var status = parts[0] === "ok" ? "ok" : "fail"
    var reason = plainText(parts.slice(1).join(":") || (status === "ok" ? "connected" : "connect_failed"), 64)
    if (!Object.prototype.hasOwnProperty.call(KNOWN_RESULTS, reason)) {
      reason = status === "ok" ? "connected" : "connect_failed"
    }
    return { kind: "result", ok: status === "ok", reason: reason }
  }

  return null
}

function nodeProps(node) {
  return node && node.ready && node.properties ? node.properties : {}
}

function nodeText(node) {
  var props = nodeProps(node)
  return [
    node ? node.name : "",
    node ? node.description : "",
    node ? node.nickname : "",
    node ? node.nick : "",
    props["node.name"],
    props["node.description"],
    props["node.nick"],
    props["device.name"],
    props["device.description"],
    props["device.product.name"],
    props["device.alias"],
    props["device.string"],
    props["api.bluez5.address"],
    props["bluez5.address"],
    props["media.name"]
  ].join(" ").toLowerCase()
}

function bluetoothSinkMatchesDevice(node, address, deviceName) {
  if (!node || !node.isSink || node.isStream) return false
  var addrHex = normalizedAddressHex(address)
  var text = nodeText(node)
  if (addrHex !== "" && normalizedAddressHex(text).indexOf(addrHex) !== -1) return true
  var label = plainText(deviceName, MAX_TEXT_LEN).toLowerCase()
  return label !== "" && text.indexOf(label) !== -1
}

function barIcon(connected, busy, bleOnly) {
  if (busy) return "󰂰"
  if (bleOnly) return "󰂲"
  if (connected) return "󰋋"
  return "󰋐"
}

function buildBarTooltip(deviceName, statusText, batteryText) {
  var safeName = plainText(deviceName || "Bluetooth Audio", MAX_TEXT_LEN)
  var safeStatus = plainText(statusText || "", MAX_TEXT_LEN)
  var safeBat = plainText(batteryText || "", 32)
  var result = safeName
  if (safeStatus) result += " — " + safeStatus
  if (safeBat) result += " (" + safeBat + ")"
  return plainText(result, 200)
}

if (typeof module !== "undefined") {
  module.exports = {
    MAX_TEXT_LEN: MAX_TEXT_LEN,
    MAX_INFO_BYTES: MAX_INFO_BYTES,
    MAX_INFO_LINES: MAX_INFO_LINES,
    MAX_DEVICES: MAX_DEVICES,
    MAX_UUIDS: MAX_UUIDS,
    MIN_SCAN_TIMEOUT: MIN_SCAN_TIMEOUT,
    MAX_SCAN_TIMEOUT: MAX_SCAN_TIMEOUT,
    AUTO_HEAL_COOLDOWN_MS: AUTO_HEAL_COOLDOWN_MS,
    KNOWN_STEPS: KNOWN_STEPS,
    KNOWN_RESULTS: KNOWN_RESULTS,
    plainText: plainText,
    isValidMac: isValidMac,
    normalizeMac: normalizeMac,
    normalizedAddressHex: normalizedAddressHex,
    clampScanTimeout: clampScanTimeout,
    parseBluetoothInfo: parseBluetoothInfo,
    parseDeviceCatalog: parseDeviceCatalog,
    pickTargetDevice: pickTargetDevice,
    hasAnyBleOnly: hasAnyBleOnly,
    findConnectedBleOnlyDevice: findConnectedBleOnlyDevice,
    parseCtlLine: parseCtlLine,
    bluetoothSinkMatchesDevice: bluetoothSinkMatchesDevice,
    barIcon: barIcon,
    buildBarTooltip: buildBarTooltip
  }
}
