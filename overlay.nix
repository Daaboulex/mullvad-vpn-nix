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

    # Override versionCheckHook target: use CLI not GUI.
    #
    # WHY: default target is $out/bin/mullvad-vpn — the Electron GUI.
    # Electron tries to enter Chromium's SUID sandbox; the sandbox helper
    # needs mode 4755 + owner root, which the read-only Nix store cannot
    # provide. Check FATAL-aborts in CI even though the build artifact is
    # fine. The CLI binary `mullvad` reports the same version with no
    # Electron dependency.
    #
    # SYNTAX: `placeholder "out"` is mandatory. This attribute is evaluated
    # by Nix at instantiation time (before $out exists), not by bash —
    # a literal "$out/..." string is passed through unsubstituted and the
    # hook tries to open a file literally named `$out/bin/mullvad`.
    versionCheckProgram = "${placeholder "out"}/bin/mullvad";
  });
}
