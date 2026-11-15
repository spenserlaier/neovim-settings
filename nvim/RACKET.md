# Optional Racket support

Racket support uses an existing `racket` executable on Neovim's PATH. Home
Manager does not install Racket or its packages.

Home Manager supplies the Racket Tree-sitter parser and its standard syntax
highlighting queries. Rebuild the Home Manager configuration and restart
Neovim to use them. No PLAI-specific highlighting rules are added.

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
followed by a Tree-sitter pass that indents PLAI variant-clause bodies two
spaces from the clause opener. This avoids argument-style alignment inside
patterns such as `(res (value store) ...)`, while ordinary constructor calls
keep their usual alignment. Both steps also run with `<leader>f`, using the
existing two-second timeout on save. The compacting pass preserves line breaks
and literal contents, and skips files with parse errors. If the server is
absent, only the compacting pass runs. Formatting does not balance missing
parentheses or enforce a maximum line width.

Home Manager installs `~/.lispwords` rules for PLAI's `type-case` and
`define-type`. In particular, `type-case` clauses indent two spaces from the
opening form instead of aligning under its first argument, which otherwise
pushes nested cases far to the right. The indenter reads these rules for files
under your home directory; a project's own `.lispwords` can override them.

In normal and visual mode, placing the cursor on either `(` / `)` or `[` / `]`
adds a faint background tint across the matched expression. Moving off the
delimiter clears the tint; the existing matching-pair highlights remain.
This uses `vim-matchup`, works across lines, and does not require a Racket
Tree-sitter parser. The tint adapts when changing color schemes, blending 75%
background with 25% of the theme's informational accent to distinguish it from
the current-line highlight. Its strength can be adjusted in
`lua/custom/delimiter_tint.lua`.
