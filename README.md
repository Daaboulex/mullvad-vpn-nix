# mullvad-vpn-nix

[Mullvad VPN](https://mullvad.net/) for NixOS, with the daemon's settings
declared in your configuration instead of set by hand in the app. It is for
people who run Mullvad on several machines and want one configuration to give
every one of them the same settings.

nixpkgs alone gives you `services.mullvad-vpn.enable = true` and nothing more.
Every other setting, such as the DNS blockers, the kill switch, DAITA and
multihop, is state the daemon keeps in `/etc/mullvad-vpn/settings.json`. This
module applies those settings through the `mullvad` command, which the daemon
validates, so a wrong value fails visibly.

It is written against NixOS unstable for `x86_64-linux` and `aarch64-linux`,
and needs the `mullvad` command of version 2026.1 or later. The packages come
straight from nixpkgs, with no overlay and no version pin. The repository's
checks only evaluate the two modules. No check starts the daemon, so none
proves that a setting takes effect.

## Install

Add the flake:

```nix
{
  inputs.mullvad-vpn = {
    url = "github:Daaboulex/mullvad-vpn-nix";
    inputs.nixpkgs.follows = "nixpkgs";
  };
}
```

Then import the module and switch it on:

```nix
{
  imports = [ inputs.mullvad-vpn.nixosModules.default ];
  services.mullvad-vpn-declarative.enable = true;
}
```

That turns on nixpkgs' `services.mullvad-vpn` with its desktop app, and loads
the `wireguard` kernel module before the daemon starts. Log in once on each
machine with `mullvad account login`, which stays a manual step.

The module applies its defaults too. With nothing else set it turns on
auto-connect, multihop, DAITA, quantum-resistant key exchange and tracker
blocking.

## Settings

```nix
{
  services.mullvad-vpn-declarative.settings = {
    autoConnect = true;
    lockdownMode = true;
    dns.blockAds = true;
    dns.blockTrackers = true;
    obfuscation.wireguardPort = 51820;
    tunnel.daita.enable = true;
  };
}
```

The settings are applied again on every `nixos-rebuild switch`, so a change
made in the app or with the `mullvad` command is reverted at the next switch.

The ones you are likely to set first, all under `settings`:

| Option | What it is for |
|---|---|
| `autoConnect` | Connect when the daemon starts |
| `lockdownMode` | Block all traffic while disconnected, the kill switch |
| `dns.blockAds`, `dns.blockTrackers`, `dns.blockMalware` | Content blockers on Mullvad's DNS |
| `dns.mode`, `dns.customServers` | Use your own DNS servers instead of Mullvad's |
| `multihop.enable` | Route through an entry relay, then an exit relay |
| `tunnel.daita.enable` | DAITA, Mullvad's defence against traffic analysis |
| `obfuscation.mode` | How the traffic is disguised where a network blocks it |

Every option, with its type and default: [docs/OPTIONS.md](docs/OPTIONS.md).

The relay location is not one of the module's settings, so a switch leaves it
alone. Choose it with `mullvad relay set location se`, here Sweden.
`mullvad status` shows the connection, and `mullvad connect` and
`mullvad disconnect` work as they always do.

## The desktop app's preferences

A Home Manager module installs the app for the user and seeds its preferences.
Import it, then set `programs.mullvad-vpn-gui.enable = true` in the user's
Home Manager configuration:

```nix
{
  home-manager.sharedModules = [ inputs.mullvad-vpn.homeModules.default ];
}
```

The app writes `~/.config/Mullvad VPN/gui_settings.json` itself. So
`programs.mullvad-vpn-gui.settings` seeds that file once, when it is absent,
and the app owns it after that. Delete the file to seed it again.
`programs.mullvad-vpn-gui.autostart` launches the app when the session starts.

## Known limits

- `updateDefaultLocation`, `relay.entryProviders` and `relay.entryOwnership`
  are accepted but not applied: the `mullvad` command has no setter for them.
- `tunnel.mtu` and `tunnel.rotationIntervalHours` run no command while they
  are `null`, so the module does not reset a value the daemon already holds.
- The content blockers apply only with Mullvad's DNS. `dns.mode = "custom"`
  with no `dns.customServers` falls back to Mullvad's DNS.
- Per-relay overrides and custom relay lists stay per machine, like the
  login: `mullvad relay override` and `mullvad custom-list`.
- OpenVPN bridges are deprecated and not covered. Set `obfuscation.mode` to
  `"udp2tcp"` or `"shadowsocks"` instead.
- Mullvad Browser's encrypted DNS proxy is a browser feature and not covered.

## When a setting does not take effect

`mullvad-apply-settings.service` applies the settings once the daemon is up.
It tries every setting, logs each one that fails with the command's own error,
and then fails itself. `systemctl --failed` lists it, and
`journalctl -u mullvad-apply-settings.service` shows the log.

The service gives up when the daemon has not answered within 30 seconds.
Before it changes anything it copies the live settings to
`/etc/mullvad-vpn/settings.json.nixos-bak`, to compare or restore by hand.

## More

- [docs/DESIGN.md](docs/DESIGN.md): what each setting runs, what is left out
- [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md): the dev shell, the checks, CI

## License

MIT for the packaging code in this repo. Mullvad VPN itself is **GPL-3.0**.
See [the upstream repo](https://github.com/mullvad/mullvadvpn-app) for the
application source and license. The Mullvad daemon and GUI packages come from
nixpkgs; this repo adds only the declarative configuration, with no overlay
and no version pin.
