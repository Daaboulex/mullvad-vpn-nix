# mullvad-vpn-nix

<!-- BEGIN generated:badges -->
[![NixOS unstable](https://img.shields.io/badge/NixOS-unstable-78C0E8?logo=nixos&logoColor=white)](https://nixos.org)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](./LICENSE)
<!-- END generated:badges -->

[Mullvad VPN](https://mullvad.net/) packaged for NixOS — declarative daemon settings, Home Manager GUI prefs, upstream version pin.

<!-- BEGIN generated:upstream -->
## Upstream

| | |
|---|---|
| **Project** | [mullvad/mullvadvpn-app](https://github.com/mullvad/mullvadvpn-app) |
| **License** | GPL-3.0 |
| **Tracked** | GitHub releases |
<!-- END generated:upstream -->

## Why this exists

Vanilla nixpkgs gives you `services.mullvad-vpn.enable = true;` and that's it. Every other Mullvad setting (DNS blockers, kill-switch, DAITA, multihop) is **imperative state held inside the daemon** at `/etc/mullvad-vpn/settings.json`. On multi-host setups, you'd configure each host separately via GUI/CLI.

This module fixes that by patching `settings.json` declaratively from your NixOS config, so a single host config replicates across all your machines.

The CLI in 2025.14 was broken (`mullvad <cmd> get|set` crashed with `missing bridge settings`), so the overlay also bumps to 2026.1 where the CLI works again.

<!-- BEGIN generated:installation -->
## Installation

Add as a flake input:

```nix
{
  inputs.mullvad-vpn = {
    url = "github:Daaboulex/mullvad-vpn-nix";
    inputs.nixpkgs.follows = "nixpkgs";
  };
}
```

Then add the overlay:

```nix
nixpkgs.overlays = [ inputs.mullvad-vpn.overlays.default ];
```

Import the NixOS module:

```nix
imports = [ inputs.mullvad-vpn.nixosModules.default ];
```

Import the Home Manager module:

```nix
home-manager.sharedModules = [ inputs.mullvad-vpn.homeManagerModules.default ];
```
<!-- END generated:installation -->

## Setting reference

### Daemon (`services.mullvad-vpn-declarative.settings`)

| Option | Default | What it does |
|--------|---------|--------------|
| `autoConnect` | `true` | Connect on daemon start |
| `lockdownMode` | `false` | Block all traffic when disconnected (kill-switch) |
| `lan` | `true` | Allow local-network sharing while connected |
| `betaProgram` | `false` | Beta update notifications |
| `dns.mode` | `"default"` | `"default"` = Mullvad resolvers (with optional blockers), `"custom"` = your IPs |
| `dns.blockAds` | `false` | Block ad-serving domains |
| `dns.blockTrackers` | `true` | Block tracking domains (Mullvad daemon default) |
| `dns.blockMalware` | `false` | Block known-malware domains |
| `dns.blockAdultContent` | `false` | Block adult-content domains |
| `dns.blockGambling` | `false` | Block gambling domains |
| `dns.blockSocialMedia` | `false` | Block social-media domains |
| `dns.customServers` | `[ ]` | DNS IPs when mode = `"custom"` |
| `obfuscation.mode` | `"auto"` | `auto` / `off` / `udp2tcp` / `shadowsocks` (replaces deprecated OpenVPN bridges) |
| `multihop.enable` | `true` | Route through entry-then-exit relay |
| `apiAccess.direct` | `true` | Direct API access |
| `apiAccess.mullvadBridges` | `true` | API via bridge relay (when direct is blocked) |
| `apiAccess.encryptedDnsProxy` | `true` | API via DoH (when direct is blocked) |
| `tunnel.quantumResistant` | `"on"` | Post-quantum key exchange |
| `tunnel.ipv6` | `true` | IPv6 inside tunnel |
| `tunnel.daita.enable` | `true` | DAITA (Defense Against AI-guided Traffic Analysis) |
| `tunnel.daita.useMultihopIfNecessary` | `true` | Auto-multihop when chosen exit doesn't support DAITA |

### GUI (`programs.mullvad-vpn-gui.settings`)

| Option | Default | What it does |
|--------|---------|--------------|
| `preferredLocale` | `"system"` | GUI language |
| `autoConnect` | `false` | GUI-level auto-connect (when window opens; usually use daemon-level instead) |
| `enableSystemNotifications` | `true` | Status notifications |
| `monochromaticIcon` | `true` | Tray icon style |
| `startMinimized` | `true` | Start in tray, not as window |
| `unpinnedWindow` | `true` | Window movable/resizable freely |
| `animateMap` | `false` | Map animations (off saves CPU) |

## What's NOT in this module (intentionally)

- **OpenVPN bridges** — deprecated; use `obfuscation.mode = "udp2tcp"` or `"shadowsocks"`
- **Per-relay overrides / custom relay lists** — per-device state, use `mullvad relay override` / `mullvad custom-list` CLI
- **Account login** — sensitive, `mullvad account login` stays manual per device
- **Encrypted DNS Proxy (browser)** — Mullvad Browser feature, separate from the VPN daemon

## Usage

Enable the declarative NixOS module:

```nix
{
  services.mullvad-vpn-declarative = {
    enable = true;
    settings = {
      autoConnect = true;
      killSwitch = true;
      daita = true;
      dns = {
        mode = "default";
        blockAds = true;
        blockTrackers = true;
      };
      relay = {
        country = "se";
        tunnel.wireguard.port = 51820;
      };
    };
  };
}
```

### Home Manager module (GUI preferences)

```nix
{
  programs.mullvad-vpn = {
    enable = true;
  };
}
```

### CLI

```bash
mullvad status                   # connection status
mullvad relay set location se    # switch to Sweden
mullvad connect                  # connect
mullvad disconnect               # disconnect
```
## Development

```bash
nix develop
nix flake check --no-build
nix build
nix fmt
```

## How it works (under the hood)

1. `services.mullvad-vpn.enable = true` starts `mullvad-daemon.service` (vanilla NixOS)
2. New `mullvad-apply-settings.service` oneshot runs after the daemon
3. It checks `settings_version=15` (refuses to touch unknown schemas)
4. Stops the daemon, backs up `settings.json` to `.nixos-bak`
5. `jq` patches each declared field at its exact JSON path
6. Validates the result with `jq -e .` (rolls back on parse failure)
7. Restarts the daemon

Idempotent — re-runs on every `nixos-rebuild switch` so GUI/CLI drift gets reverted.

<!-- BEGIN generated:options -->
<!-- END generated:options -->

## License

MIT for the packaging code in this repo. Mullvad VPN itself is **GPL-3.0** — see [the upstream repo](https://github.com/mullvad/mullvadvpn-app) for the application source and license. This repo wraps the prebuilt .deb that Mullvad publishes; it does not include or modify the Mullvad source code.

<!-- BEGIN generated:footer -->
---

*Maintained as part of the [Daaboulex](https://github.com/Daaboulex) NixOS ecosystem.*
<!-- END generated:footer -->
