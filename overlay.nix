# overlay.nix — pin mullvad-vpn ahead of nixpkgs.
#
# nixpkgs ships 2025.14 (Dec 2025) which has a CLI schema-parse bug:
# `mullvad <subcmd> get|set` crashes with "missing bridge settings" on
# settings_version=15 (where bridges moved into api_access_methods).
# Upstream desktop 2026.1 (Mar 16, 2026) ships the fix.
#
# nixpkgs uses fetchurl on Mullvad's pre-built .deb, so the bump is
# version + hash. When nixpkgs catches up, this overlay can be dropped.
_final: prev: {
  mullvad-vpn = prev.mullvad-vpn.overrideAttrs (_old: rec {
    version = "2026.1";
    src = prev.fetchurl {
      url = "https://github.com/mullvad/mullvadvpn-app/releases/download/${version}/MullvadVPN-${version}_amd64.deb";
      hash = "sha256-HleajbEbw5Z1ab/E4zSR+GxDOIuvegP4N9yRFZYv7z4=";
    };
  });
}
