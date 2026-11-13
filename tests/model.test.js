const assert = require("assert")
const fs = require("fs")
const path = require("path")
const Model = require("../Model.js")

// 1. Markup neutralization for shared tooltips, PanelHero, and dynamic text sinks
{
  const malicious = 'Sony WH-1000XM5 <img src="https://example.invalid/tracker"><b>Audio</b><script>alert(1)</script>'
  const cleaned = Model.plainText(malicious)
  assert(!cleaned.includes("<"), "plainText must strip <")
  assert(!cleaned.includes(">"), "plainText must strip >")
  assert(cleaned.includes("Sony WH-1000XM5"), "plainText preserves device text")

  const tooltip = Model.buildBarTooltip(
    'Headset <img src="https://example.invalid/tracker">',
    '<b>Connected</b>',
    '<font color="red">85%</font>'
  )
  assert(!tooltip.includes("<") && !tooltip.includes(">"), "buildBarTooltip must neutralize markup in all arguments")
  assert(tooltip.includes("Headset") && tooltip.includes("Connected") && tooltip.includes("85%"))
}

// 2. Bounds on string length, timeouts, and bluetoothctl info output
{
  const huge = "A".repeat(5000)
  assert.strictEqual(Model.plainText(huge, 120).length, 120)
  assert.strictEqual(Model.clampScanTimeout(-10, 5), Model.MIN_SCAN_TIMEOUT)
  assert.strictEqual(Model.clampScanTimeout(999, 5), Model.MAX_SCAN_TIMEOUT)
  assert.strictEqual(Model.clampScanTimeout("invalid", 5), 5)
}

// 3. MAC validation and shell injection rejection
{
  assert.strictEqual(Model.isValidMac("AA:BB:CC:11:22:33"), true)
  assert.strictEqual(Model.isValidMac("aa:bb:cc:11:22:33"), true)
  assert.strictEqual(Model.isValidMac("AA:BB:CC:11:22:33; rm -rf /"), false)
  assert.strictEqual(Model.isValidMac("$(id)"), false)
  assert.strictEqual(Model.normalizeMac("invalid-mac", ""), "")
}

// 4. Multi-device catalog parsing, BLE-trap detection, and HID peripheral exclusion
{
  const multiCatalog = `
===DEVICE===
Device 11:22:33:44:55:66 (random)
\tName: Logitech MX Master <img src="https://example.invalid/mouse">
\tAlias: Logitech MX Master
\tIcon: input-mouse
\tPaired: yes
\tConnected: yes
\tUUID: Human Interface Device (00001812-0000-1000-8000-00805f9b34fb)
===DEVICE===
Device AA:BB:CC:DD:EE:01 (public)
\tName: Generic Headset A2DP <script>x</script>
\tAlias: Generic Headset A2DP <script>x</script>
\tIcon: audio-headset
\tPaired: yes
\tTrusted: yes
\tConnected: no
\tUUID: Audio Sink (0000110b-0000-1000-8000-00805f9b34fb)
\tBattery Percentage: 0x50 (80)
===DEVICE===
Device AA:BB:CC:DD:EE:02 (random)
\tName: DualMode Earbuds LE
\tAlias: DualMode Earbuds LE
\tPaired: yes
\tConnected: yes
\tUUID: Generic Access Profile (00001800-0000-1000-8000-00805f9b34fb)
`
  const list = Model.parseDeviceCatalog(multiCatalog)
  assert.strictEqual(list.length, 3)

  // BLE-trapped audio device is prioritized first
  assert.strictEqual(list[0].address, "AA:BB:CC:DD:EE:02")
  assert.strictEqual(list[0].bleOnly, true)
  assert.strictEqual(list[0].hasAudioSink, false)

  // Auto-heal candidate detection with cooldown
  const candidate = Model.findConnectedBleOnlyDevice(list, {}, 100000)
  assert(candidate && candidate.address === "AA:BB:CC:DD:EE:02")
  const onCooldown = Model.findConnectedBleOnlyDevice(
    list,
    { "AA:BB:CC:DD:EE:02": 100000 - 5000 },
    100000
  )
  assert.strictEqual(onCooldown, null, "Device on cooldown must not re-trigger auto-heal")

  // Paired A2DP headset is second, markup stripped
  assert.strictEqual(list[1].address, "AA:BB:CC:DD:EE:01")
  assert.strictEqual(list[1].bleOnly, false)
  assert.strictEqual(list[1].hasAudioSink, true)
  assert.strictEqual(list[1].battery, 80)
  assert(!list[1].name.includes("<") && !list[1].name.includes(">"))

  // BLE Mouse is NOT flagged as bleOnly audio trap
  const mouse = list[2]
  assert.strictEqual(mouse.address, "11:22:33:44:55:66")
  assert.strictEqual(mouse.isInputPeripheral, true)
  assert.strictEqual(mouse.bleOnly, false)
}

// 5. QML source check: every Text in Panel.qml uses PlainText
{
  const panelQml = fs.readFileSync(path.join(__dirname, "..", "Panel.qml"), "utf8")
  assert(!/\bText\s*\{/.test(panelQml), "Panel.qml must use PlainText instead of bare Text {}")
}

console.log("All mrclaro.bt-audio-fixer model tests passed.")
