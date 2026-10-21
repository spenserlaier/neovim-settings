{ pkgs, ... }:

let
  symbols = pkgs.noto-fonts.override { variants = [ "NotoSansSymbols2" ]; };
  fontPython = pkgs.python3.withPackages (python: [ python.fonttools ]);
  symbolMap = pkgs.runCommand "kitty-symbol-fonts.conf" { } ''
    ${fontPython}/bin/python ${../scripts/kitty-symbol-map.py} \
      ${symbols}/share/fonts > "$out"
  '';
in
{
  home.packages = [
    pkgs.nerd-fonts.caskaydia-cove
    pkgs.nerd-fonts.fira-code
    symbols
  ];

  # macOS registers home.packages fonts through Home Manager's Darwin module.
  fonts.fontconfig.enable = pkgs.stdenv.hostPlatform.isLinux;

  xdg.configFile."kitty/symbol-fonts.conf".source = symbolMap;
}
