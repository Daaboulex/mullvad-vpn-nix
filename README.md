# mullvad-vpn-nix

<!-- BEGIN generated:badges -->
[![CI](https://github.com/Daaboulex/mullvad-vpn-nix/actions/workflows/ci.yml/badge.svg)](https://github.com/Daaboulex/mullvad-vpn-nix/actions/workflows/ci.yml)
[![NixOS unstable](https://img.shields.io/badge/NixOS-unstable-78C0E8?logo=nixos&logoColor=white)](https://nixos.org)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](./LICENSE)
<!-- END generated:badges -->

[Mullvad VPN](https://mullvad.net/) packaged for NixOS — declarative daemon settings and Home Manager GUI preferences.

<!-- BEGIN generated:upstream -->
## Upstream

| | |
|---|---|
| **Project** | [mullvad/mullvadvpn-app](https://github.com/mullvad/mullvadvpn-app) |
| **License** | GPL-3.0 |
| **Tracked** | via nixpkgs (no independent pin) |

<!-- END generated:upstream -->

## Why this exists

Vanilla nixpkgs gives you `services.mullvad-vpn.enable = true;` and that's it. Every other Mullvad setting (DNS blockers, kill-switch, DAITA, multihop) is **imperative state held inside the daemon** at `/etc/mullvad-vpn/settings.json`. On multi-host setups, you'd configure each host separately via GUI/CLI.

This module fixes that by patching `settings.json` declaratively from your NixOS config, so a single host config replicates across all your machines.

Settings are applied through the `mullvad` CLI, which the daemon validates, so an invalid value errors visibly instead of silently corrupting `settings.json`. The packages come straight from nixpkgs: this repo carries no overlay and pins no version.

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
      lockdownMode = true;
      dns = {
        mode = "default";
        blockAds = true;
        blockTrackers = true;
      };
      obfuscation.wireguardPort = 51820;
      tunnel.daita.enable = true;
    };
  };
}
```

### Home Manager module (GUI preferences)

```nix
{
  programs.mullvad-vpn-gui = {
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
2. A `mullvad-apply-settings.service` oneshot runs after the daemon
3. It backs up the live `settings.json` to `settings.json.nixos-bak`
4. It waits for the daemon's IPC to come up, then applies each declared setting through the `mullvad <subcommand> set` CLI (DNS, relay provider, kill switch, auto-connect, ...)
5. Critical toggles (kill switch, auto-connect) apply through `run_critical`, so the unit fails loudly if they do not take effect

Idempotent — re-runs on every `nixos-rebuild switch` so GUI/CLI drift gets reverted.

<!-- BEGIN generated:options -->
## Options

NixOS module: `services.mullvad-vpn-declarative.*` (see [`nixos-module.nix`](nixos-module.nix))

Home Manager module: `programs.mullvad-vpn-gui.*` (see [`hm-module.nix`](hm-module.nix))
<!-- END generated:options -->

## License

MIT for the packaging code in this repo. Mullvad VPN itself is **GPL-3.0** — see [the upstream repo](https://github.com/mullvad/mullvadvpn-app) for the application source and license. The Mullvad daemon and GUI packages come from nixpkgs; this repo adds only the declarative configuration, with no overlay and no version pin.

<!-- BEGIN generated:footer -->
<!-- END generated:footer -->
