# Options

Every option the modules of this flake declare. This file is generated from the module sources: change a description there, then run `nix run .#std-write-option-reference`.

## Home Manager module

Declared in [hm-module.nix](../hm-module.nix).

### `programs.mullvad-vpn-gui.enable`

Whether to enable Mullvad VPN GUI client (Home Manager).

Type: `boolean`. Default: `false`.

### `programs.mullvad-vpn-gui.package`

The mullvad-vpn package providing the GUI binary.

Type: `package`. Default: `pkgs.mullvad-vpn`.

### `programs.mullvad-vpn-gui.autostart`

Launch the GUI on session start (writes a .desktop entry to
`$XDG_CONFIG_HOME/autostart/`). Independent of daemon auto-connect.

Type: `boolean`. Default: `false`.

### `programs.mullvad-vpn-gui.settings`

User-scope GUI preferences, seeded into
`$XDG_CONFIG_HOME/Mullvad VPN/gui_settings.json` at activation when
that file does not exist yet. These are GUI-only preferences
(window state, tray icon style, notifications) — they do NOT change
connection / privacy behavior. Daemon settings live under
`services.mullvad-vpn-declarative.settings`.

An existing file is left alone, so the app's own changes survive.
To apply these values again, delete the file and activate.

Type: `submodule`. Default: `{ }`.

### `programs.mullvad-vpn-gui.settings.animateMap`

Animate the connection-status map. Off saves CPU on weak hardware.

Type: `boolean`. Default: `false`.

### `programs.mullvad-vpn-gui.settings.autoConnect`

GUI auto-connect (separate from daemon-level autoConnect).
GUI-side: connects when the GUI window opens.
Daemon-side: connects on daemon start.
Usually you want the daemon-side one (more reliable).

Type: `boolean`. Default: `false`.

### `programs.mullvad-vpn-gui.settings.enableSystemNotifications`

Show the app's desktop notifications.

Type: `boolean`. Default: `true`.

### `programs.mullvad-vpn-gui.settings.monochromaticIcon`

Tray icon style. Monochrome blends with most themes.

Type: `boolean`. Default: `true`.

### `programs.mullvad-vpn-gui.settings.preferredLocale`

GUI language. 'system' follows the OS locale.

Type: `string`. Default: `"system"`.

### `programs.mullvad-vpn-gui.settings.startMinimized`

Start hidden in tray instead of opening the main window.

Type: `boolean`. Default: `true`.

### `programs.mullvad-vpn-gui.settings.unpinnedWindow`

Allow window to be moved/resized freely (vs pinned to tray).

Type: `boolean`. Default: `true`.

## NixOS module

Declared in [nixos-module.nix](../nixos-module.nix).

### `services.mullvad-vpn-declarative.enable`

Whether to enable Mullvad VPN daemon with declarative settings.

Type: `boolean`. Default: `false`.

### `services.mullvad-vpn-declarative.package`

The Mullvad daemon package, which also carries the `mullvad` CLI the
settings-apply script drives. nixpkgs splits the daemon (`pkgs.mullvad`)
from the desktop app (`pkgs.mullvad-vpn`); the GUI package is selected
by `services.mullvad-vpn.gui.package`.

Type: `package`. Default: `pkgs.mullvad`.

### `services.mullvad-vpn-declarative.settings`

Declarative Mullvad daemon settings. Applied on activation via
individual `mullvad <subcmd> set` calls (CLI 2026.1+). The
daemon validates each call, so invalid values error visibly
instead of silently corrupting /etc/mullvad-vpn/settings.json.

**Options without a CLI setter in 2026.1** (left at daemon
default until upstream exposes them):

- `updateDefaultLocation` — no CLI command
- `relay.entryProviders` — `mullvad relay set entry` supports
  `location` and `custom-list` only
- `relay.entryOwnership` — same limitation as entryProviders

Type: `submodule`. Default: `{ }`.

### `services.mullvad-vpn-declarative.settings.apiAccess`

The ways the daemon may reach Mullvad's API.

Type: `submodule`. Default: `{ }`.

### `services.mullvad-vpn-declarative.settings.apiAccess.direct`

