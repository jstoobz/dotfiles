---
name: nerves-expert
description: Nerves embedded/IoT patterns including host-vs-target builds, Circuits hardware libraries, VintageNet networking, NervesHub OTA updates, and firmware lifecycle
targets:
  elixir: "1.18+"
  nerves: "1.11+"
  otp: "27+"
---

# Nerves Expert

## When to Use This Skill

- Building firmware for embedded targets (Raspberry Pi, BeagleBone, custom hardware)
- Working with `mix firmware`, `mix burn`, `mix upload`, or `MIX_TARGET`
- Using `Circuits.GPIO` / `Circuits.I2C` / `Circuits.SPI` / `Circuits.UART` to talk to peripherals
- Configuring `VintageNet` for Wi-Fi, Ethernet, or cellular
- Setting up NervesHub for OTA firmware deployment or fleet management
- Skip this skill when working on standard server-side Elixir (use `elixir-expert`)

## Mental Model

- **Nerves is not "Elixir on Linux"** — it's a stripped-down embedded Linux where the BEAM is essentially PID 1. There's no shell, no package manager, no systemd. Your release IS the system.
- **Host vs Target are two different builds.** `MIX_TARGET=host` gives you a normal Elixir app on your dev machine (with hardware shims). `MIX_TARGET=rpi4` (or similar) cross-compiles for the device. Same code, different deps and config.
- **The filesystem is mostly read-only.** `/data` (or `/root` on some systems) is the only writable partition that persists across firmware updates. Everything else is replaced wholesale on update.
- **Firmware is atomic.** A "deploy" is the entire OS + BEAM + your release packaged as a single `.fw` artifact (typically 30-100MB). You don't push files; you flash or upload firmware.
- **A/B partitioning gives you safe updates.** New firmware writes to the inactive partition. Reboot switches active. Failed boot reverts. This is what makes OTA updates safe in the field.

## Architecture / Build & Deploy Flow

```
Host build (MIX_TARGET=host):
  Standard Elixir — runs on dev machine, hardware calls return stubs

Target build (MIX_TARGET=rpi4):
  mix deps.get → cross-compile for ARM → mix firmware → app.fw artifact
                                                            ↓
                            ┌───────────────────────────────┼───────────────────┐
                            ↓                               ↓                   ↓
                  mix burn (SD card)            mix upload (SSH, dev)   NervesHub (OTA)

Device boot:
  Bootloader → kernel + initramfs → ERTS → release → Application supervisor
                                                          ↓
                                            (your code starts running)
```

## Decision Tree: Where Does This Code Run?

```
What's this dependency or module for?
├── Pure Elixir, runs anywhere? → no targets restriction
├── Talks to real hardware (GPIO, I2C, sensors)? → targets: @all_targets (or specific list)
│   └── Add a host stub for dev: targets: [:host] for a mock module
├── Build tool only (firmware tooling, NervesHub CLI)? → only_in_target or runtime: false
├── Phoenix / web UI on the device? → all targets, but watch firmware size
└── Test-only? → only: :test (excluded from firmware automatically)
```

## Decision Tree: Which Hardware Library?

```
What kind of peripheral?
├── Single-pin digital input/output (LED, button, relay)? → Circuits.GPIO
├── Bus with multiple addressable devices (sensors, displays, RTCs)? → Circuits.I2C
├── High-speed full-duplex (some displays, ADCs, fast sensors)? → Circuits.SPI
├── Serial device (GPS, modem, legacy peripheral)? → Circuits.UART
├── PWM (motor speed, servo, dimmable LED)? → pigpiox or platform-specific lib
├── 1-Wire (DS18B20 temperature sensors)? → OneWire (via sysfs)
└── USB device? → varies — likely a kernel module + sysfs/character device
```

## Decision Tree: Where Does State Persist?

```
What's the lifetime of this data?
├── Process memory only, lost on restart? → Agent / GenServer state
├── Survives BEAM restart, lost on firmware update? → /tmp or RAM-backed FS
├── Survives firmware updates? → /data partition (writable, persistent)
│   └── Examples: device-specific config, calibration data, captured logs
├── Set at provisioning, never changes? → /root or burn into firmware
├── Sent to cloud/fleet, queryable across devices? → NervesHub or your own backend
└── Sensitive (keys, certs)? → /data with proper file perms; consider TPM if hardware supports
```

## Decision Tree: How To Deploy An Update

