# nixpkgs is pinned so local development and CI use identical tool versions.
# Current pin: a build of the nixpkgs-unstable channel (version 26.05pre998534,
# commit d233902), chosen because it is the revision this template was
# developed and tested against, not for any specific package version.
# A floating channel can silently change tool versions (a newer linter once
# failed CI on rules a project never opted into). To bump: pick a channel
# revision, compute its hash with
#   nix-prefetch-url --unpack https://github.com/NixOS/nixpkgs/archive/<rev>.tar.gz
# and update both this file and template/shell.nix.jinja (`just validate`
# checks that they match), then run `just validate`.
{ pkgs ? import
    (fetchTarball {
      url = "https://github.com/NixOS/nixpkgs/archive/d233902339c02a9c334e7e593de68855ad26c4cb.tar.gz";
      sha256 = "1485vqhb8cwym1m75v61i10j427vazszaklkwj2wmm80k8sijjyz";
    })
    { }
}:

pkgs.mkShell {
  buildInputs = with pkgs; [
    git
    gh
    just
    jq
    copier
  ];

  shellHook = ''
    echo "❄️ Welcome to the Project Template shell!"
  '';
}
