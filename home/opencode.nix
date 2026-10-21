{ pkgs, ... }:

{
  programs.opencode = {
    enable = true;
    settings = builtins.fromJSON (builtins.readFile ../opencode/opencode.json);
  };

  home.packages = [
    (pkgs.writeShellApplication {
      name = "opencode-local";
      runtimeInputs = with pkgs; [
        coreutils
        curl
        jq
        openssh
        opencode
      ];
      text = builtins.readFile ../scripts/opencode-local.sh;
    })
  ];
}