```
What's the situation?
├── Initial provisioning of a new device? → mix burn (write SD card directly)
├── Fast iteration on a device on your bench (same network)? → mix upload (SSH push)
├── Fleet of devices in the field, controlled rollout? → NervesHub deployment
├── One-off hotfix to a single device, no NervesHub? → mix firmware.gen.script + scp + fwup
└── Recovery from bricked state? → reflash SD card with mix burn
```

## Core Patterns

### `mix.exs` with target-aware deps

```elixir
defmodule MyDevice.MixProject do
  use Mix.Project

  @app :my_device
  @version "0.1.0"
  @all_targets [:rpi0, :rpi3, :rpi4, :bbb, :x86_64]

  def project do
    [
      app: @app,
      version: @version,
      elixir: "~> 1.18",
      archives: [nerves_bootstrap: "~> 1.13"],
      build_embedded: true,
      deps: deps(),
      releases: [{@app, release()}],
      preferred_cli_target: [run: :host, test: :host]
    ]
  end

  def application do
    [mod: {MyDevice.Application, []}, extra_applications: [:logger, :runtime_tools]]
  end

  defp deps do
    [
      # Runs everywhere
      {:nerves, "~> 1.11", runtime: false},
      {:shoehorn, "~> 0.9"},
      {:ring_logger, "~> 0.11"},

      # Target-only (cross-compiled for hardware)
      {:nerves_runtime, "~> 0.13", targets: @all_targets},
      {:nerves_pack, "~> 0.7", targets: @all_targets},
      {:circuits_gpio, "~> 2.1", targets: @all_targets},
      {:vintage_net_wifi, "~> 0.12", targets: @all_targets},

      # Per-target system deps
      {:nerves_system_rpi4, "~> 1.27", runtime: false, targets: :rpi4},
      {:nerves_system_rpi0, "~> 1.27", runtime: false, targets: :rpi0}
    ]
  end

  defp release do
    [overwrite: true, cookie: "#{@app}_cookie", include_erts: &Nerves.Release.erts/0,
     steps: [&Nerves.Release.init/1, :assemble], strip_beams: Mix.env() == :prod]
  end
end
```

**Rule:** Hardware deps (Circuits, VintageNet, etc.) must use `targets:` — without it, they try to compile on the host and fail or pull in the wrong NIFs.

### Target-conditional supervision tree

```elixir
defmodule MyDevice.Application do
  use Application

  @target Mix.target()

  def start(_type, _args) do
    children = [MyDevice.Repo, MyDeviceWeb.Endpoint] ++ children(@target)

    Supervisor.start_link(children, strategy: :one_for_one, name: MyDevice.Supervisor)
  end

  # Host: stubs only — no real hardware on dev machine
  defp children(:host) do
    [{MyDevice.Sensors.Mock, []}]
  end

  # Target: real hardware drivers
  defp children(_target) do
    [
      {MyDevice.Sensors.TempSensor, i2c_bus: "i2c-1", address: 0x48},
      {MyDevice.LedController, gpio_pin: 17},
      {MyDevice.Network.Watchdog, []}
    ]
  end
end
```

**Rule:** `Mix.target()` is compile-time. The match-on-target is decided when you build, not at runtime. Same release won't work on multiple targets — each `MIX_TARGET` produces a distinct firmware.

### GPIO (digital I/O)

```elixir
defmodule MyDevice.LedController do
  use GenServer
  alias Circuits.GPIO

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  def on, do: GenServer.cast(__MODULE__, :on)
  def off, do: GenServer.cast(__MODULE__, :off)

  @impl true
  def init(opts) do
    pin = Keyword.fetch!(opts, :gpio_pin)
    {:ok, ref} = GPIO.open(pin, :output)
    {:ok, %{ref: ref}}
  end

  @impl true
  def handle_cast(:on, %{ref: ref} = state) do
    GPIO.write(ref, 1)
    {:noreply, state}
  end

  def handle_cast(:off, %{ref: ref} = state) do
    GPIO.write(ref, 0)
    {:noreply, state}
  end

  # Listen for input changes (button press, etc.)
  @impl true
  def handle_info({:circuits_gpio, _pin, _timestamp, value}, state) do
    Logger.info("GPIO changed to #{value}")
    {:noreply, state}
  end
end
```

### I2C transaction (read a sensor)

