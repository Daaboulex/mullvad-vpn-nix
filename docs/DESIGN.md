# Design

Why the modules are built the way they are, and what each setting does. The
[README](../README.md) says how to use them.

## Why the settings go through the `mullvad` command

Vanilla nixpkgs gives you `services.mullvad-vpn.enable = true;` and that is it.
Every other Mullvad setting (DNS blockers, kill-switch, DAITA, multihop) is
imperative state held inside the daemon at `/etc/mullvad-vpn/settings.json`. On
multi-host setups, you would configure each host separately via GUI or CLI.

This module fixes that by applying the settings from your NixOS config through
the `mullvad` CLI, so a single host config replicates across all your machines.

Settings are applied through the `mullvad` CLI, which the daemon validates, so
an invalid value errors visibly instead of silently corrupting `settings.json`.
The packages come straight from nixpkgs: this repo carries no overlay and pins
no version.

## How a switch applies them

The NixOS module is [`nixos-module.nix`](../nixos-module.nix), under
`services.mullvad-vpn-declarative.*`.

1. `services.mullvad-vpn.enable = true` starts `mullvad-daemon.service`
   (vanilla NixOS).
2. A `mullvad-apply-settings.service` oneshot runs after the daemon.
3. It waits up to 30 seconds for the daemon's IPC to come up.
4. It backs up the live `settings.json` to `settings.json.nixos-bak`, then
   applies each declared setting through the `mullvad <subcommand> set` CLI
   (DNS, relay provider, kill switch, auto-connect and the rest).
5. Every setting is attempted. Any that fails is logged with the CLI's own
   error and the unit exits non-zero after the pass, so `systemctl --failed`
   shows a setting that did not take effect.

It is idempotent: it re-runs on every `nixos-rebuild switch`, so GUI or CLI
drift gets reverted.

What the code adds to those steps:

- The wait asks `mullvad status` once a second, because `settings.json`
  appears before the IPC is ready. If the daemon answers and `settings.json`
  is still missing, the service stops without applying anything.
- The unit names the daemon in `wants`, not only in `after`, so the daemon is
  pulled in.
- The unit has no `RemainAfterExit` and lists the apply script in
  `restartTriggers`. That is what makes it run again on a switch instead of
  being skipped as already done.
- The log lines start with `[mullvad-apply]`.

## What enabling the module also does

Enabling the module also enables the desktop app
(`services.mullvad-vpn.gui.enable`), loads the `wireguard` kernel module, and
starts `mullvad-daemon.service` only after `systemd-modules-load.service`.

The desktop app is enabled because it no longer ships inside the daemon
package. nixpkgs splits the daemon (`pkgs.mullvad`) from the desktop app
(`pkgs.mullvad-vpn`). `services.mullvad-vpn-declarative.package` is the daemon
package, which also carries the `mullvad` CLI the apply script drives. The app
package is chosen by `services.mullvad-vpn.gui.package`.

The `wireguard` module is loaded because nixpkgs' `services.mullvad-vpn` only
adds `tun`. Without `wireguard` loaded the daemon falls back to userspace
WireGuard, and that fallback has a race. It creates the TUN device and at once
tries to set an IPv6 address, before the kernel has registered
`/proc/sys/net/ipv6/conf/wg-mullvad/`. The daemon reports
`Failed to set IPv6 address`, enters its error state and blocks all traffic,
which looks like the WiFi dying on a rebuild. The kernel's WireGuard creates
that sysctl tree together with the link, so it has no race. The fix belongs in
nixpkgs' own module, where it is one line. The line here is a harmless
duplicate once it lands there.

The daemon is ordered after `systemd-modules-load.service`, and requires it,
because `boot.kernelModules` only puts a module on the load list and orders no
service. Without the ordering, on a cold boot the daemon can start before the
modules are loaded, hit the userspace fallback and block traffic for that boot.

The module also installs an icon. nixpkgs' `mullvad-vpn` ships its SVG only
under `share/mullvad-vpn/resources`, while its desktop entry asks for
`Icon=mullvad-vpn`. The module links the SVG into
`share/icons/hicolor/scalable/apps` until nixpkgs installs it there itself.

