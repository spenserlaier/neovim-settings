local M = {}

-- Compact only PLAI type-case clauses after the language server has indented.
-- Name-based .lispwords rules cannot distinguish patterns from constructor calls.
function M.compact(lines, range)
  local source = table.concat(lines, '\n')
  local ok, parser = pcall(vim.treesitter.get_string_parser, source, 'racket')
  if not ok then
    return lines
  end
  local root = parser:parse()[1]:root()
  if root:has_error() then
    return lines
  end

  local shifts, closings, protected = {}, {}, {}
  local function protect(node)
    local kind = node:type()
    if kind == 'string' or kind == 'here_string' or kind == 'byte_string' or kind == 'regex' or kind == 'symbol' or kind == 'block_comment' then
      local first, _, last = node:range()
      -- Leading spaces inside a multiline literal are part of its value.
      for row = first + 1, last do
        protected[row] = true
      end
    end
    for child in node:iter_children() do
      protect(child)
    end
  end
  protect(root)

  local function children(node)
    local result = {}
    for child in node:iter_children() do
      if child:named() and not child:type():find 'comment' then
        result[#result + 1] = child
      end
    end
    return result
  end

  local function visit(node)
    -- Quoted data, strings, and commented-out expressions are not code.
    if node:type() ~= 'program' and node:type() ~= 'list' then
      return
    end
    local parts = children(node)
    local head = parts[1] and vim.treesitter.get_node_text(parts[1], source)
    if head == 'quote' or head == 'quasiquote' or head == 'syntax' or head == 'quasisyntax' then
      return
    end
    if node:type() == 'list' and head == 'type-case' then
      for i = 4, #parts do
        local clause = parts[i]
        if clause:type() == 'list' then
          local fields = children(clause)
          local row, col, last = clause:range()
          local selected = not range or (row >= range.start[1] - 1 and last <= range['end'][1] - 1)
          if
            selected
            and fields[1]
            and fields[1]:type() == 'symbol'
            and vim.treesitter.get_node_text(fields[1], source) ~= 'else'
            and fields[2]
            and fields[2]:type() == 'list'
          then
            local _, _, header_end = fields[2]:range()
            local body = fields[3]
            -- A clause under construction may contain only a placeholder comment.
            if not body then
              for child in clause:iter_children() do
                if child:named() and child:start() > header_end then
                  body = child
                  break
                end
              end
            end
            local body_row, body_col
            if body then
              body_row, body_col = body:range()
            end
            -- Keep expressions written on the header line in their current layout.
            if body_row and body_row > header_end then
              local indent = col + (shifts[row] or 0)
              local delta = indent + 2 - body_col - (shifts[body_row] or 0)
              for line = header_end + 1, last do
                shifts[line] = (shifts[line] or 0) + delta
              end
              -- A delimiter-only line closes at the clause's indentation.
              if lines[last + 1]:match '^%s*[%)%]%}]+%s*$' then
                closings[last] = math.min(closings[last] or indent, indent)
              end
            end
          end
        end
      end
    end
    for _, child in ipairs(parts) do
      visit(child)
    end
  end
  visit(root)

  local result = vim.deepcopy(lines)
  for index, line in ipairs(lines) do
    local row = index - 1
    if not protected[row] and (shifts[row] or closings[row]) then
      local whitespace = line:match '^%s*'
      local indent = closings[row] or (#whitespace + (shifts[row] or 0))
      result[index] = string.rep(' ', math.max(0, indent)) .. line:sub(#whitespace + 1)
    end
  end
  return result
end

function M.format(_, ctx, lines, callback)
  local ok, result = pcall(M.compact, lines, ctx.range)
  if ok then
    callback(nil, result)
  else
    callback(tostring(result))
  end
end

return M
