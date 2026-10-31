{ config, ... }:

{
  programs.plasma = {
    enable = true;
    # Manage only declared settings; preserve the rest of the desktop setup.
    overrideConfig = false;
    input.keyboard.options = [ "caps:escape" ];
    shortcuts."services/org.kde.konsole.desktop"._launch = [ ];
    shortcuts."org.kde.konsole.desktop"._launch = [ ];
    hotkeys.commands.kitty = {
      name = "Open Kitty";
      keys = [ "Ctrl+Alt+T" ];
      # Kitty is installed by the host distribution, not Nix.
      command = "/usr/bin/kitty";
      logs.enabled = false;
    };
  };

  # Fedora's running desktop may not include the Nix profile in XDG_DATA_DIRS.
  xdg.dataFile."applications/plasma-manager-commands.desktop".source =
    "${config.home.path}/share/applications/plasma-manager-commands.desktop";
}
