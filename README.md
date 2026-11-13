# mrclaro.bt-audio-fixer — Bluetooth Audio Fixer for Omarchy

A universal status bar widget and recovery panel for the [Omarchy](https://omarchy.org/) Shell that fixes the infamous **Linux BlueZ BLE vs. BR/EDR trap** on dual-mode Bluetooth headphones and earbuds.

![Bluetooth Audio Fixer preview](preview.png?v=2)

> **Português (PT-BR):** [Clique aqui para ler a documentação em Português](#português-pt-br)

---

## The Problem

Most modern Bluetooth headphones and earbuds (Edifier, Sony, Bose, JBL, Sennheiser, Soundcore, QCY, AirPods, etc.) are **Dual-Mode** devices:
1. **BR/EDR (Bluetooth Classic):** Carries actual audio profiles (`Audio Sink` `0000110b`, `A2DP` `0000110d`, `Handsfree` `0000111e`, `HSP` `00001108`).
2. **BLE (Bluetooth Low Energy):** Broadcasts beacons for mobile companion apps, battery widgets, or Google Fast Pair (`GATT` services / `random` LE addresses).

On Linux (`BlueZ`), scanning in default `auto` mode frequently catches the **BLE advertisement** first. When that happens:
- The headphone pairs or connects over **BLE only** (`Connected: yes`, but no audio output appears in PipeWire/PulseAudio).
- `bluetoothctl connect` fails with `br-connection-profile-unavailable` or `le-connection-abort-by-local`.
- After suspend/resume or repeated dual-mode collisions, USB Bluetooth controllers (`btusb`) can lock up at the HCI layer until the adapter is power-cycled or the kernel module is reloaded.

Traditionally, fixing this required opening a terminal and running a chain of `bluetoothctl` and `modprobe` commands by hand. **`mrclaro.bt-audio-fixer`** automates the detection and recovery directly from the Omarchy bar.

---

## How It Works

- **Automatic BLE-Trap Detection:** Reads `bluetoothctl` device records and checks whether each device exposes Classic Audio UUIDs (`0000110b`, `0000110d`, `0000111e`, `00001108`). If a non-HID device is cached or connected with only BLE GATT UUIDs or a `random` LE address, the plugin flags it as **`BLE ONLY`** and highlights the bar icon.
- **Background Auto-Heal:** When a headphone connects in BLE-only mode, the plugin can automatically trigger a `BR/EDR` re-pair in the background (with a 60s per-device cooldown) without requiring a single click.
- **HID Peripheral Exclusion:** BLE mice, keyboards, and tablets (`00001812` / `00001124`) are automatically excluded so they are never mistaken for trapped audio devices.
- **Transport-Specific `BR/EDR` Scanning:** Uses `bluetoothctl --timeout <N> scan bredr` to force BlueZ to discover devices on the Classic Audio (`BR/EDR`) radio while ignoring BLE beacons.
- **Four Recovery & Connection Modes:**
  1. **Smart Connect (`A2DP`):** Powers on the adapter, trusts and connects to the selected headphone, verifies that the Classic Audio profile is active, and switches the default PipeWire audio output to it. If connection fails or lands in BLE-only mode, it automatically falls back to **Force BR/EDR Re-pair**.
  2. **Force BR/EDR Re-pair (`BR/EDR`):** Removes the stale BLE cache entry (if no Audio Sink UUID is present), runs a `BR/EDR`-only scan, pairs, trusts, and connects.
  3. **Scan Classic Audio (`SCAN`):** Scans for nearby headphones exclusively over `BR/EDR` so dual-mode headphones appear with their audio profiles instead of their BLE alias.
  4. **Reset USB Stack (`btusb`) & Recover (`HCI RESET`):** Performs a user-space adapter power cycle followed by a `btusb` kernel module reload (`modprobe -r btusb && modprobe btusb` via Omarchy's native Polkit prompt or passwordless sudo), removes the corrupted device cache, and runs a fresh `BR/EDR` re-pair.

---

## Installation

```bash
omarchy plugin add https://github.com/MrClaro/mrclaro.bt-audio-fixer.git --enable
```

Or to enable and place it right next to the built-in Bluetooth icon:

```bash
omarchy plugin enable mrclaro.bt-audio-fixer --before omarchy.bluetooth
```

Validate the plugin at any time with:

```bash
omarchy plugin validate ~/.config/omarchy/plugins/mrclaro.bt-audio-fixer
```

## Updating & Uninstalling

```bash
# Update to the latest version
omarchy plugin update mrclaro.bt-audio-fixer --yes

# Disable from the bar without deleting
omarchy plugin disable mrclaro.bt-audio-fixer

# Uninstall completely (removes from bar and deletes plugin directory)
omarchy plugin remove mrclaro.bt-audio-fixer
```

---

## Usage

### Bar Icon Interactions
| Action | Behavior |
|---|---|
| **Left click** | Opens / closes the **Bluetooth Audio Fixer** panel |
| **Right click** | Runs **Smart Connect** on the selected/active audio device (or disconnects if already connected with A2DP audio) |
| **Middle click** | Runs **Force BR/EDR Re-pair** on the selected device (or starts a `BR/EDR` scan if no device is paired yet) |

### Panel & Keyboard Shortcuts
Inside the popup panel, click any device in the **Devices** list to select it (or double-click a device row to connect/repair it immediately).

| Key | Action |
|---|---|
| `↑` / `↓` or `j` / `k` | Navigate recovery actions |
| `Enter` / `Space` | Run the highlighted action |
| `1` or `c` | **Smart Connect** (or disconnect if already connected with audio) |
| `2` | **Force BR/EDR Re-pair** |
| `3` or `b` | **Reset USB Stack (`btusb`) & Recover** |
| `s` | **Scan Classic Audio (`BR/EDR`)** |
| `d` | **Disconnect** active device |
| `r` | **Refresh** device status |
| `Esc` | Close panel |

### CLI / Hyprland Keybinding IPC
You can trigger any action from scripts or `~/.config/hypr/bindings.lua` via `omarchy-shell`:

```bash
omarchy-shell mrclaro.bt-audio-fixer toggle      # Open/close the popup panel
omarchy-shell mrclaro.bt-audio-fixer connect     # Smart Connect (with auto-fallback to BR/EDR repair)
omarchy-shell mrclaro.bt-audio-fixer repair      # Force BR/EDR re-pair on the active device
omarchy-shell mrclaro.bt-audio-fixer scan        # Scan for headphones over Classic Audio (BR/EDR)
omarchy-shell mrclaro.bt-audio-fixer reset       # Power-cycle + reload btusb kernel module and recover
omarchy-shell mrclaro.bt-audio-fixer disconnect  # Disconnect active device
```

---

## Configuration

Settings can be customized on the widget entry inside `~/.config/omarchy/shell.json` (or with `omarchy bar set mrclaro.bt-audio-fixer <key> <value>`):

| Key | Type | Default | Description |
|---|---|---|---|
| `scanTimeoutSec` | `integer` (`2`–`30`) | `5` | Duration (in seconds) for `BR/EDR` discovery scans |
| `smartFallback` | `boolean` | `true` | Automatically run `BR/EDR` re-pair when normal connect fails or lands on BLE without an Audio Sink |
| `autoHealBle` | `boolean` | `true` | Automatically trigger a `BR/EDR` re-pair in the background when a headphone connects in BLE-only mode |
| `switchAudioOutput` | `boolean` | `true` | Automatically set the headphone as the default PipeWire audio output upon connection |
| `preferredDevice` | `string` | `""` | Optional MAC address (`XX:XX:XX:XX:XX:XX`) to prioritize when multiple headphones are paired |

---

## External Dependencies & Permissions

All dependencies come pre-installed on standard Omarchy / Arch Linux systems:
- **`bluez-utils` (`bluetoothctl`):** Used to query Bluetooth device records, scan over `BR/EDR`, pair, trust, and connect.
- **`coreutils` (`timeout`):** Bounds every `bluetoothctl` call so a unresponsive controller never hangs the shell.
- **`kmod` (`modprobe`) & `polkit` (`pkexec`) / `sudo` *(Optional — only for Action 3 "Reset USB Stack")*:** Reloading the `btusb` kernel module (`modprobe -r btusb && modprobe btusb`) requires root privileges and prompts via Polkit (`pkexec`) unless passwordless `sudo` is configured. All other actions (**Smart Connect**, **Force BR/EDR Re-pair**, **Scan Classic Audio**, **Disconnect**, and **Auto-Heal**) run entirely in user space without elevated privileges.
- **`omarchy-bluetooth-power` *(Optional)*:** Used if present on Omarchy to unblock/power on the Bluetooth radio before `bluetoothctl power on`.

The plugin does not modify user configuration files on its own; enabling or disabling it is managed exclusively through `omarchy plugin`.

---

## Development & Tests

```bash
# Run unit & security regression tests (markup neutralization, BLE detection, bounds)
node tests/model.test.js

# Run cross-file contract, settings, IPC, and i18n parity tests
node tests/wiring.test.js

# Validate manifest and entry points
omarchy plugin validate .
```

The plugin ships with live translations in `i18n/` (`en.json`, `pt-BR.json`, `pt.json`) following Omarchy's language setting without requiring a shell restart.

## License

Released under the [MIT License](LICENSE).

---

# Português (PT-BR)

## O Problema que o Plugin Resolve

A maioria dos fones de ouvido Bluetooth modernos (Edifier, Sony, Bose, JBL, Sennheiser, Soundcore, QCY, AirPods, etc.) opera em **Modo Duplo (Dual-Mode)**:
1. **BR/EDR (Bluetooth Clássico):** Transporta os canais reais de áudio (`Audio Sink` `0000110b`, `A2DP` `0000110d`, `Handsfree` `0000111e`, `HSP` `00001108`).
2. **BLE (Bluetooth Low Energy):** Emite sinais para aplicativos de celular, leitura rápida de bateria ou Fast Pair (serviços `GATT` / endereço `random`).

No Linux (`BlueZ`), a busca padrão (`scan on` em modo `auto`) frequentemente captura o anúncio **BLE** primeiro. Quando isso ocorre:
- O fone pareia ou conecta **apenas em protocolo BLE** (`Connected: yes`, mas nenhuma saída de áudio aparece no PipeWire/sistema).
- O comando `bluetoothctl connect` falha com `br-connection-profile-unavailable` ou `le-connection-abort-by-local`.
- Em alguns casos (especialmente após suspensão ou colisões entre BLE e BR/EDR), o driver USB Bluetooth (`btusb`) trava e precisa ser recarregado no kernel (`modprobe -r btusb && modprobe btusb`).

O **`mrclaro.bt-audio-fixer`** resolve isso direto na barra do Omarchy para **qualquer fone Bluetooth**, sem precisar digitar comandos no terminal.

## Como Ele Funciona

1. **Detecção Automática de Fones Presos em BLE + Auto-Heal:** Lista todos os dispositivos conhecidos pelo BlueZ e verifica seus UUIDs. Se um dispositivo (que não seja mouse/teclado HID) estiver sem o UUID `Audio Sink` (`0000110b`), o plugin exibe o alerta **`SÓ BLE`**, destaca o ícone da barra e (quando `autoHealBle` está ativo) pode iniciar a recuperação `BR/EDR` automaticamente em segundo plano.
2. **Conexão Inteligente (`Smart Connect`):** Tenta conectar diretamente; se a conexão falhar ou subir apenas em BLE (sem áudio), ele limpa o cache BLE e refaz o pareamento forçando `BR/EDR` automaticamente, além de selecionar o fone como saída padrão no PipeWire.
3. **Forçar Pareamento BR/EDR (`bluetoothctl scan bredr`):** Limpa o registro BLE corrompido, escaneia exclusivamente no transporte de áudio clássico (`BR/EDR`), pareia, marca como confiável (`trust`) e conecta.
4. **Resetar Stack USB (`btusb`) e Recuperar:** Faz primeiro um ciclo de energia no adaptador e em seguida recarrega o módulo `btusb` no kernel via janela gráfica do Polkit (`pkexec`), aguarda o controlador voltar, remove o cache antigo e reconecta em `BR/EDR`.

## Instalação

```bash
omarchy plugin add https://github.com/MrClaro/mrclaro.bt-audio-fixer.git --enable
omarchy plugin enable mrclaro.bt-audio-fixer --before omarchy.bluetooth
```

## Atualização e Desinstalação

O plugin é 100% autocontido dentro de `~/.config/omarchy/plugins/mrclaro.bt-audio-fixer/` (não instala daemons nem arquivos fora da própria pasta). O próprio CLI nativo do Omarchy cuida de desativar o widget da barra e remover a pasta:

```bash
# Atualizar para a versão mais recente
omarchy plugin update mrclaro.bt-audio-fixer --yes

# Apenas desativar da barra (mantendo instalado)
omarchy plugin disable mrclaro.bt-audio-fixer

# Desinstalar completamente (remove da barra e apaga a pasta do plugin)
omarchy plugin remove mrclaro.bt-audio-fixer
```

## Como Usar

- **Clique esquerdo no ícone da barra:** Abre/fecha o painel com a lista de dispositivos e ações.
- **Clique direito no ícone da barra:** Executa o **Smart Connect** no fone selecionado (ou desconecta se já estiver conectado com áudio A2DP).
- **Clique do meio (scroll) no ícone da barra:** Executa direto o **Forçar Pareamento BR/EDR**.
- **Atalhos no painel:** `1`/`c` (Smart Connect), `2` (Forçar BR/EDR), `3`/`b` (Resetar `btusb`), `s` (Scan BR/EDR), `d` (Desconectar), `r` (Atualizar), `Esc` (Fechar).

## Licença

[MIT](LICENSE)
