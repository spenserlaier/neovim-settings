# Optional Racket support

Racket support uses an existing `racket` executable on Neovim's PATH. Home
Manager does not install Racket or its packages.

For `#lang plai-typed`, install the packages using the same Racket installation
that Neovim will launch:

```sh
raco pkg install --auto racket-langserver plai-typed
```

Restart Neovim after installing packages. Opening a `.rkt` file checks for the
language server asynchronously and enables it when available. If Racket or the
server package is absent, support stays inactive without a startup error.

Syntax and type errors use the existing diagnostic signs, underlines, floating
messages, and `<leader>q` diagnostic list. Use `:checkhealth vim.lsp` to inspect
the attached server. Runtime errors and failing tests still require running the
program.

Racket formats automatically on save through the attached language server,
using the existing two-second formatting timeout. Explicit formatting is also
available with `<leader>f`. If the server is absent, saving works without
formatting. The installed server's indenter adjusts whitespace; it does not
balance missing parentheses or perform full line-break reflow.

In normal and visual mode, placing the cursor on either `(` / `)` or `[` / `]`
adds a faint background tint across the matched expression. Moving off the
delimiter clears the tint; the existing matching-pair highlights remain.
This uses `vim-matchup`, works across lines, and does not require a Racket
Tree-sitter parser. The tint adapts when changing color schemes, blending 75%
background with 25% of the theme's informational accent to distinguish it from
the current-line highlight. Its strength can be adjusted in
`lua/custom/delimiter_tint.lua`.
