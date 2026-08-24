{ pkgs, ... }:

{
  # Keep this at the version used for the first Home Manager activation.
  home.stateVersion = "26.05";

  # General-purpose command-line tools available outside program-specific
  # wrappers as well as inside editors and shells.
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

    neovim = {
      enable = true;
      defaultEditor = true;
      extraPackages = with pkgs; [
        clang
        clang-tools
        fd
        git
        gnumake
        ripgrep
        tree-sitter
        unzip
      ];
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
    "nvim".source = ../nvim;
  };
}
