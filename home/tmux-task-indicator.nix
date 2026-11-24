{
  config,
  lib,
  pkgs,
  ...
}:
let
  indicator = pkgs.writeShellApplication {
    name = "tmux-task-indicator";
    runtimeInputs = [ pkgs.tmux ];
    text = builtins.readFile ../scripts/tmux-task-indicator.sh;
  };
  indicatorCommand = lib.escapeShellArg "${config.xdg.configHome}/tmux/task-indicator";
  codexStatus = pkgs.writeShellScript "tmux-codex-status" ''
    exec ${pkgs.python3}/bin/python3 ${../scripts/codex-tmux.py} ${pkgs.tmux}/bin/tmux ${indicatorCommand} "$@"
  '';
  hook = command: [
    {
      hooks = [
        {
          type = "command";
          inherit command;
          timeout = 3;
        }
      ];
    }
  ];
  claudeHook = action: hook "${indicatorCommand} ${action} >/dev/null 2>&1 || :";
in
{
  xdg.configFile."tmux/task-indicator".source = "${indicator}/bin/tmux-task-indicator";
  xdg.configFile."tmux/codex-status".source = codexStatus;
  xdg.configFile."fish/functions/codex.fish".source = ../fish/functions/codex.fish;

  home.file.".claude/settings.json".text = builtins.toJSON {
    enabledPlugins = {
      "pyright-lsp@claude-plugins-official" = true;
      "typescript-lsp@claude-plugins-official" = true;
    };
    editorMode = "vim";
    hooks = {
      SessionStart = claudeHook "agent-idle";
      UserPromptSubmit = claudeHook "agent-start";
      PreToolUse = map (group: group // { matcher = "AskUserQuestion|ExitPlanMode"; }) (
        claudeHook "agent-waiting"
      );
      PermissionRequest = claudeHook "agent-waiting";
      PostToolUse = claudeHook "agent-working";
      PostToolUseFailure = claudeHook "agent-working";
      Stop = claudeHook "agent-done";
      StopFailure = claudeHook "agent-failed";
      SessionEnd = claudeHook "agent-exit";
    };
  };
}
