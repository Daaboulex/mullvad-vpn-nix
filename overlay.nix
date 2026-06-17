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
    version = "2026.3";
    # Upstream ships a per-arch .deb. The github-release updater re-hashes the
    # build arch (x86_64-linux) on a version bump; the aarch64-linux hash is
    # hand-bumped alongside it.
    # MINIMIZE-DEBT: the single-asset updater cannot re-hash both .debs. Repay by
    # dropping this overlay once nixpkgs ships the CLI fix -- nixpkgs already
    # selects the .deb per arch, so both arches are covered upstream then.
    src =
      let
        debArch = if prev.stdenv.hostPlatform.isAarch64 then "arm64" else "amd64";
      in
      prev.fetchurl {
        url = "https://github.com/mullvad/mullvadvpn-app/releases/download/${version}/MullvadVPN-${version}_${debArch}.deb";
        hash =
          {
            x86_64-linux = "sha256-OMbuc66AhwaIVgkiooUlttDazGLC5BCTiGPXA46TGso=";
            aarch64-linux = "sha256-pEzb21CSPn/ZflzZGTSJI5Hz3Q+ERFILg8q7V89AN1Q=";
          }
          .${prev.stdenv.hostPlatform.system};
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
