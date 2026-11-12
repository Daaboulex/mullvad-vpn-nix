# Development

```bash
nix develop
nix flake check --no-build
nix build
nix fmt
```

`nix build` builds `packages.default`, which is nixpkgs' `mullvad-vpn`
unchanged. `packages.mullvad-vpn` is the same package. The flake is declared
for `x86_64-linux` and `aarch64-linux` and follows `nixos-unstable`.

The dev shell, the formatter and the commit hooks come from
`inputs.std.flakeModules.base`, the base module of
`github:Daaboulex/nix-packaging-standard` on its `release` branch.
[`.envrc`](../.envrc) loads the shell through direnv. Run `direnv allow` once
per clone.

## Checks

[`flake.nix`](../flake.nix) declares two checks of its own. Each instantiates
a module with its switch on, so that activation errors surface.

- `checks.module-eval-nixos` instantiates
  [`nixos-module.nix`](../nixos-module.nix) with
  `services.mullvad-vpn-declarative.enable = true`.
- `checks.module-eval-hm` instantiates [`hm-module.nix`](../hm-module.nix)
  with `programs.mullvad-vpn-gui.enable = true`.

Neither starts the daemon or runs the apply script.

## CI

[`ci.yml`](../.github/workflows/ci.yml) runs the standard's package CI
workflow on a push to `main` or `master`, on a pull request and on a manual
dispatch.

[`maintenance.yml`](../.github/workflows/maintenance.yml) runs the standard's
package maintenance workflow on a schedule. It runs weekly unless the
repository variable `MAINTENANCE_CADENCE` says `daily` or `biweekly`.

## Where the version comes from

| | |
|---|---|
| Project | [mullvad/mullvadvpn-app](https://github.com/mullvad/mullvadvpn-app) |
| License | GPL-3.0 |
| Tracked | via nixpkgs (no independent pin) |

[`update.json`](../.github/update.json) states the same: its upstream type is
`none`, so nothing here follows an upstream release. A new Mullvad version
arrives with nixpkgs.
