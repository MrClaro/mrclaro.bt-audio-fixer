import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth
import Quickshell.Services.Pipewire
import qs.Ui
import qs.Commons
import qs.Commons as Commons
import "Model.js" as Model

Panel {
  id: root
  moduleName: "mrclaro.bt-audio-fixer"
  ipcTarget: "mrclaro.bt-audio-fixer"
  manageIpc: false

  Commons.Translations {
    id: strings
    directory: Qt.resolvedUrl("i18n")
  }

  readonly property color foreground: bar ? bar.foreground : Commons.Color.foreground
  readonly property color urgent: bar ? bar.urgent : Commons.Color.urgent
  readonly property color accent: Commons.Color.accent
  readonly property color dim: Qt.darker(foreground, 1.45)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property string scriptPath: String(Qt.resolvedUrl("scripts/bt-audio-ctl.sh")).replace(/^file:\/\//, "")
  readonly property string preferredAddress: Model.normalizeMac(setting("preferredDevice", ""), "")
  readonly property int scanTimeoutSec: Model.clampScanTimeout(setting("scanTimeoutSec", 5), 5)
  readonly property bool smartFallback: setting("smartFallback", true) !== false
  readonly property bool autoHealBle: setting("autoHealBle", true) !== false
  readonly property bool switchAudioOutput: setting("switchAudioOutput", true) !== false

  readonly property var adapter: Bluetooth.defaultAdapter
  readonly property var btDevices: Bluetooth.devices ? Bluetooth.devices.values : []
  readonly property var pipewireNodes: Pipewire.nodes ? Pipewire.nodes.values : []

  property var catalogDevices: []
  property var autoHealCooldowns: ({})
  property string selectedAddress: ""
  property bool busy: actionProcess.running
  property string busyAction: ""
  property string currentStepKey: ""
  property string lastResultKey: ""
  property bool lastResultOk: true

  property int selectedActionIndex: 0
  property bool cursorActive: false
  property int pendingAudioSwitchAttempts: 0

  readonly property var targetDevice: Model.pickTargetDevice(catalogDevices, selectedAddress, preferredAddress)
  readonly property string targetAddress: targetDevice ? targetDevice.address : preferredAddress

  readonly property var liveBluezDevice: {
    var targetHex = Model.normalizedAddressHex(root.targetAddress)
    if (!targetHex) return null
    var list = btDevices || []
    for (var i = 0; i < list.length; i++) {
      var d = list[i]
      if (d && Model.normalizedAddressHex(d.address) === targetHex) return d
    }
    return null
  }

  readonly property bool isConnected: {
    if (liveBluezDevice && liveBluezDevice.connected !== undefined) {
      return !!liveBluezDevice.connected
    }
    return targetDevice ? !!targetDevice.connected : false
  }

  readonly property bool isPaired: {
    if (liveBluezDevice && liveBluezDevice.paired !== undefined) {
      return !!liveBluezDevice.paired
    }
    return targetDevice ? !!targetDevice.paired : false
  }

  readonly property bool isBleOnly: targetDevice ? !!targetDevice.bleOnly : false
  readonly property bool anyBleOnly: Model.hasAnyBleOnly(catalogDevices)

  readonly property int batteryPercent: {
    if (liveBluezDevice && liveBluezDevice.batteryAvailable && liveBluezDevice.battery !== undefined) {
      var raw = Number(liveBluezDevice.battery)
      var pct = raw <= 1 && raw > 0 ? Math.round(raw * 100) : Math.round(raw)
      if (isFinite(pct) && pct >= 0 && pct <= 100) return pct
    }
    return targetDevice && targetDevice.battery !== undefined ? targetDevice.battery : -1
  }

  readonly property string batteryLabel: batteryPercent >= 0
    ? Model.plainText(strings.t("panel.battery").arg(Commons.I18n.formatNumber(batteryPercent)), 16)
    : ""

  readonly property string displayName: {
    if (liveBluezDevice) {
      var liveLabel = Model.plainText(liveBluezDevice.deviceName || liveBluezDevice.name || "", Model.MAX_TEXT_LEN)
      if (liveLabel && !Model.isValidMac(liveLabel.replace(/-/g, ":"))) return liveLabel
    }
    if (targetDevice && targetDevice.name) {
      return Model.plainText(targetDevice.name, Model.MAX_TEXT_LEN)
    }
    return Model.plainText(strings.t("panel.title"), Model.MAX_TEXT_LEN)
  }

  readonly property string icon: Model.barIcon(isConnected, busy, isBleOnly || anyBleOnly)

  readonly property string heroStatusText: {
    if (busy && currentStepKey !== "") {
      return Model.plainText(strings.t("panel.step." + currentStepKey), Model.MAX_TEXT_LEN)
    }
    if (lastResultKey !== "") {
      return Model.plainText(strings.t("panel.result." + lastResultKey), Model.MAX_TEXT_LEN)
    }
    if (adapter && !adapter.enabled) {
      return Model.plainText(strings.t("panel.status.adapterOff"), Model.MAX_TEXT_LEN)
    }
    if (!targetDevice) {
      return Model.plainText(strings.t("panel.status.noDevices"), Model.MAX_TEXT_LEN)
    }
    if (isBleOnly) {
      return Model.plainText(strings.t("panel.status.bleOnly"), Model.MAX_TEXT_LEN)
    }
    if (isConnected) {
      return Model.plainText(strings.t("panel.status.connected"), Model.MAX_TEXT_LEN)
    }
    if (isPaired) {
      return Model.plainText(strings.t("panel.status.paired"), Model.MAX_TEXT_LEN)
    }
    return Model.plainText(strings.t("panel.status.disconnected"), Model.MAX_TEXT_LEN)
  }

  readonly property string barTooltipText: Model.buildBarTooltip(displayName, heroStatusText, batteryLabel)

  readonly property var actionItems: [
    {
      id: root.isConnected && !root.isBleOnly ? "disconnect" : "connect",
      icon: root.isConnected && !root.isBleOnly ? "󰂲" : "󰋋",
      title: root.isConnected && !root.isBleOnly
        ? strings.t("panel.action.disconnect.title")
        : strings.t("panel.action.connect.title"),
      subtitle: root.isConnected && !root.isBleOnly
        ? strings.t("panel.action.disconnect.subtitle").arg(root.displayName)
        : (root.smartFallback
          ? strings.t("panel.action.connect.subtitle")
          : strings.t("panel.action.connect.directSubtitle").arg(root.displayName)),
      badge: root.isConnected && !root.isBleOnly
        ? strings.t("panel.action.disconnect.badge")
        : strings.t("panel.action.connect.badge"),
      requiresDevice: true,
      urgent: false
    },
    {
      id: "repair",
      icon: "󰂰",
      title: strings.t("panel.action.repair.title"),
      subtitle: strings.t("panel.action.repair.subtitle").arg(Commons.I18n.formatNumber(root.scanTimeoutSec)),
      badge: strings.t("panel.action.repair.badge"),
      requiresDevice: true,
      urgent: false
    },
    {
      id: "scan_bredr",
      icon: "󰐾",
      title: strings.t("panel.action.scan.title"),
      subtitle: strings.t("panel.action.scan.subtitle").arg(Commons.I18n.formatNumber(root.scanTimeoutSec)),
      badge: strings.t("panel.action.scan.badge"),
      requiresDevice: false,
      urgent: false
    },
    {
      id: "reset",
      icon: "󰑓",
      title: strings.t("panel.action.reset.title"),
      subtitle: strings.t("panel.action.reset.subtitle").arg(Commons.I18n.formatNumber(root.scanTimeoutSec)),
      badge: strings.t("panel.action.reset.badge"),
      requiresDevice: false,
      urgent: true
    }
  ]

  function refreshStatus() {
    if (statusProcess.running) return
    statusProcess.command = [
      "bash",
      root.scriptPath,
      "status"
    ]
    statusProcess.running = true
  }

  function runAction(actionName, explicitAddress) {
    if (actionProcess.running) return
    var addr = Model.normalizeMac(explicitAddress || root.targetAddress, "")
    if ((actionName === "connect" || actionName === "disconnect" || actionName === "repair") && !Model.isValidMac(addr)) {
      lastResultOk = false
      lastResultKey = "invalid_mac"
      resultClearTimer.restart()
      return
    }

    lastResultKey = ""
    lastResultOk = true
    busyAction = actionName
    currentStepKey = actionName === "disconnect"
      ? "disconnecting"
      : (actionName === "scan_bredr" ? "scanning_bredr" : "connecting")
    resultClearTimer.stop()

    actionProcess.command = [
      "bash",
      root.scriptPath,
      actionName,
      addr,
      String(root.scanTimeoutSec),
      root.smartFallback ? "1" : "0"
    ]
    actionProcess.running = true
  }

  function moveCursor(dy) {
    cursorActive = true
    var count = actionItems.length
    if (count <= 0) return
    selectedActionIndex = (selectedActionIndex + dy + count) % count
  }

  function activateSelected() {
    if (busy) return
    var item = actionItems[selectedActionIndex]
    if (item) runAction(item.id, root.targetAddress)
  }

  function checkAutoHeal() {
    if (!root.autoHealBle || root.busy) return
    var trapped = Model.findConnectedBleOnlyDevice(root.catalogDevices, root.autoHealCooldowns, Date.now())
    if (!trapped) return
    var nextCooldowns = ({})
    for (var k in root.autoHealCooldowns) nextCooldowns[k] = root.autoHealCooldowns[k]
    nextCooldowns[trapped.address] = Date.now()
    root.autoHealCooldowns = nextCooldowns
    root.selectedAddress = trapped.address
    root.runAction("repair", trapped.address)
  }

  function trySwitchAudioSink() {
    if (!switchAudioOutput || !root.targetAddress) return
    var nodes = pipewireNodes || []
    for (var i = 0; i < nodes.length; i++) {
      var node = nodes[i]
      if (Model.bluetoothSinkMatchesDevice(node, root.targetAddress, root.displayName)) {
        Pipewire.preferredDefaultAudioSink = node
        if (node.id !== undefined && node.name) {
          Quickshell.execDetached([
            "omarchy-audio-output-set-default",
            String(node.id),
            String(node.name)
          ])
        }
        audioSwitchTimer.stop()
        return
      }
    }
    pendingAudioSwitchAttempts += 1
    if (pendingAudioSwitchAttempts < 8) {
      audioSwitchTimer.restart()
    }
  }

  onOpenedChanged: {
    if (opened) {
      cursorActive = false
      selectedActionIndex = 0
      refreshStatus()
    }
  }

  onBtDevicesChanged: refreshStatus()

  onIsConnectedChanged: {
    refreshStatus()
    if (isConnected && switchAudioOutput) {
      pendingAudioSwitchAttempts = 0
      audioSwitchTimer.restart()
    }
  }

  Component.onCompleted: refreshStatus()

  Process {
    id: statusProcess
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parsed = Model.parseDeviceCatalog(text)
        root.catalogDevices = parsed
        var picked = Model.pickTargetDevice(parsed, root.selectedAddress, root.preferredAddress)
        if (picked) root.selectedAddress = picked.address
        if (root.autoHealBle && !root.busy) {
          autoHealTimer.restart()
        }
      }
    }
  }

  Process {
    id: actionProcess
    stdout: SplitParser {
      onRead: function(line) {
        var parsed = Model.parseCtlLine(line)
        if (!parsed) return
        if (parsed.kind === "step") {
          root.currentStepKey = parsed.step
        } else if (parsed.kind === "result") {
          root.lastResultOk = parsed.ok
          root.lastResultKey = parsed.reason
          resultClearTimer.restart()
        }
      }
    }
    onExited: {
      root.currentStepKey = ""
      root.busyAction = ""
      root.refreshStatus()
      if (root.lastResultOk && root.switchAudioOutput) {
        root.pendingAudioSwitchAttempts = 0
        audioSwitchTimer.restart()
      }
    }
  }

  Timer {
    id: autoHealTimer
    interval: 2500
    repeat: false
    onTriggered: root.checkAutoHeal()
  }

  Timer {
    id: resultClearTimer
    interval: 8000
    repeat: false
    onTriggered: root.lastResultKey = ""
  }

  Timer {
    id: audioSwitchTimer
    interval: 600
    repeat: false
    onTriggered: root.trySwitchAudioSink()
  }

  ShellIpc {
    target: "mrclaro.bt-audio-fixer"

    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function connect(): void { root.runAction("connect", root.targetAddress) }
    function disconnect(): void { root.runAction("disconnect", root.targetAddress) }
    function repair(): void { root.runAction("repair", root.targetAddress) }
    function scan(): void { root.runAction("scan_bredr", "") }
    function reset(): void { root.runAction("reset", root.targetAddress) }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.icon
    active: root.isBleOnly || root.anyBleOnly
    useActiveColor: root.isBleOnly || root.anyBleOnly
    tooltipText: root.barTooltipText
    onPressed: function(b) {
      if (b === Qt.RightButton) {
        if (root.busy) return
        if (!root.targetAddress) {
          root.open()
          return
        }
        if (root.isConnected && !root.isBleOnly) root.runAction("disconnect", root.targetAddress)
        else root.runAction("connect", root.targetAddress)
      } else if (b === Qt.MiddleButton) {
        if (root.busy) return
        if (root.targetAddress) root.runAction("repair", root.targetAddress)
        else root.runAction("scan_bredr", "")
      } else {
        root.toggle()
      }
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: panel.loadedContent
    contentWidth: panel.fittedContentWidth(Style.space(420))
    contentHeight: panel.fittedContentHeight(panel.loadedContentHeight)

    content: PanelKeyCatcher {
      id: keyCatcher
      implicitHeight: column.implicitHeight
      anchors.fill: parent
      LayoutMirroring.enabled: Commons.I18n.rightToLeft
      LayoutMirroring.childrenInherit: true

      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) {
          root.cursorActive = true
          return
        }
        if (dy !== 0) root.moveCursor(dy)
      }
      onActivateRequested: root.activateSelected()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "1" || t === "c" || t === "C") {
          root.runAction(root.isConnected && !root.isBleOnly ? "disconnect" : "connect", root.targetAddress)
        } else if (t === "2") {
          root.runAction("repair", root.targetAddress)
        } else if (t === "3" || t === "b" || t === "B") {
          root.runAction("reset", root.targetAddress)
        } else if (t === "s" || t === "S") {
          root.runAction("scan_bredr", "")
        } else if (t === "d" || t === "D") {
          root.runAction("disconnect", root.targetAddress)
        } else if (t === "r" || t === "R") {
          root.refreshStatus()
        }
      }

      Column {
        id: column
        anchors.fill: parent
        spacing: Style.space(12)

        PanelHero {
          width: parent.width
          foreground: root.foreground
          fontFamily: root.fontFamily
          title: root.displayName
          detail: root.batteryLabel
          meta: root.heroStatusText
          iconOpacity: root.isConnected && !root.isBleOnly ? 1.0 : 0.75

          iconComponent: Component {
            PlainText {
              text: root.icon
              color: root.isBleOnly
                ? root.urgent
                : (root.isConnected ? root.accent : root.foreground)
              font.family: root.fontFamily
              font.pixelSize: Style.font.display
            }
          }

          trailingControl: Component {
            PanelActionButton {
              iconText: "󰑐"
              tooltipText: Model.plainText(strings.t("panel.refresh"), 80)
              foreground: root.foreground
              fontFamily: root.fontFamily
              enabled: !root.busy
              onClicked: root.refreshStatus()
            }
          }
        }

        // BLE-only warning banner with motion adhering to plugins.md
        BorderSurface {
          id: bleBanner
          visible: root.isBleOnly || opacity > 0
          width: parent.width
          implicitHeight: bleBannerText.implicitHeight + Style.space(16)
          radius: Style.cornerRadius
          color: Style.hoverFillFor(root.urgent, root.urgent)
          borderSpec: Border.controlSpec("normal", root.urgent, root.urgent)
          opacity: root.isBleOnly ? 1 : 0
          scale: root.isBleOnly ? 1 : 0.97

          Behavior on opacity {
            NumberAnimation {
              duration: Style.duration(root.isBleOnly ? 180 : 120)
              easing.type: Easing.OutCubic
            }
          }
          Behavior on scale {
            NumberAnimation {
              duration: Style.duration(root.isBleOnly ? 180 : 120)
              easing.type: Easing.Bezier
              easing.bezierCurve: Style.easeOut
            }
          }

          PlainText {
            id: bleBannerText
            anchors.fill: parent
            anchors.margins: Style.space(8)
            text: strings.t("panel.bleWarning")
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }
        }

        PanelSeparator {
          visible: root.catalogDevices.length > 0
          foreground: root.foreground
        }

        // Dynamic Device Selector (supports any headphone / Bluetooth device)
        Column {
          visible: root.catalogDevices.length > 0
          width: parent.width
          spacing: Style.space(6)

          PanelSectionHeader {
            text: strings.tn("panel.section.devices", root.catalogDevices.length)
              .arg(Commons.I18n.formatNumber(root.catalogDevices.length))
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Repeater {
            model: root.catalogDevices

            delegate: CursorSurface {
              id: devRow
              required property var modelData
              required property int index

              readonly property bool isTarget: root.targetAddress === modelData.address

              width: parent.width
              implicitHeight: devLayout.implicitHeight + Style.space(12)
              foreground: modelData.bleOnly ? root.urgent : root.foreground
              accent: modelData.bleOnly ? root.urgent : root.accent
              bordered: isTarget
              current: isTarget

              RowLayout {
                id: devLayout
                anchors.fill: parent
                anchors.leftMargin: Style.space(10)
                anchors.rightMargin: Style.space(10)
                spacing: Style.space(8)

                PlainText {
                  text: devRow.modelData.bleOnly
                    ? "󰂲"
                    : (devRow.modelData.connected ? "󰋋" : "󰋐")
                  color: devRow.modelData.bleOnly
                    ? root.urgent
                    : (devRow.modelData.connected ? root.accent : root.foreground)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.icon
                  Layout.alignment: Qt.AlignVCenter
                }

                Column {
                  Layout.fillWidth: true
                  Layout.alignment: Qt.AlignVCenter
                  spacing: Style.space(1)

                  PlainText {
                    width: parent.width
                    text: Model.plainText(devRow.modelData.name, Model.MAX_TEXT_LEN)
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    font.bold: devRow.isTarget
                    elide: Text.ElideRight
                  }

                  PlainText {
                    width: parent.width
                    text: Model.plainText(devRow.modelData.address, 24)
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                  }
                }

                BorderSurface {
                  implicitWidth: devBadgeText.implicitWidth + Style.space(8)
                  implicitHeight: devBadgeText.implicitHeight + Style.space(4)
                  radius: Style.cornerRadius
                  color: "transparent"
                  borderSpec: Border.controlSpec(
                    "normal",
                    devRow.modelData.bleOnly ? root.urgent : root.foreground,
                    root.accent
                  )
                  Layout.alignment: Qt.AlignVCenter

                  PlainText {
                    id: devBadgeText
                    anchors.centerIn: parent
                    text: devRow.modelData.bleOnly
                      ? strings.t("panel.device.badgeBle")
                      : (devRow.modelData.hasAudioSink
                        ? strings.t("panel.device.badgeA2dp")
                        : strings.t("panel.device.badgePaired"))
                    color: devRow.modelData.bleOnly ? root.urgent : root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                  }
                }
              }

              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                enabled: !root.busy
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  root.selectedAddress = devRow.modelData.address
                }
                onDoubleClicked: {
                  root.selectedAddress = devRow.modelData.address
                  if (devRow.modelData.bleOnly) {
                    root.runAction("repair", devRow.modelData.address)
                  } else if (devRow.modelData.connected) {
                    root.runAction("disconnect", devRow.modelData.address)
                  } else {
                    root.runAction("connect", devRow.modelData.address)
                  }
                }
              }
            }
          }
        }

        PanelSeparator {
          foreground: root.foreground
        }

        Column {
          width: parent.width
          spacing: Style.space(6)

          PanelSectionHeader {
            text: strings.t("panel.section.actions")
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Repeater {
            model: root.actionItems

            delegate: CursorSurface {
              id: actionRow
              required property var modelData
              required property int index

              readonly property bool disabledRow: root.busy || (modelData.requiresDevice && !root.targetAddress)

              width: parent.width
              implicitHeight: rowLayout.implicitHeight + Style.space(14)
              foreground: modelData.urgent ? root.urgent : root.foreground
              accent: modelData.urgent ? root.urgent : root.accent
              bordered: true
              hasCursor: root.cursorActive && root.selectedActionIndex === index
              current: root.busy && root.busyAction === modelData.id
              opacity: disabledRow && !(root.busy && root.busyAction === modelData.id) ? 0.5 : 1.0

              Behavior on opacity {
                NumberAnimation {
                  duration: Style.duration(140)
                  easing.type: Easing.OutCubic
                }
              }

              RowLayout {
                id: rowLayout
                anchors.fill: parent
                anchors.leftMargin: Style.space(12)
                anchors.rightMargin: Style.space(12)
                spacing: Style.space(10)

                PlainText {
                  text: actionRow.modelData.icon
                  color: actionRow.modelData.urgent ? root.urgent : root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.icon
                  Layout.alignment: Qt.AlignVCenter
                }

                Column {
                  Layout.fillWidth: true
                  Layout.alignment: Qt.AlignVCenter
                  spacing: Style.space(2)

                  PlainText {
                    width: parent.width
                    text: Model.plainText(actionRow.modelData.title, Model.MAX_TEXT_LEN)
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    font.bold: true
                    elide: Text.ElideRight
                  }

                  PlainText {
                    width: parent.width
                    text: Model.plainText(actionRow.modelData.subtitle, Model.MAX_TEXT_LEN)
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                  }
                }

                BorderSurface {
                  implicitWidth: badgeLabel.implicitWidth + Style.space(10)
                  implicitHeight: badgeLabel.implicitHeight + Style.space(4)
                  radius: Style.cornerRadius
                  color: "transparent"
                  borderSpec: Border.controlSpec(
                    "normal",
                    actionRow.modelData.urgent ? root.urgent : root.foreground,
                    root.accent
                  )
                  Layout.alignment: Qt.AlignVCenter

                  PlainText {
                    id: badgeLabel
                    anchors.centerIn: parent
                    text: Model.plainText(actionRow.modelData.badge, 24)
                    color: actionRow.modelData.urgent ? root.urgent : root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                  }
                }
              }

              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                enabled: !actionRow.disabledRow
                cursorShape: root.busy ? Qt.WaitCursor : Qt.PointingHandCursor
                onEntered: {
                  root.cursorActive = true
                  root.selectedActionIndex = actionRow.index
                }
                onClicked: {
                  root.cursorActive = true
                  root.selectedActionIndex = actionRow.index
                  root.runAction(actionRow.modelData.id, root.targetAddress)
                }
              }
            }
          }
        }

        PlainText {
          width: parent.width
          text: strings.t("panel.footerHint")
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          horizontalAlignment: Text.AlignHCenter
          elide: Text.ElideRight
        }
      }
    }
  }
}
