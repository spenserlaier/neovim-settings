{ pkgs, ... }:

{
  # Keep this at the version used for the first Home Manager activation.
  home.stateVersion = "26.05";

  # This initial module deliberately manages packages only. Existing dotfile
  # symlinks and application configuration remain untouched until later phases.
  home.packages = with pkgs; [
    bat
    carapace
    clang
    clang-tools
    delta
    eza
    fd
    fzf
    fx
    gnumake
    jq
    lazygit
    neovim
    ripgrep
    sd
    tree
    tree-sitter
    unzip
    yazi
    zoxide
  ];

  programs = {
    atuin = {
      enable = true;
      enableFishIntegration = true;
      settings = builtins.fromTOML (builtins.readFile ../atuin/config.toml);
    };

    direnv = {
      enable = true;
      nix-direnv.enable = true;
    };

    fish = {
      enable = true;
      interactiveShellInit = builtins.readFile ../fish/interactive.fish;
    };

    git = {
      enable = true;
      settings = {
        user = {
          name = "Spenser Laier";
          email = "spenserlaier@gmail.com";
        };
        core.pager = "delta";
        interactive.diffFilter = "delta --color-only";
        delta = {
          navigate = true;
          side-by-side = true;
          line-numbers = true;
        };
      };
    };

    home-manager.enable = true;

    jujutsu = {
      enable = true;
      settings = builtins.fromTOML (builtins.readFile ../jujutsu/.jjconfig.toml);
    };

    starship = {
      enable = true;
      enableFishIntegration = true;
      settings = builtins.fromTOML (builtins.readFile ../starship/starship.toml);
    };

    tmux = {
      enable = true;
      extraConfig = builtins.readFile ../tmux/common.conf;
      plugins = with pkgs.tmuxPlugins; [
        resurrect
        continuum
      ];
    };
  };

  xdg.configFile = {
    "fish/functions/nvimvenv.fish".source = ../fish/functions/nvimvenv.fish;
    "fish/tmux-sessionizer.fish" = {
      source = ../fish/tmux-sessionizer.fish;
      executable = true;
    };
  };
}
