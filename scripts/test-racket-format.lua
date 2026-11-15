-- Runs against the built parser from scripts/verify-neovim.lua.
local compact = assert(loadfile 'nvim/lua/custom/racket_format.lua')().compact
local function lines(text)
  return vim.split(text, '\n', { plain = true })
end

local input = lines [[(type-case Result value
  (res (v sto)
       (type-case Value v
         [vecV (items)
          (res items
               sto)]
         (baseV (base)
                (consume base)
                ))))]]
local expected = lines [[(type-case Result value
  (res (v sto)
    (type-case Value v
      [vecV (items)
        (res items
             sto)]
      (baseV (base)
        (consume base)
  ))))]]
assert(vim.deep_equal(compact(input), expected), 'nested variant bodies should indent by two spaces')
assert(vim.deep_equal(compact(expected), expected), 'compacting twice must not change indentation')

local unchanged = lines [[(res value
     store)
'(type-case Result value
   (res (v sto)
        (consume v)))
#;(type-case Result value
    (res (v sto)
         (consume v)))
(quote (type-case Result value
         (res (v sto)
              (consume v))))]]
assert(vim.deep_equal(compact(unchanged), unchanged), 'calls and quoted/commented-out data should not be compacted')

local literals = lines [[(type-case Result value
  (res (v sto)
       (list "first
         keep these string spaces"
             #<<END
         keep these here-string spaces
END
             |first
         keep these symbol spaces|)))]]
local formatted = compact(literals)
for _, row in ipairs { 4, 6, 7, 9 } do
  assert(formatted[row] == literals[row], 'multiline literal contents must be preserved, row ' .. row)
end

local placeholder = lines [[(type-case Result value
  (res (v sto)
       ; unfinished branch
       ))]]
assert(compact(placeholder)[3] == '    ; unfinished branch', 'placeholder comments should also use compact indentation')

local broken = lines [[(type-case Result value
  (res (v sto)
       (consume v)]]
assert(vim.deep_equal(compact(broken), broken), 'syntax errors should leave input unchanged')
assert(vim.deep_equal(compact(input, { start = { 1, 0 }, ['end'] = { 2, 14 } }), input), 'partial selections must not change outside clauses')
local selected = compact(input, { start = { 4, 0 }, ['end'] = { 6, 21 } })
assert(selected[5] == '           (res items', 'selected nested clause should compact')
assert(selected[3] == input[3] and selected[8] == input[8], 'unselected clauses must retain indentation')

print 'Racket compact-format regression checks passed'
