vim.cmd.packloadall()

assert(loadfile('nvim/init.lua'), 'nvim/init.lua contains a Lua syntax error')
assert(pcall(require, 'nvim-treesitter'), 'nvim-treesitter is not available')

local parsers = {
  'bash',
  'c',
  'diff',
  'fish',
  'html',
  'htmldjango',
  'javascript',
  'lua',
  'markdown',
  'markdown_inline',
  'python',
  'tsx',
  'typescript',
  'yaml',
}

for _, parser in ipairs(parsers) do
  local paths = vim.api.nvim_get_runtime_file('parser/' .. parser .. '.so', true)
  local nix_parser = vim.iter(paths):any(function(path)
    local resolved = vim.uv.fs_realpath(path)
    return resolved ~= nil and resolved:match '^/nix/store/' ~= nil
  end)

  assert(nix_parser, 'Nix parser is not available: ' .. parser)
  assert(pcall(vim.treesitter.language.add, parser), 'parser failed to load: ' .. parser)
end

local executables = {
  'bash-language-server',
  'clangd',
  'fd',
  'git',
  'lua-language-server',
  'make',
  'markdownlint',
  'pylsp',
  'pyright-langserver',
  'rg',
  'shellcheck',
  'shfmt',
  'stylua',
  'taplo',
  'tree-sitter',
  'typescript-language-server',
  'unzip',
  'yaml-language-server',
}

for _, executable in ipairs(executables) do
  assert(vim.fn.executable(executable) == 1, 'executable is not available: ' .. executable)
end

print(('Neovim runtime passed: %d parsers, %d executables'):format(#parsers, #executables))
