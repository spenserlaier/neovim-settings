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
  codexHook = action: hook "${indicatorCommand} ${action} >/dev/null 2>&1; printf '%s\\n' '{}'";
  claudeHook = action: hook "${indicatorCommand} ${action} >/dev/null 2>&1 || :";
in
{
  xdg.configFile."tmux/task-indicator".source = "${indicator}/bin/tmux-task-indicator";

  home.file.".codex/hooks.json".text = builtins.toJSON {
    hooks = {
      SessionStart = codexHook "agent-idle";
      UserPromptSubmit = codexHook "agent-start";
      PermissionRequest = codexHook "agent-waiting";
      PostToolUse = codexHook "agent-working";
      Stop = codexHook "agent-done";
      Interrupt = codexHook "agent-idle";
      SessionEnd = codexHook "agent-exit";
    };
  };

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
