const assert = require("assert")
const fs = require("fs")
const path = require("path")
const { execFileSync } = require("child_process")
const Model = require("../Model.js")

const rootDir = path.join(__dirname, "..")
const manifest = JSON.parse(fs.readFileSync(path.join(rootDir, "manifest.json"), "utf8"))
const panelQml = fs.readFileSync(path.join(rootDir, "Panel.qml"), "utf8")
const ctlScript = fs.readFileSync(path.join(rootDir, "scripts", "bt-audio-ctl.sh"), "utf8")
const readme = fs.readFileSync(path.join(rootDir, "README.md"), "utf8")

// 1. Manifest schema & defaults <-> schema parity
{
  assert.strictEqual(manifest.schemaVersion, 1)
  assert.strictEqual(manifest.id, "mrclaro.bt-audio-fixer")
  const defaults = manifest.barWidget.defaults || {}
  const schema = manifest.barWidget.schema || []
  const schemaByKey = {}
  for (const entry of schema) {
    assert(entry.key, "Every schema item must have a key")
    schemaByKey[entry.key] = entry
    assert(
      Object.prototype.hasOwnProperty.call(defaults, entry.key),
      `Schema key '${entry.key}' missing from barWidget.defaults`
    )
    assert.deepStrictEqual(
      defaults[entry.key],
      entry.defaultValue,
      `Default mismatch for '${entry.key}' between defaults and schema`
    )
  }
  for (const key of Object.keys(defaults)) {
    assert(schemaByKey[key], `Default key '${key}' missing from barWidget.schema`)
    assert(readme.includes("`" + key + "`"), `Setting '${key}' must be documented in README.md`)
  }
}

// 2. Panel.qml setting() calls match manifest defaults
{
  const defaults = manifest.barWidget.defaults
  const settingRegex = /\bsetting\(\s*"([^"]+)"\s*,\s*([^)]+)\)/g
  let match
  const seenSettings = new Set()
  while ((match = settingRegex.exec(panelQml)) !== null) {
    const key = match[1]
    const rawFallback = match[2].trim()
    seenSettings.add(key)
    assert(
      Object.prototype.hasOwnProperty.call(defaults, key),
      `Panel.qml reads unknown setting '${key}'`
    )
    const parsedFallback = JSON.parse(rawFallback)
    assert.deepStrictEqual(
      parsedFallback,
      defaults[key],
      `Panel.qml fallback for '${key}' (${rawFallback}) disagrees with manifest default (${defaults[key]})`
    )
  }
  for (const key of Object.keys(defaults)) {
    assert(seenSettings.has(key), `Manifest setting '${key}' is never read in Panel.qml`)
  }
}

// 3. Model functions called in Panel.qml exist on Model.js
{
  const modelCallRegex = /\bModel\.([A-Za-z0-9_]+)\s*\(/g
  let match
  while ((match = modelCallRegex.exec(panelQml)) !== null) {
    const fnName = match[1]
    assert.strictEqual(
      typeof Model[fnName],
      "function",
      `Panel.qml calls Model.${fnName}(), which is not exported by Model.js`
    )
  }
}

// 4. STEP and RESULT tokens in bt-audio-ctl.sh match Model.js and all i18n catalogs
{
  const locales = ["en", "pt-BR", "pt"]
  const catalogs = {}
  for (const loc of locales) {
    catalogs[loc] = JSON.parse(
      fs.readFileSync(path.join(rootDir, "i18n", `${loc}.json`), "utf8")
    )
  }

  const enKeys = Object.keys(catalogs["en"]).sort()
  for (const loc of locales) {
    assert.deepStrictEqual(
      Object.keys(catalogs[loc]).sort(),
      enKeys,
      `i18n/${loc}.json keys do not match i18n/en.json`
    )
  }

  const stepRegex = /STEP:([a-z0-9_]+)/g
  let match
  while ((match = stepRegex.exec(ctlScript)) !== null) {
    const step = match[1]
    assert(Model.KNOWN_STEPS[step], `bt-audio-ctl.sh emits unknown STEP:${step}`)
    assert(catalogs.en[`panel.step.${step}`], `Missing i18n key panel.step.${step}`)
  }

  const resultRegex = /RESULT:(?:ok|fail):([a-z0-9_]+)/g
  while ((match = resultRegex.exec(ctlScript)) !== null) {
    const res = match[1]
    assert(Model.KNOWN_RESULTS[res], `bt-audio-ctl.sh emits unknown RESULT:${res}`)
    assert(catalogs.en[`panel.result.${res}`], `Missing i18n key panel.result.${res}`)
  }

  // Static strings.t("...") and strings.tn("...") in Panel.qml exist in catalogs
  const tRegex = /\bstrings\.t(?:n)?\(\s*"([^"]+)"/g
  while ((match = tRegex.exec(panelQml)) !== null) {
    const key = match[1]
    if (key.endsWith(".")) continue // dynamic prefix like "panel.step."
    assert(
      Object.prototype.hasOwnProperty.call(catalogs.en, key),
      `Panel.qml references missing i18n key '${key}'`
    )
  }
}

// 5. README IPC commands match ShellIpc functions in Panel.qml
{
  const ipcBlockMatch = /ShellIpc\s*\{([\s\S]*?)\n  \}/.exec(panelQml)
  assert(ipcBlockMatch, "Panel.qml must declare a ShellIpc block")
  const ipcFns = new Set()
  const fnRegex = /function\s+([a-zA-Z0-9_]+)\s*\(/g
  let m
  while ((m = fnRegex.exec(ipcBlockMatch[1])) !== null) {
    ipcFns.add(m[1])
  }

  const readmeIpcRegex = /omarchy-shell\s+mrclaro\.bt-audio-fixer\s+([a-zA-Z0-9_]+)/g
  let documentedCount = 0
  while ((m = readmeIpcRegex.exec(readme)) !== null) {
    documentedCount += 1
    const verb = m[1]
    assert(ipcFns.has(verb), `README documents IPC verb '${verb}' not found in ShellIpc`)
  }
  assert(documentedCount > 0, "README must document omarchy-shell IPC verbs")
}

// 6. Shell script syntax check
{
  execFileSync("bash", ["-n", path.join(rootDir, "scripts", "bt-audio-ctl.sh")])
}

console.log("All mrclaro.bt-audio-fixer wiring & contract tests passed.")