Direct API access (built-in method index 1).

Type: `boolean`. Default: `true`.

### `services.mullvad-vpn-declarative.settings.apiAccess.encryptedDnsProxy`

API via DoH (built-in method index 3).

Type: `boolean`. Default: `true`.

### `services.mullvad-vpn-declarative.settings.apiAccess.mullvadBridges`

API via bridge relay (built-in method index 2).

Type: `boolean`. Default: `true`.

### `services.mullvad-vpn-declarative.settings.autoConnect`

Connect automatically on daemon start.

Type: `boolean`. Default: `true`.

### `services.mullvad-vpn-declarative.settings.betaProgram`

Opt into beta update notifications.

Type: `boolean`. Default: `false`.

### `services.mullvad-vpn-declarative.settings.dns`

The DNS the tunnel uses: Mullvad's own, with its content blockers, or servers you name.

Type: `submodule`. Default: `{ }`.

### `services.mullvad-vpn-declarative.settings.dns.blockAds`

Block ads through Mullvad's DNS. Applies while custom servers are not in use.

Type: `boolean`. Default: `false`.

### `services.mullvad-vpn-declarative.settings.dns.blockAdultContent`

Block adult content through Mullvad's DNS. Applies while custom servers are not in use.

Type: `boolean`. Default: `false`.

### `services.mullvad-vpn-declarative.settings.dns.blockGambling`

Block gambling sites through Mullvad's DNS. Applies while custom servers are not in use.

Type: `boolean`. Default: `false`.

### `services.mullvad-vpn-declarative.settings.dns.blockMalware`

Block malware domains through Mullvad's DNS. Applies while custom servers are not in use.

Type: `boolean`. Default: `false`.

### `services.mullvad-vpn-declarative.settings.dns.blockSocialMedia`

Block social media through Mullvad's DNS. Applies while custom servers are not in use.

Type: `boolean`. Default: `false`.

### `services.mullvad-vpn-declarative.settings.dns.blockTrackers`

Block trackers through Mullvad's DNS. Applies while custom servers are not in use.

Type: `boolean`. Default: `true`.

### `services.mullvad-vpn-declarative.settings.dns.customServers`

Custom DNS servers (only applied when `mode = "custom"`).
Empty list + `mode = "custom"` falls back to default
DNS to avoid a CLI error.

Type: `list of string`. Default: `[ ]`.

### `services.mullvad-vpn-declarative.settings.dns.mode`

`default` uses Mullvad's DNS with the blockers set here. `custom` uses `customServers` and no blocker.

Type: `one of "default", "custom"`. Default: `"default"`.

### `services.mullvad-vpn-declarative.settings.lan`

Allow LAN sharing while connected.

Type: `boolean`. Default: `true`.

### `services.mullvad-vpn-declarative.settings.lockdownMode`

Block all traffic when VPN disconnected (kill-switch).

Type: `boolean`. Default: `false`.

### `services.mullvad-vpn-declarative.settings.multihop`

Routing the tunnel through two relays instead of one.

Type: `submodule`. Default: `{ }`.

### `services.mullvad-vpn-declarative.settings.multihop.enable`

Enable WireGuard multihop. DAITA's useMultihopIfNecessary can also auto-enable.

Type: `boolean`. Default: `true`.

### `services.mullvad-vpn-declarative.settings.obfuscation`

How the WireGuard traffic is disguised where a network blocks or throttles it.

Type: `submodule`. Default: `{ }`.

### `services.mullvad-vpn-declarative.settings.obfuscation.mode`

WireGuard anti-censorship mode. 2026.1 renamed this
from "obfuscation" to "anti-censorship" in the CLI;
the settings.json field stays `obfuscation_settings`.

Type: `one of "auto", "off", "udp2tcp", "shadowsocks", "wireguard-port", "quic", "lwo"`. Default: `"auto"`.

### `services.mullvad-vpn-declarative.settings.obfuscation.shadowsocksPort`

Pin Shadowsocks port. null = daemon picks.

Type: `null or 16 bit unsigned integer; between 0 and 65535 (both inclusive)`. Default: `null`.

### `services.mullvad-vpn-declarative.settings.obfuscation.udp2tcpPort`