```elixir
defmodule MyDevice.Sensors.TempSensor do
  use GenServer
  alias Circuits.I2C

  def read_temp, do: GenServer.call(__MODULE__, :read_temp)

  @impl true
  def init(opts) do
    bus = Keyword.fetch!(opts, :i2c_bus)
    address = Keyword.fetch!(opts, :address)
    {:ok, ref} = I2C.open(bus)
    {:ok, %{ref: ref, address: address}}
  end

  @impl true
  def handle_call(:read_temp, _from, %{ref: ref, address: addr} = state) do
    # Write register pointer, then read 2 bytes — typical I2C sensor pattern
    case I2C.write_read(ref, addr, <<0x00>>, 2) do
      {:ok, <<msb, lsb>>} ->
        temp_c = ((msb <<< 4) ||| (lsb >>> 4)) * 0.0625
        {:reply, {:ok, temp_c}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end
end
```

### VintageNet Wi-Fi configuration

```elixir
# Runtime configuration, not compile-time — usually set from /data on first boot
VintageNet.configure("wlan0", %{
  type: VintageNetWiFi,
  vintage_net_wifi: %{
    networks: [
      %{
        key_mgmt: :wpa_psk,
        ssid: System.get_env("WIFI_SSID"),
        psk: System.get_env("WIFI_PSK")
      }
    ]
  },
  ipv4: %{method: :dhcp}
})

# Subscribe to interface state changes
VintageNet.subscribe(["interface", "wlan0", "connection"])

# Receive: {VintageNet, ["interface", "wlan0", "connection"], old, new, _meta}
def handle_info({VintageNet, _path, _old, :internet, _meta}, state) do
  Logger.info("Internet is up — starting cloud sync")
  {:noreply, %{state | online: true}}
end
```

**Rule:** Wi-Fi credentials should never be baked into firmware. Read from `/data` config or pass via NervesHub secrets at provisioning. `regulatory_domain` matters — without setting your country code, some channels won't work and Wi-Fi may misbehave.

### `mix upload` for fast dev iteration

```bash
# One-time SSH setup (puts your key on the device)
mix upload.ssh

# Iterate: rebuild firmware and push without re-flashing
MIX_TARGET=rpi4 mix firmware
MIX_TARGET=rpi4 mix upload nerves.local
# Device reboots into new firmware via A/B partition swap
```

## Anti-patterns

### Don't: write to anywhere except `/data` (or `/root`)

```elixir
# BAD
File.write!("/srv/erlang/lib/my_device-0.1.0/priv/cache.json", json)
```

**Why it bites:** Everywhere outside `/data` is read-only on a running device, AND those paths get replaced on every firmware update. Your write may even succeed in dev (overlay FS), then mysteriously fail in prod, then mysteriously vanish on the next OTA.

**Instead:**

```elixir
# GOOD
File.write!("/data/cache.json", json)
```

Use `/data` for anything that must survive reboots OR firmware updates. Treat `priv/` as read-only.

### Don't: forget `MIX_TARGET` and ship a host build

```bash
# BAD
mix firmware
# (MIX_TARGET defaults to host — produces nothing useful, may even succeed silently)
```

**Why it bites:** A host build doesn't include the cross-compiled BEAM, kernel, or hardware deps. The resulting `.fw` either fails to flash, or worse, silently flashes broken firmware.

**Instead:** Always export `MIX_TARGET` for the session, or pass it explicitly:

```bash
export MIX_TARGET=rpi4
mix deps.get
mix firmware
mix burn
```

Set `preferred_cli_target` in `mix.exs` so common tasks default sensibly.

### Don't: block in `Application.start/2`

```elixir
# BAD
def start(_type, _args) do
  :ok = MyDevice.Sensors.calibrate_blocking()  # 30 seconds
  Supervisor.start_link(children(), ...)
end
```

**Why it bites:** `Application.start/2` runs synchronously during boot. Blocking here delays the entire system from coming up — including the SSH server you'd use to debug it. If it crashes, the device never boots. If it takes too long, the watchdog may reset the device.

**Instead:** Start a supervised GenServer that does the calibration in `handle_continue/2`. Boot completes immediately; calibration runs in the background and other processes can wait on its readiness via `Process.monitor` or a registry.

### Don't: assume the network is up

```elixir
# BAD
def start(_type, _args) do
  {:ok, _} = MyDevice.CloudSync.connect()  # crashes if Wi-Fi not connected yet
  Supervisor.start_link(children(), ...)
end
```