## What each setting runs

All under `services.mullvad-vpn-declarative.settings`.

| Option | Default | What it does | Command |
|---|---|---|---|
| `autoConnect` | `true` | Connect on daemon start | `mullvad auto-connect set on` or `off` |
| `lockdownMode` | `false` | Block all traffic when disconnected (kill-switch) | `mullvad lockdown-mode set on` or `off` |
| `lan` | `true` | Allow local-network sharing while connected | `mullvad lan set allow` or `block` |
| `betaProgram` | `false` | Beta update notifications | `mullvad beta-program set on` or `off` |
| `updateDefaultLocation` | `false` | Update the stored default location as you connect to different relays | none: parsed but not applied, the `mullvad` CLI has no setter |
| `dns.mode` | `"default"` | `"default"` = Mullvad resolvers (with optional blockers), `"custom"` = your IPs | `mullvad dns set default` or `mullvad dns set custom` |
| `dns.blockAds` | `false` | Block ad-serving domains | `--block-ads` on `mullvad dns set default` |
| `dns.blockTrackers` | `true` | Block tracking domains (Mullvad daemon default) | `--block-trackers` on `mullvad dns set default` |
| `dns.blockMalware` | `false` | Block known-malware domains | `--block-malware` on `mullvad dns set default` |
| `dns.blockAdultContent` | `false` | Block adult-content domains | `--block-adult-content` on `mullvad dns set default` |
| `dns.blockGambling` | `false` | Block gambling domains | `--block-gambling` on `mullvad dns set default` |
| `dns.blockSocialMedia` | `false` | Block social-media domains | `--block-social-media` on `mullvad dns set default` |
| `dns.customServers` | `[ ]` | DNS IPs when mode = `"custom"` | the addresses given to `mullvad dns set custom` |
| `obfuscation.mode` | `"auto"` | `auto` / `off` / `udp2tcp` / `shadowsocks` / `wireguard-port` / `quic` / `lwo` (replaces deprecated OpenVPN bridges) | `mullvad anti-censorship set mode` |
| `obfuscation.udp2tcpPort` | `null` | UDP2TCP port. `null` = daemon picks | `mullvad anti-censorship set udp2tcp --port`, with `any` for `null` |
| `obfuscation.shadowsocksPort` | `null` | Shadowsocks port. `null` = daemon picks | `mullvad anti-censorship set shadowsocks --port`, with `any` for `null` |
| `obfuscation.wireguardPort` | `null` | WireGuard port. `null` = daemon picks | `mullvad anti-censorship set wireguard-port --port`, with `any` for `null` |
| `multihop.enable` | `true` | Route through entry-then-exit relay | `mullvad relay set multihop on` or `off` |
| `relay.ipVersion` | `"any"` | Tunnel IP version: `any` / `v4` / `v6` | `mullvad relay set ip-version` |
| `relay.providers` | `null` | Restrict relays to these hosting providers. `null` = any provider | `mullvad relay set provider`, with `any` for `null` |
| `relay.ownership` | `"any"` | Relay ownership filter: `any` / `rented` / `owned` | `mullvad relay set ownership` |
| `relay.entryProviders` | `null` | Provider filter for the multihop entry relay | none: parsed but not applied, the `mullvad` CLI has no setter |
| `relay.entryOwnership` | `"any"` | Ownership filter for the multihop entry relay | none: parsed but not applied, the `mullvad` CLI has no setter |
| `apiAccess.direct` | `true` | Direct API access | `mullvad api-access enable 1` or `disable 1` |
| `apiAccess.mullvadBridges` | `true` | API via bridge relay (when direct is blocked) | `mullvad api-access enable 2` or `disable 2` |
| `apiAccess.encryptedDnsProxy` | `true` | API via DoH (when direct is blocked) | `mullvad api-access enable 3` or `disable 3` |
| `tunnel.quantumResistant` | `"on"` | Post-quantum key exchange | `mullvad tunnel set quantum-resistant` |
| `tunnel.ipv6` | `true` | IPv6 inside tunnel | `mullvad tunnel set ipv6 on` or `off` |
| `tunnel.mtu` | `null` | Tunnel MTU | `mullvad tunnel set mtu`, and no command for `null` |
| `tunnel.rotationIntervalHours` | `null` | WireGuard key rotation interval in hours | `mullvad tunnel set rotation-interval`, and no command for `null` |
| `tunnel.daita.enable` | `true` | DAITA (Defense Against AI-guided Traffic Analysis) | `mullvad tunnel set daita on` or `off` |
| `tunnel.daita.useMultihopIfNecessary` | `true` | Auto-multihop when chosen exit doesn't support DAITA | `mullvad tunnel set daita-direct-only`, inverted: `true` sets `off` |

