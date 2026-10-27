local M = {}

function M.setup()
  local group = vim.api.nvim_create_augroup('delimiter-tint', { clear = true })

  local function highlight()
    local normal = vim.api.nvim_get_hl(0, { name = 'Normal', link = false })
    local info = vim.api.nvim_get_hl(0, { name = 'DiagnosticInfo', link = false })
    local dark = vim.o.background == 'dark'
    local bg = normal.bg or (dark and 0x1e1e2e or 0xffffff)
    -- Use the theme's informational accent to distinguish this from CursorLine.
    local accent_color = info.fg or (dark and 0x89b4fa or 0x1e66f5)
    local tint = 0
    for _, shift in ipairs { 16, 8, 0 } do
      local base = math.floor(bg / 2 ^ shift) % 256
      local accent = math.floor(accent_color / 2 ^ shift) % 256
      tint = tint + math.floor(base * 0.75 + accent * 0.25 + 0.5) * 2 ^ shift
    end
    -- Background only: preserve syntax colors and the stronger pair highlights.
    vim.api.nvim_set_hl(0, 'MatchBackground', { bg = tint })
  end

  vim.g.matchup_matchparen_hi_background = 0
  vim.g.matchup_matchparen_hi_surround_always = 0

  local function update()
    local col = vim.api.nvim_win_get_cursor(0)[2]
    local char = vim.api.nvim_get_current_line():sub(col + 1, col + 1)
    local mode = vim.api.nvim_get_mode().mode:sub(1, 1)
    -- Insert mode's match-up cursor is one character behind the actual cursor.
    local on_delimiter = mode ~= 'i' and mode ~= 'R' and char:match '^[()%[%]]$' ~= nil
    local previous = vim.g.matchup_matchparen_hi_background
    vim.g.matchup_matchparen_hi_background = on_delimiter and 1 or 0
    if on_delimiter or previous == 1 then
      -- Refresh immediately, including clearing the tint when leaving a pair.
      vim.fn['matchup#matchparen#update']()
    end
  end

  vim.api.nvim_create_autocmd('ColorScheme', { group = group, callback = highlight })
  vim.api.nvim_create_autocmd({
    'CursorMoved',
    'CursorMovedI',
    'TextChanged',
    'TextChangedI',
    'BufEnter',
    'WinEnter',
    'InsertEnter',
    'InsertLeave',
  }, { group = group, callback = update })
  highlight()
  update()
end

return M