**Why it bites:** On boot, Wi-Fi takes seconds to associate and may never connect (bad credentials, no AP in range). Cellular takes longer. Code that assumes connectivity at startup will crash-loop and trigger the watchdog.

**Instead:** Subscribe to `VintageNet` state changes and start network-dependent work only after `:internet` is reached. Have a sensible offline mode (queue events, retry on reconnect).

### Don't: store secrets in firmware

```elixir
# BAD
config :my_device, :api_key, "sk_live_abc123..."
```

**Why it bites:** Firmware is reproducible from source — anyone with the `.fw` can extract strings. If the device is physically accessible (it is), the secret is recoverable. Also: rotating the secret means flashing every device.

**Instead:** Provision secrets to `/data` at first boot via NervesHub, a setup wizard, or a one-time provisioning script. Read at runtime from a known path. For high-value keys, use hardware crypto (TPM, ATECC608) if available.

## Common Gotchas

- **`MIX_TARGET=host` is the default** — every `mix` command without it gives you a host build. Export it once per shell session or alias `iex -S mix` to include it.
- **`/data` survives firmware updates; everything else does not** — internalize this. Calibration data, paired Bluetooth devices, Wi-Fi credentials, captured logs all belong in `/data`.
- **Time can be wildly wrong on first boot** — most embedded boards have no RTC. The clock starts at 1970 (or whenever the firmware was built) and only corrects after NTP succeeds. Don't use `DateTime.utc_now()` for anything time-sensitive until NTP has synced.
- **`Logger` to console is not free** — default config sends logs to RingLogger (in-memory ring buffer). Connecting via SSH and running `RingLogger.next()` is the usual debug flow. Don't expect `IO.puts` output unless you've wired stdout somewhere.
- **GPIO pin numbering varies** — Circuits uses BCM (Broadcom) numbering on Raspberry Pi, not the physical pin numbers on the header. Check the pinout before wiring.
- **Custom NIFs need a cross-compilation toolchain** — `nerves_system_*` provides one, but Makefiles need to honor `CC` / `CFLAGS` / `CROSSCOMPILE` from the env. Check existing Nerves-friendly libs (`elixir_make` integrates well) for working examples.
- **Firmware is the entire OS** — a 1KB code change still ships a 30-100MB firmware. NervesHub deltas help, but the wire cost on the first deployment is full size.
- **`mix upload` requires the same firmware UUID lineage** — you can't `mix upload` a fundamentally different firmware (e.g., switched from `:rpi3` to `:rpi4`). The bootloader rejects mismatched firmware.

## Quick Reference

```
Common mix tasks (all require MIX_TARGET set):
  mix deps.get             — fetch deps for current target
  mix firmware             — build .fw artifact
  mix burn                 — write firmware to inserted SD card (uses fwup)
  mix upload <host>        — push firmware over SSH (A/B partition swap)
  mix firmware.gen.script  — generate fwup script for manual deploy
  mix firmware.unpack      — inspect contents of a .fw

Common targets:
  rpi0, rpi3, rpi3a, rpi4, rpi5  — Raspberry Pi family
  bbb                             — BeagleBone Black
  x86_64                          — generic x86_64 (Intel NUC, VM)
  osd32mp1, grisp2, ...           — specialized boards (own systems)

Filesystem layout (typical Nerves device):
  /                  — read-only root (replaced on firmware update)
  /srv/erlang        — your release lives here (read-only)
  /data              — writable, persists across firmware updates
  /tmp               — RAM-backed, lost on reboot
  /root              — sometimes writable (system-dependent)
```

## When to Load Deeper References

- Building drivers for specific peripherals (GPIO interrupts, SPI multi-byte transactions, I2C device classes, UART framing)? → Read `references/circuits-hardware.md`
- Configuring complex network setups (Wi-Fi roaming, ethernet + cellular failover, USB gadget mode, AP-mode for provisioning)? → Read `references/vintage-networking.md`
- Setting up NervesHub (signing keys, deployments, fleet rollout strategy, device certificates, console access)? → Read `references/nerves-hub.md`
- Structuring a multi-app Nerves project (poncho layout, shared libraries, separate firmware variants)? → Read `references/poncho-projects.md`
- Building a custom `nerves_system_*` for new hardware (Buildroot config, kernel options, custom drivers)? → Read `references/custom-systems.md`
