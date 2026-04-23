# nixos-module.nix — Mullvad VPN daemon + declarative settings via
# `mullvad <subcmd> set` calls.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.mullvad-vpn-declarative;
  s = cfg.settings;

  onOff = v: if v then "on" else "off";
  allowBlock = v: if v then "allow" else "block";
  portArg = v: if v == null then "any" else toString v;

  # Translate declarative settings to a sequence of `mullvad <subcmd>
  # set` invocations. The daemon validates each call and idempotent
  # writes are no-ops — safe to re-run on every rebuild.
  #
  # Options without a direct CLI setter (see module-level comments) are
  # intentionally skipped here; the applyScript comment block below
  # spells out which ones.
  dnsBlockFlags = lib.concatStringsSep " " (
    lib.optional s.dns.blockAds "--block-ads"
    ++ lib.optional s.dns.blockTrackers "--block-trackers"
    ++ lib.optional s.dns.blockMalware "--block-malware"
    ++ lib.optional s.dns.blockAdultContent "--block-adult-content"
    ++ lib.optional s.dns.blockGambling "--block-gambling"
    ++ lib.optional s.dns.blockSocialMedia "--block-social-media"
  );

  dnsCmd =
    if s.dns.mode == "default" then
      "mullvad dns set default ${dnsBlockFlags}"
    else
      # Custom DNS requires at least one address; if user leaves the list
      # empty we fall through to default to avoid a CLI error.
      (
        if s.dns.customServers == [ ] then
          "mullvad dns set default ${dnsBlockFlags}"
        else
          "mullvad dns set custom ${lib.concatMapStringsSep " " lib.escapeShellArg s.dns.customServers}"
      );

  providerCmd =
    if s.relay.providers == null then
      "mullvad relay set provider any"
    else
      "mullvad relay set provider ${lib.concatMapStringsSep " " lib.escapeShellArg s.relay.providers}";

  applyScript = pkgs.writeShellApplication {
    name = "mullvad-apply-settings";
    runtimeInputs = [
      cfg.package
      pkgs.systemd
      pkgs.coreutils
    ];
    text = ''
      set -eu
      SETTINGS=/etc/mullvad-vpn/settings.json
      BACKUP=/etc/mullvad-vpn/settings.json.nixos-bak

      log() { echo "[mullvad-apply] $*"; }
      # Each set is idempotent, but we don't want a single bad call to
      # abort the batch — log and continue so operators can see the
      # specific failure without losing every later setting.
      run() {
        if ! "$@"; then
          log "WARN: failed: $*"
        fi
      }

      # Wait up to 30s for the daemon to create settings.json on first
      # boot. Without this, on a fresh install the file doesn't exist
      # when this unit runs.
      for _ in $(seq 1 30); do
        [ -f "$SETTINGS" ] && break
        sleep 1
      done
      if [ ! -f "$SETTINGS" ]; then
        log "settings.json never appeared after 30s — daemon failed to start; aborting"
        exit 1
      fi

      # Snapshot live settings so operators can diff / restore by hand.
      cp -a "$SETTINGS" "$BACKUP"

      log "applying settings via mullvad CLI"

      # Top-level toggles
      run mullvad auto-connect set ${onOff s.autoConnect}
      run mullvad lockdown-mode set ${onOff s.lockdownMode}
      run mullvad lan set ${allowBlock s.lan}
      run mullvad beta-program set ${onOff s.betaProgram}

      # DNS
      run ${dnsCmd}

      # Anti-censorship (formerly "obfuscation" in settings.json)
      run mullvad anti-censorship set mode ${s.obfuscation.mode}
      run mullvad anti-censorship set udp2tcp --port ${portArg s.obfuscation.udp2tcpPort}
      run mullvad anti-censorship set shadowsocks --port ${portArg s.obfuscation.shadowsocksPort}
      run mullvad anti-censorship set wireguard-port --port ${portArg s.obfuscation.wireguardPort}

      # Relay constraints
      run mullvad relay set multihop ${onOff s.multihop.enable}
      run mullvad relay set ip-version ${s.relay.ipVersion}
      run mullvad relay set ownership ${s.relay.ownership}
      run ${providerCmd}

      # Tunnel
      run mullvad tunnel set quantum-resistant ${s.tunnel.quantumResistant}
      run mullvad tunnel set ipv6 ${onOff s.tunnel.ipv6}
      run mullvad tunnel set daita ${onOff s.tunnel.daita.enable}
      # daita-direct-only=on is the inverse of useMultihopIfNecessary=true
      run mullvad tunnel set daita-direct-only ${onOff (!s.tunnel.daita.useMultihopIfNecessary)}
      ${lib.optionalString (s.tunnel.mtu != null) ''
        run mullvad tunnel set mtu ${toString s.tunnel.mtu}
      ''}
      ${lib.optionalString (s.tunnel.rotationIntervalHours != null) ''
        run mullvad tunnel set rotation-interval ${toString s.tunnel.rotationIntervalHours}
      ''}

      # API access methods (built-in indices: 1=Direct, 2=Mullvad Bridges,
      # 3=Encrypted DNS Proxy). `enable` / `disable` are idempotent.
      run mullvad api-access ${if s.apiAccess.direct then "enable" else "disable"} 1
      run mullvad api-access ${if s.apiAccess.mullvadBridges then "enable" else "disable"} 2
      run mullvad api-access ${if s.apiAccess.encryptedDnsProxy then "enable" else "disable"} 3

      log "done"
    '';
  };
