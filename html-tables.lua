-- HTML tables in Markdown, as GitHub renders them, become ordinary pandoc tables.
--
-- Pipe tables cannot have merged cells, several paragraphs or lists in a cell.
-- For such tables, authors write the table structure in HTML and the cell
-- contents in Markdown, separated from the tags by blank lines:
--
--   <table>
--   <tr><th>Name</th><th colspan="2">Description</th></tr>
--   <tr>
--   <td>
--
--   `substring`
--
--   </td>
--   ...
--
-- pandoc's Markdown reader delivers such a table as raw HTML pieces with
-- Markdown blocks in between. This filter writes the Markdown blocks back as
-- HTML (pandoc's HTML writer) and reads the whole table with pandoc's HTML
-- reader, so the table model is pandoc's own. Footnotes and citations have no
-- HTML form; they are kept aside and put back afterwards.
--
-- The classes of <col> elements in a <colgroup>, which pandoc's HTML reader does
-- not keep, are stored in the table attribute "columns" (space-separated), for
-- specification-specific table styles (see specification.lua); nested tables
-- get the classes of their own <colgroup>.
--
-- Also: <br> in a cell of a pipe table (or anywhere) becomes a line break.

local function park(el, parked)
  table.insert(parked, el)
  return pandoc.Span({}, { parked = tostring(#parked) })
end

-- Text typed directly inside the HTML tags (a Plain block between them)
-- stays as typed, as GitHub shows it: pandoc's smart quotes are undone.
-- Markdown paragraphs in cells (separated by blank lines) keep them.
local function straight(q)
  local mark = q.quotetype == 'DoubleQuote' and '"' or "'"
  local out = pandoc.Inlines({ pandoc.Str(mark) })
  out:extend(q.content)
  out:insert(pandoc.Str(mark))
  return out
end

local function html_of(block, parked)
  local blocks = pandoc.Blocks({ block }):walk({
    Note = function(n) return park(n, parked) end,
    Cite = function(c) return park(c, parked) end,
  })
  if block.t == 'Plain' then blocks = blocks:walk({ Quoted = straight }) end
  return pandoc.write(pandoc.Pandoc(blocks), 'html')
end

local function restore(el, parked)
  return el:walk({ Span = function(s)
    local k = s.attributes['parked']
    if k then return parked[tonumber(k)] end
  end })
end

-- Classes of the <col> elements of each table's <colgroup>, in the order of
-- the <table> tags (nested tables included); '' for a table without one
local function colgroups(html)
  local result, pos = {}, 1
  while true do
    local s, e = html:find('<table[%s>]', pos)
    if not s then break end
    -- the part of this table before its first row or nested table
    local stop = math.min(html:find('<tr', e) or #html + 1, html:find('<table[%s>]', e) or #html + 1)
    local head = html:sub(e, stop - 1)
    local group = head:match('<colgroup.-</colgroup>') or head:match('<colgroup.*') or ''
    local classes = {}
    for col in group:gmatch('<col[%s>][^>]*') do
      local class = col:match('class%s*=%s*"([^"]*)"') or ''
      local span = tonumber(col:match('span%s*=%s*"(%d+)"') or '1')
      for _ = 1, span do table.insert(classes, class == '' and '-' or class) end
    end
    table.insert(result, table.concat(classes, ' '))
    pos = e
  end
  return result
end

local function is_html(b, pattern)
  return b.t == 'RawBlock' and b.format == 'html' and b.text:match(pattern)
end

function Blocks(blocks)
  local out, i, changed = pandoc.Blocks({}), 1, false
  while i <= #blocks do
    if is_html(blocks[i], '^%s*<table') then
      local parts, parked, depth, j = {}, {}, 0, i
      repeat
        local b = blocks[j]
        if b.t == 'RawBlock' and b.format == 'html' then
          table.insert(parts, b.text)
          local _, opens = b.text:gsub('<table[%s>]', '')
          local _, closes = b.text:gsub('</table>', '')
          depth = depth + opens - closes
        else
          table.insert(parts, html_of(b, parked))
        end
        j = j + 1
      until depth <= 0 or j > #blocks
      local html = table.concat(parts, '\n')
      local groups, k = colgroups(html), 0
      for _, r in ipairs(pandoc.read(html, 'html').blocks) do
        r = restore(r, parked)
        -- tables in the order of their <table> tags: outer before nested
        out:extend(pandoc.Blocks({ r }):walk({ traverse = 'topdown', Table = function(t)
          k = k + 1
          if groups[k] and groups[k] ~= '' then t.attributes['columns'] = groups[k] end
          return t
        end }))
      end
      i, changed = j, true
    else
      out:insert(blocks[i])
      i = i + 1
    end
  end
  return changed and out or nil
end

function RawInline(el)
  if el.format == 'html' and el.text:match('^<br%s*/?>$') then
    return pandoc.LineBreak()
  end
end
