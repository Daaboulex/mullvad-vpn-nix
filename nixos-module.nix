# nixos-module.nix — Mullvad VPN daemon + declarative settings via jq-patch.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.mullvad-vpn-declarative;
  s = cfg.settings;

  # mullvad-cli 2025.14 has a schema-compat bug where `get`/`set` crash with
  # "missing bridge settings" on settings_version=15. Daemon handles it fine
  # — only CLI is broken. Workaround: patch /etc/mullvad-vpn/settings.json
  # directly with jq, daemon stopped/started around the patch. Schema-gated
  # to settings_version=15; if Mullvad bumps the schema we skip rather than
  # clobber.
  b = v: if v then "true" else "false";
  q = v: "\"${v}\"";
  # Mullvad uses sentinel string "any" for unset constraints. Translate
  # null → "any", string → "{ only: <string> }", list → "{ only: [...] }".
  filterAny =
    v:
    if v == null then
      "\"any\""
    else if builtins.isList v then
      "{\"only\": ${builtins.toJSON v}}"
    else
      "{\"only\": ${builtins.toJSON v}}";
  # Port: null → "any" sentinel string, int → { only: { port: int } } shape.
  portAny = v: if v == null then "\"any\"" else "{\"only\": ${toString v}}";

  applyScript = pkgs.writeShellApplication {
    name = "mullvad-apply-settings";
    runtimeInputs = with pkgs; [
      jq
      systemd
      coreutils
    ];
    text = ''
      set -eu
      SETTINGS=/etc/mullvad-vpn/settings.json
      BACKUP=/etc/mullvad-vpn/settings.json.nixos-bak

      log() { echo "[mullvad-apply] $*"; }

      # Wait up to 30s for the daemon to create settings.json on first boot.
      # Without this, on a fresh install the file doesn't exist when this
      # unit runs (we ordered after mullvad-daemon.service start, but the
      # daemon writes settings.json LAZILY a few seconds after start). The
      # old early-exit + RemainAfterExit combo silently skipped the patch
      # for the entire boot session, leaving user-declared settings unapplied
      # until the next reboot — a privacy regression for lockdownMode users.
      for _ in $(seq 1 30); do
        [ -f "$SETTINGS" ] && break
        sleep 1
      done
      if [ ! -f "$SETTINGS" ]; then
        log "settings.json never appeared after 30s — daemon failed to start; aborting"
        exit 1
      fi
      VER=$(jq -r '.settings_version // empty' "$SETTINGS")
      if [ "$VER" != "15" ]; then
        log "settings_version=$VER (expected 15) — aborting to avoid clobber"
        exit 0
      fi

      log "stopping mullvad-daemon"
      systemctl stop mullvad-daemon.service
      # Trap restarts the daemon on any exit path. We do NOT swallow start
      # failures — if the daemon refuses to come back, the unit must fail
      # so the operator sees it (vs systemd marking us "active (exited)"
      # while the daemon stays dead with stale settings).
      trap 'systemctl start mullvad-daemon.service' EXIT
      cp -a "$SETTINGS" "$BACKUP"

      log "patching settings.json (settings_version=15)"
      jq '
          .auto_connect                                            = ${b s.autoConnect}
        | .lockdown_mode                                           = ${b s.lockdownMode}
        | .allow_lan                                               = ${b s.lan}
        | .show_beta_releases                                      = ${b s.betaProgram}
        | .update_default_location                                 = ${b s.updateDefaultLocation}
        | .tunnel_options.wireguard.quantum_resistant              = ${q s.tunnel.quantumResistant}
        | .tunnel_options.wireguard.daita.enabled                  = ${b s.tunnel.daita.enable}
        | .tunnel_options.wireguard.daita.use_multihop_if_necessary = ${b s.tunnel.daita.useMultihopIfNecessary}
        | .tunnel_options.wireguard.mtu                            = ${
          if s.tunnel.mtu == null then "null" else toString s.tunnel.mtu
        }
        | .tunnel_options.wireguard.rotation_interval              = ${
          if s.tunnel.rotationIntervalHours == null then "null" else toString s.tunnel.rotationIntervalHours
        }
        | .tunnel_options.generic.enable_ipv6                      = ${b s.tunnel.ipv6}
        | .tunnel_options.dns_options.state                        = ${q s.dns.mode}
        | .tunnel_options.dns_options.default_options.block_ads           = ${b s.dns.blockAds}
        | .tunnel_options.dns_options.default_options.block_trackers      = ${b s.dns.blockTrackers}
        | .tunnel_options.dns_options.default_options.block_malware       = ${b s.dns.blockMalware}
        | .tunnel_options.dns_options.default_options.block_adult_content = ${b s.dns.blockAdultContent}
        | .tunnel_options.dns_options.default_options.block_gambling      = ${b s.dns.blockGambling}
        | .tunnel_options.dns_options.default_options.block_social_media  = ${b s.dns.blockSocialMedia}
        | .tunnel_options.dns_options.custom_options.addresses     = ${builtins.toJSON s.dns.customServers}
        | .obfuscation_settings.selected_obfuscation               = ${q s.obfuscation.mode}
        | .obfuscation_settings.udp2tcp.port                       = ${portAny s.obfuscation.udp2tcpPort}
        | .obfuscation_settings.shadowsocks.port                   = ${portAny s.obfuscation.shadowsocksPort}
        | .obfuscation_settings.wireguard_port.port                = ${portAny s.obfuscation.wireguardPort}
        | .api_access_methods.direct.enabled                       = ${b s.apiAccess.direct}
        | .api_access_methods.mullvad_bridges.enabled              = ${b s.apiAccess.mullvadBridges}
        | .api_access_methods.encrypted_dns_proxy.enabled          = ${b s.apiAccess.encryptedDnsProxy}
        | .relay_settings.normal.wireguard_constraints.use_multihop = ${b s.multihop.enable}
        | .relay_settings.normal.wireguard_constraints.ip_version   = ${q s.relay.ipVersion}
        | .relay_settings.normal.providers                          = ${filterAny s.relay.providers}
        | .relay_settings.normal.ownership                          = ${q s.relay.ownership}
        | .relay_settings.normal.wireguard_constraints.entry_providers = ${filterAny s.relay.entryProviders}
        | .relay_settings.normal.wireguard_constraints.entry_ownership = ${q s.relay.entryOwnership}
      ' "$BACKUP" > "$SETTINGS".tmp

      jq -e . "$SETTINGS".tmp >/dev/null || {
        log "ERROR: jq output invalid — rolling back"
        rm -f "$SETTINGS".tmp
        cp -a "$BACKUP" "$SETTINGS"
        exit 1
      }
      mv "$SETTINGS".tmp "$SETTINGS"
      # 600: file may contain account tokens after first login. World-readable
      # (644) was an oversight from earlier iterations.
      chmod 600 "$SETTINGS"
      chown root:root "$SETTINGS"

      log "starting mullvad-daemon"
      systemctl start mullvad-daemon.service
      trap - EXIT
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
        Declarative Mullvad daemon settings. Applied via jq-patch of
        /etc/mullvad-vpn/settings.json (mullvad-cli 2025.14 has a schema bug
        on settings_version=15). Schema-gated: if Mullvad bumps the schema
        this module skips rather than clobbering.
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
                  ];
                  default = "auto";
                  description = "WireGuard obfuscation. Replaces legacy OpenVPN bridges.";
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
                  description = "Provider filter for the multihop entry relay. null = any.";
                };
                entryOwnership = lib.mkOption {
                  type = lib.types.enum [
                    "any"
                    "rented"
                    "owned"
                  ];
                  default = "any";
                  description = "Ownership filter for the multihop entry relay.";
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
                  description = "Direct API access.";
                };
                mullvadBridges = lib.mkOption {
                  type = lib.types.bool;
                  default = true;
                  description = "API via bridge relay (when direct blocked).";
                };
                encryptedDnsProxy = lib.mkOption {
                  type = lib.types.bool;
                  default = true;
                  description = "API via DoH (when direct blocked).";
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
                        description = "Auto-enable multihop when chosen exit doesn't support DAITA.";
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
      package = cfg.package;
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
      description = "Apply declarative Mullvad VPN settings (settings.json patch)";
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
