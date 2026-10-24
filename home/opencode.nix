{ pkgs, ... }:

{
  programs.opencode = {
    enable = true;
    settings = builtins.fromJSON (builtins.readFile ../opencode/opencode.json);
  };

  home.packages = [
    (pkgs.writeShellApplication {
      name = "opencode-local";
      runtimeInputs =
        with pkgs;
        [
          autossh
          coreutils
          curl
          flock
          jq
          openssh
          opencode
        ]
        ++ lib.optionals stdenv.hostPlatform.isLinux [ procps ];
      text = builtins.readFile ../scripts/opencode-local.sh;
    })
  ];
}