in
{
  options.services.mullvad-vpn-declarative = {
    enable = lib.mkEnableOption "Mullvad VPN daemon with declarative settings";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.mullvad-vpn;
      defaultText = lib.literalExpression "pkgs.mullvad-vpn";
      description = "The mullvad-vpn package. Override via overlay or here directly.";
    };

    settings = lib.mkOption {
      description = ''
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
      '';
      default = { };
      type = lib.types.submodule {
        options = {
          autoConnect = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Connect automatically on daemon start.";
          };
          lockdownMode = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Block all traffic when VPN disconnected (kill-switch).";
          };
          lan = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Allow LAN sharing while connected.";
          };
          betaProgram = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Opt into beta update notifications.";
          };
          updateDefaultLocation = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = ''
              Auto-update the daemon's stored "default location" pin as you
              connect to different relays. False keeps a stable preferred
              location across reconnects.

              NOTE: no CLI setter exists in mullvad-cli 2026.1 — this
              option is parsed but not applied. Remove once upstream
              exposes a setter.
            '';
          };

          dns = lib.mkOption {
            default = { };
            type = lib.types.submodule {
              options = {
                mode = lib.mkOption {
                  type = lib.types.enum [
                    "default"
                    "custom"
                  ];
                  default = "default";
                };
                # Defaults match Mullvad daemon defaults (settings_version=15):
                # only trackers blocked by default. All other blockers are opt-in.
                blockAds = lib.mkOption {
                  type = lib.types.bool;
                  default = false;
                };
                blockTrackers = lib.mkOption {
                  type = lib.types.bool;
                  default = true;
                };
                blockMalware = lib.mkOption {
                  type = lib.types.bool;
                  default = false;
                };
                blockAdultContent = lib.mkOption {
                  type = lib.types.bool;
                  default = false;
                };
                blockGambling = lib.mkOption {
                  type = lib.types.bool;
                  default = false;
                };
                blockSocialMedia = lib.mkOption {
                  type = lib.types.bool;
                  default = false;
                };
                customServers = lib.mkOption {
                  type = lib.types.listOf lib.types.str;
                  default = [ ];
                  description = ''
                    Custom DNS servers (only applied when `mode = "custom"`).
                    Empty list + `mode = "custom"` falls back to default
                    DNS to avoid a CLI error.
                  '';
                };
              };
            };
          };

          obfuscation = lib.mkOption {
            default = { };
            type = lib.types.submodule {
              options = {
                mode = lib.mkOption {
                  type = lib.types.enum [
                    "auto"
                    "off"
                    "udp2tcp"
                    "shadowsocks"
                    "wireguard-port"
                    "quic"
                    "lwo"
                  ];
                  default = "auto";
                  description = ''
                    WireGuard anti-censorship mode. 2026.1 renamed this
                    from "obfuscation" to "anti-censorship" in the CLI;
                    the settings.json field stays `obfuscation_settings`.
                  '';
                };
                udp2tcpPort = lib.mkOption {
                  type = lib.types.nullOr lib.types.port;
                  default = null;
                  description = "Pin UDP2TCP port. null = daemon picks any available.";
                };
                shadowsocksPort = lib.mkOption {
                  type = lib.types.nullOr lib.types.port;
                  default = null;
                  description = "Pin Shadowsocks port. null = daemon picks.";
                };
                wireguardPort = lib.mkOption {
                  type = lib.types.nullOr lib.types.port;
                  default = null;
                  description = "Pin WireGuard port (when not obfuscated). null = daemon picks.";
                };
              };
            };
          };

          multihop = lib.mkOption {
            default = { };
            type = lib.types.submodule {
              options.enable = lib.mkOption {
                type = lib.types.bool;
                default = true;
                description = "Enable WireGuard multihop. DAITA's useMultihopIfNecessary can also auto-enable.";
              };
            };
          };

          relay = lib.mkOption {
            default = { };
            description = "Relay selection constraints — provider, ownership, IP version filters.";
            type = lib.types.submodule {
              options = {
                ipVersion = lib.mkOption {
                  type = lib.types.enum [
                    "any"
                    "v4"
                    "v6"
                  ];
                  default = "any";
                  description = "Tunnel IP version constraint.";
                };
                providers = lib.mkOption {
                  type = lib.types.nullOr (lib.types.listOf lib.types.str);
                  default = null;
                  example = [
                    "31173"
                    "M247"
                  ];
                  description = ''
                    Restrict relays to specific hosting providers.
                    null = any provider. Use `mullvad relay list` to see provider names.
                  '';
                };
                ownership = lib.mkOption {
                  type = lib.types.enum [
                    "any"
                    "rented"
                    "owned"
                  ];
                  default = "any";
                  description = ''
                    Filter relays by ownership.
                    "owned" = Mullvad-owned servers (more privacy).
                    "rented" = third-party datacenters.
                    "any" = no filter.
                  '';
                };
                entryProviders = lib.mkOption {
                  type = lib.types.nullOr (lib.types.listOf lib.types.str);
                  default = null;
                  description = ''
                    Provider filter for the multihop entry relay. null = any.

                    NOTE: no CLI setter in mullvad-cli 2026.1 — parsed
                    but not applied (see top-level comment).
                  '';
                };
                entryOwnership = lib.mkOption {
                  type = lib.types.enum [
                    "any"
                    "rented"
                    "owned"
                  ];
                  default = "any";
                  description = ''
                    Ownership filter for the multihop entry relay.

                    NOTE: no CLI setter in mullvad-cli 2026.1 — parsed
                    but not applied (see top-level comment).
                  '';
                };
              };
            };
          };

          apiAccess = lib.mkOption {
            default = { };
            type = lib.types.submodule {
              options = {
                direct = lib.mkOption {
                  type = lib.types.bool;
                  default = true;
                  description = "Direct API access (built-in method index 1).";
                };
                mullvadBridges = lib.mkOption {
                  type = lib.types.bool;
                  default = true;
                  description = "API via bridge relay (built-in method index 2).";
                };
                encryptedDnsProxy = lib.mkOption {
                  type = lib.types.bool;
                  default = true;
                  description = "API via DoH (built-in method index 3).";
                };
              };
            };
          };

          tunnel = lib.mkOption {
            default = { };
            type = lib.types.submodule {
              options = {
                quantumResistant = lib.mkOption {
                  type = lib.types.enum [
                    "auto"
                    "on"
                    "off"
                  ];
                  default = "on";
                };
                ipv6 = lib.mkOption {
                  type = lib.types.bool;
                  default = true;
                };
                mtu = lib.mkOption {
                  type = lib.types.nullOr lib.types.int;
                  default = null;
                  example = 1280;
                  description = "Override tunnel MTU. null = daemon auto.";
                };
                rotationIntervalHours = lib.mkOption {
                  type = lib.types.nullOr lib.types.int;
                  default = null;
                  example = 24;
                  description = ''
                    WireGuard key rotation interval in hours.
                    null = daemon default (~7 days).
                  '';
                };
                daita = lib.mkOption {
                  default = { };
                  type = lib.types.submodule {
                    options = {
                      enable = lib.mkOption {
                        type = lib.types.bool;
                        default = true;
                        description = "DAITA traffic-analysis defense (~5-10% throughput cost).";
                      };
                      useMultihopIfNecessary = lib.mkOption {
                        type = lib.types.bool;
                        default = true;
                        description = ''
                          Auto-enable multihop when chosen exit doesn't
                          support DAITA. Inverse of Mullvad's
                          `daita-direct-only` CLI flag: `true` here sets
                          daita-direct-only=off.
                        '';
                      };
                    };
                  };
                };
              };
            };
          };
        };
      };
    };
  };

  config = lib.mkIf cfg.enable {
    services.mullvad-vpn = {
      enable = true;
      inherit (cfg) package;
    };

    # Pre-load the wireguard kernel module. Vanilla NixOS `services.mullvad-vpn`
    # only adds `tun`. Without `wireguard` loaded, mullvad-daemon falls back
    # to wg-userspace (boringtun-style TUN). That fallback has a race: it
    # creates the TUN device and immediately tries to set an IPv6 address
    # before the kernel finishes registering /proc/sys/net/ipv6/conf/wg-mullvad/.
    # ENOENT bubbles up as `Failed to set IPv6 address`, the daemon enters
    # auto-error-state lockdown and blocks ALL traffic — symptom looks like
    # "WiFi died" on rebuild. Native kernel WG creates the sysctl tree
    # synchronously with link creation, so no race.
    #
    # NOTE: this fix belongs upstream in nixpkgs's services.mullvad-vpn
    # module (one-line patch: "tun" → [ "tun" "wireguard" ]). Keep this here
    # until that PR lands; harmless duplicate after.
    boot.kernelModules = [ "wireguard" ];

    # Order mullvad-daemon AFTER kernel-module load. boot.kernelModules
    # only declares membership of the load list — it does not order
    # downstream services. Without this, on cold boot mullvad-daemon can
    # start before systemd-modules-load.service finishes, hit the userspace
    # fallback, and reproduce the original ENOENT lockdown for one boot.
    systemd.services.mullvad-daemon = {
      after = [ "systemd-modules-load.service" ];
      requires = [ "systemd-modules-load.service" ];
    };

    systemd.services.mullvad-apply-settings = {
      description = "Apply declarative Mullvad VPN settings";
      # `wants =` (not bare `after =`) ensures mullvad-daemon is actually
      # pulled in. `restartTriggers` re-fires this unit when applyScript
      # changes (i.e., when user edits declarative settings) — without it,
      # systemd's "active (exited)" oneshot semantics would skip re-runs
      # until reboot.
      after = [ "mullvad-daemon.service" ];
      wants = [ "mullvad-daemon.service" ];
      wantedBy = [ "multi-user.target" ];
      restartTriggers = [ applyScript ];
      serviceConfig = {
        Type = "oneshot";
        # RemainAfterExit dropped: we WANT the unit to re-fire on every
        # nixos-rebuild switch (via restartTriggers + activation), not
        # be silently skipped because systemd thinks it's already done.
        ExecStart = "${applyScript}/bin/mullvad-apply-settings";
      };
    };
  };
}
