{ pkgs, ... }:

{
  imports = [ ./fonts.nix ./opencode.nix ];

  # Keep this at the version used for the first Home Manager activation.
  home.stateVersion = "26.05";

  # Use Readline/libedit editing in Python instead of the newer PyREPL.
  home.sessionVariables.PYTHON_BASIC_REPL = "1";

  # libedit uses a separate configuration from GNU Readline (notably on macOS).
  home.file.".editrc".text = ''
    bind -v
  '';

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
    jj-starship
    (writeScriptBin "jjr" ''
      #!${python3}/bin/python3
      ${builtins.readFile ../scripts/jjr.py}
    '')
    (writeScriptBin "jj-remote-prompt" ''
      #!${python3}/bin/python3
      ${builtins.readFile ../starship/jj-remote-prompt.py}
    '')
    jq
    lazygit
    ripgrep
    ranger
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
      package = import ./atuin-package.nix { inherit pkgs; };
      settings = builtins.fromTOML (builtins.readFile ../atuin/config.toml);
    };

    direnv = {
      enable = true;
      nix-direnv.enable = true;
    };

    fish = {
      enable = true;
      shellInit = ''
        if test -e /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.fish
          source /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.fish
        end
        if test -d "$HOME/.nix-profile/bin"
          set -gx PATH "$HOME/.nix-profile/bin" (string match -v -- "$HOME/.nix-profile/bin" $PATH)
        end
      '';
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
      withNodeJs = false;
      withPython3 = false;
      withRuby = false;
      plugins = [
        (pkgs.vimPlugins.nvim-treesitter.withPlugins (parsers: with parsers; [
          bash
          c
          diff
          fish
          html
          htmldjango
          javascript
          lua
          markdown
          markdown_inline
          python
          racket
          tsx
          typescript
          yaml
        ]))
      ];
      extraPackages = with pkgs; [
        bash-language-server
        clang
        clang-tools
        fd
        git
        gnumake
        lua-language-server
        markdownlint-cli
        pyright
        python3Packages.python-lsp-server
        ripgrep
        shellcheck
        shfmt
        stylua
        taplo
        tree-sitter
        typescript
        typescript-language-server
        unzip
        yaml-language-server
      ];
    };

    readline = {
      enable = true;
      variables.editing-mode = "vi";
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
    "fish/functions/vi_fzf.fish".source = ../fish/functions/vi_fzf.fish;
    "fish/functions/nvimvenv.fish".source = ../fish/functions/nvimvenv.fish;
    "fish/tmux-sessionizer.fish" = {
      source = ../fish/tmux-sessionizer.fish;
      executable = true;
    };
    "fish/tmux-picker.fish" = {
      source = ../fish/tmux-picker.fish;
      executable = true;
    };
    "kitty/kitty.conf" = {
      text = builtins.replaceStrings
        [ "font_size 24" ]
        [ "font_size ${if pkgs.stdenv.hostPlatform.isLinux then "20" else "24"}" ]
        (builtins.readFile ../kitty/kitty.conf);
      force = true;
    };
    "kitty/current-theme.conf".source = ../kitty/current-theme.conf;
    "kitty/open-actions.conf".source = ../kitty/open-actions.conf;
    "kitty/kitty.conf.bak".source = ../kitty/kitty.conf.bak;
    "nvim".source = ../nvim;
    "ranger".source = ../ranger;
  };
}