Notes on the table:

- The DNS blocker defaults match the daemon's own defaults at settings version
  15: only trackers are blocked, every other blocker is opt-in.
- With `dns.mode = "custom"` the blockers are not passed. With
  `dns.mode = "custom"` and an empty `dns.customServers` the module runs
  `mullvad dns set default` with the blockers instead, to avoid a CLI error.
- The CLI renamed obfuscation to anti-censorship in 2026.1. The field in
  `settings.json` is still `obfuscation_settings`, and the option keeps the
  old name.
- `tunnel.mtu` and `tunnel.rotationIntervalHours` run no command while they
  are `null`. The daemon keeps whatever value it holds, its own default or one
  set earlier.
- The numbers after `mullvad api-access` are the built-in method indices: 1 is
  Direct, 2 is Mullvad Bridges, 3 is Encrypted DNS Proxy.
- `mullvad relay list` shows the provider names `relay.providers` takes.

## Settings with no command

Three options are parsed but not applied, and stay at the daemon's default
until upstream exposes a setter. The module states this for `mullvad` CLI
2026.1.

- `updateDefaultLocation` has no CLI command.
- `relay.entryProviders` has none either: `mullvad relay set entry` supports
  `location` and `custom-list` only.
- `relay.entryOwnership` has the same limitation.

## The desktop app's preferences

The Home Manager module is [`hm-module.nix`](../hm-module.nix), under
`programs.mullvad-vpn-gui.*`.

The GUI writes `~/.config/Mullvad VPN/gui_settings.json` itself, so these
values seed that file once, when it is absent, and the GUI owns it after that.
Delete the file to re-seed it from the module. These are GUI-only preferences.
They do not change connection or privacy behavior.

All under `programs.mullvad-vpn-gui.settings`:

| Option | Default | What it does |
|---|---|---|
| `preferredLocale` | `"system"` | GUI language |
| `autoConnect` | `false` | GUI-level auto-connect (when window opens; usually use daemon-level instead) |
| `enableSystemNotifications` | `true` | Status notifications |
| `monochromaticIcon` | `true` | Tray icon style |
| `startMinimized` | `true` | Start in tray, not as window |
| `unpinnedWindow` | `true` | Window movable/resizable freely |
| `animateMap` | `false` | Map animations (off saves CPU) |

The seeded file also carries three keys the module gives no option for:
`browsedForSplitTunnelingApplications` as an empty list, and
`changelogDisplayedForVersion` and `updateDismissedForVersion` as empty
strings.

`programs.mullvad-vpn-gui.autostart` links the package's own desktop entry
into the autostart directory. The link is forced, because a desktop
environment or the user may already have linked the same entry there.

## What is left out, on purpose

- OpenVPN bridges are deprecated. Use `obfuscation.mode = "udp2tcp"` or
  `"shadowsocks"`.
- Per-relay overrides and custom relay lists are per-device state. Use the
  `mullvad relay override` and `mullvad custom-list` CLI.
- Account login is sensitive. `mullvad account login` stays manual per device.
- Encrypted DNS Proxy (browser) is a Mullvad Browser feature, separate from
  the VPN daemon.