Pin UDP2TCP port. null = daemon picks any available.

Type: `null or 16 bit unsigned integer; between 0 and 65535 (both inclusive)`. Default: `null`.

### `services.mullvad-vpn-declarative.settings.obfuscation.wireguardPort`

Pin WireGuard port (when not obfuscated). null = daemon picks.

Type: `null or 16 bit unsigned integer; between 0 and 65535 (both inclusive)`. Default: `null`.

### `services.mullvad-vpn-declarative.settings.relay`

Relay selection constraints — provider, ownership, IP version filters.

Type: `submodule`. Default: `{ }`.

### `services.mullvad-vpn-declarative.settings.relay.entryOwnership`

Ownership filter for the multihop entry relay.

NOTE: no CLI setter in mullvad-cli 2026.1 — parsed
but not applied (see top-level comment).

Type: `one of "any", "rented", "owned"`. Default: `"any"`.

### `services.mullvad-vpn-declarative.settings.relay.entryProviders`

Provider filter for the multihop entry relay. null = any.

NOTE: no CLI setter in mullvad-cli 2026.1 — parsed
but not applied (see top-level comment).

Type: `null or (list of string)`. Default: `null`.

### `services.mullvad-vpn-declarative.settings.relay.ipVersion`

Tunnel IP version constraint.

Type: `one of "any", "v4", "v6"`. Default: `"any"`.

### `services.mullvad-vpn-declarative.settings.relay.ownership`

Filter relays by ownership.
"owned" = Mullvad-owned servers (more privacy).
"rented" = third-party datacenters.
"any" = no filter.

Type: `one of "any", "rented", "owned"`. Default: `"any"`.

### `services.mullvad-vpn-declarative.settings.relay.providers`

Restrict relays to specific hosting providers.
null = any provider. Use `mullvad relay list` to see provider names.

Type: `null or (list of string)`. Default: `null`.

Example:

```nix
[
  "31173"
  "M247"
]
```

### `services.mullvad-vpn-declarative.settings.tunnel`

Settings of the WireGuard tunnel itself.

Type: `submodule`. Default: `{ }`.

### `services.mullvad-vpn-declarative.settings.tunnel.daita`

DAITA, Mullvad's defence against traffic analysis.

Type: `submodule`. Default: `{ }`.

### `services.mullvad-vpn-declarative.settings.tunnel.daita.enable`

DAITA traffic-analysis defense (~5-10% throughput cost).

Type: `boolean`. Default: `true`.

### `services.mullvad-vpn-declarative.settings.tunnel.daita.useMultihopIfNecessary`

Auto-enable multihop when chosen exit doesn't
support DAITA. Inverse of Mullvad's
`daita-direct-only` CLI flag: `true` here sets
daita-direct-only=off.

Type: `boolean`. Default: `true`.

### `services.mullvad-vpn-declarative.settings.tunnel.ipv6`

Carry IPv6 traffic inside the tunnel.

Type: `boolean`. Default: `true`.

### `services.mullvad-vpn-declarative.settings.tunnel.mtu`

Tunnel MTU. null sends nothing, so the daemon keeps the value it has.

Type: `null or signed integer`. Default: `null`. Example: `1280`.

### `services.mullvad-vpn-declarative.settings.tunnel.quantumResistant`

Quantum-resistant key exchange for the tunnel. `auto` leaves the choice to the daemon.

Type: `one of "auto", "on", "off"`. Default: `"on"`.

### `services.mullvad-vpn-declarative.settings.tunnel.rotationIntervalHours`

WireGuard key rotation interval in hours. null sends
nothing, so the daemon keeps the interval it has
(about 7 days on a fresh install).

Type: `null or signed integer`. Default: `null`. Example: `24`.

### `services.mullvad-vpn-declarative.settings.updateDefaultLocation`

Auto-update the daemon's stored "default location" pin as you
connect to different relays. False keeps a stable preferred
location across reconnects.

NOTE: no CLI setter exists in mullvad-cli 2026.1 — this
option is parsed but not applied. Remove once upstream
exposes a setter.

Type: `boolean`. Default: `false`.
