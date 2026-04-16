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

      if [ ! -f "$SETTINGS" ]; then
        log "no settings.json yet — daemon will create on first start; skipping"
        exit 0
      fi
      VER=$(jq -r '.settings_version // empty' "$SETTINGS")
      if [ "$VER" != "15" ]; then
        log "settings_version=$VER (expected 15) — aborting to avoid clobber"
        exit 0
      fi

      log "stopping mullvad-daemon"
      systemctl stop mullvad-daemon.service
      trap 'systemctl start mullvad-daemon.service || true' EXIT
      cp -a "$SETTINGS" "$BACKUP"

      log "patching settings.json (settings_version=15)"
      jq '
          .auto_connect                                            = ${b s.autoConnect}
        | .lockdown_mode                                           = ${b s.lockdownMode}
        | .allow_lan                                               = ${b s.lan}
        | .show_beta_releases                                      = ${b s.betaProgram}
        | .tunnel_options.wireguard.quantum_resistant              = ${q s.tunnel.quantumResistant}
        | .tunnel_options.wireguard.daita.enabled                  = ${b s.tunnel.daita.enable}
        | .tunnel_options.wireguard.daita.use_multihop_if_necessary = ${b s.tunnel.daita.useMultihopIfNecessary}
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
        | .api_access_methods.direct.enabled                       = ${b s.apiAccess.direct}
        | .api_access_methods.mullvad_bridges.enabled              = ${b s.apiAccess.mullvadBridges}
        | .api_access_methods.encrypted_dns_proxy.enabled          = ${b s.apiAccess.encryptedDnsProxy}
        | .relay_settings.normal.wireguard_constraints.use_multihop = ${b s.multihop.enable}
      ' "$BACKUP" > "$SETTINGS".tmp

      jq -e . "$SETTINGS".tmp >/dev/null || {
        log "ERROR: jq output invalid — rolling back"
        rm -f "$SETTINGS".tmp
        cp -a "$BACKUP" "$SETTINGS"
        exit 1
      }
      mv "$SETTINGS".tmp "$SETTINGS"
      chmod 644 "$SETTINGS"
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
                blockAds = lib.mkOption {
                  type = lib.types.bool;
                  default = true;
                };
                blockTrackers = lib.mkOption {
                  type = lib.types.bool;
                  default = true;
                };
                blockMalware = lib.mkOption {
                  type = lib.types.bool;
                  default = true;
                };
                blockAdultContent = lib.mkOption {
                  type = lib.types.bool;
                  default = false;
                };
                blockGambling = lib.mkOption {
                  type = lib.types.bool;
                  default = true;
                };
                blockSocialMedia = lib.mkOption {
                  type = lib.types.bool;
                  default = true;
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
              options.mode = lib.mkOption {
                type = lib.types.enum [
                  "auto"
                  "off"
                  "udp2tcp"
                  "shadowsocks"
                ];
                default = "auto";
                description = "WireGuard obfuscation. Replaces legacy OpenVPN bridges.";
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

    systemd.services.mullvad-apply-settings = {
      description = "Apply declarative Mullvad VPN settings (settings.json patch)";
      after = [ "mullvad-daemon.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${applyScript}/bin/mullvad-apply-settings";
      };
    };
  };
}
