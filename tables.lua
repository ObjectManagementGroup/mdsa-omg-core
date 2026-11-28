-- Tables as tabularray tables (https://ctan.org/pkg/tabularray), in the OMG
-- style: a full grid, header rows in bold, the caption below the table.
--
-- pandoc reads all tables (pipe tables, HTML tables) into its table model and
-- writes the contents of every cell with its own LaTeX writer. This filter only
-- translates the table's frame into tabularray settings:
--   column alignments and widths  -> colspec={X[2,l] X[1,c] ...}, widths from
--                                    the contents
--   header rows                   -> rowhead, bold
--   merged cells                  -> cell{r}{c}={r=2,c=1}{}
--   caption and identifier        -> caption={...}, label={tbl:...}
--   footnotes in cells            -> table notes below the table
--   line breaks in cells          -> \\ in a braced cell (tabularray's way)
--   tables in cells (HTML tables) -> an inner tblr with natural column widths,
--                                    without padding around it
--
-- Specification styles (see specification.lua) can add to a table through its
-- attributes, which this filter appends to the tabularray settings:
--   tblr-colspec  replaces the column spec, e.g. Q[c]Q[c] for natural widths
--   tblr-inner    more inner settings, e.g. double lines, cell colors
--   tblr-outer    more outer settings
--   tblr-before   LaTeX inserted before the table (e.g. a name box)
--   tblr-after    LaTeX inserted after the table
--   tblr-env      the environment: longtblr (default; breaks across pages,
--                 caption) or tblr (one piece, no caption)
--   tblr-lines    replaces the full grid ("hlines, vlines"), e.g. with
--                 single line segments; empty for no lines
-- Runs after pandoc-crossref and after specification.lua.

local ALIGN = { AlignLeft = 'l', AlignCenter = 'c', AlignRight = 'r', AlignDefault = 'l' }

local function latex(blocks)
  local s = pandoc.write(pandoc.Pandoc(blocks), 'latex', PANDOC_WRITER_OPTIONS)
  return (s:gsub('^%s+', ''):gsub('%s+$', ''))
end

local render

-- LaTeX of a cell; footnotes become table notes
local function cell_latex(blocks, notes)
  local breaks = false
  blocks = pandoc.Blocks(blocks):walk({
    traverse = 'topdown',
    Table = function(t) return render(t, true), false end,
    Note = function(n)
      table.insert(notes, latex(n.content))
      return pandoc.RawInline('latex', '\\TblrNote{' .. #notes .. '}')
    end,
    -- \\ in braces: tabularray then keeps it in the cell, and it ends the line
    -- in centered cells too (\newline leaves the line off-centre)
    LineBreak = function() breaks = true; return pandoc.RawInline('latex', '\\\\ ') end,
    Image = function(img)
      return { pandoc.RawInline('latex', '\\raisebox{-0.5\\height}{'), img, pandoc.RawInline('latex', '}') }
    end,
  })
  local tex = latex(blocks)
  if breaks then tex = '{' .. tex .. '}' end
  return tex
end

-- Relative column widths, from the contents: at least the longest word (which
-- cannot be broken), and more for columns with long texts. Widths that pandoc
-- derives from a table's source (the dashes of a pipe table, equal widths for
-- HTML tables) are ignored: they depend on how the source happens to be typed.
local function widths(tbl, rows)
  local w, word, len = {}, {}, {}
  for i = 1, #tbl.colspecs do word[i] = 3; len[i] = 3 end
  for _, row in ipairs(rows) do
    for _, c in ipairs(row.cells) do
      if c.cell.col_span == 1 then
        -- code that a specification filter wrote as raw \lstinline (e.g. FEEL in
        -- DMN) counts like code
        local raw = {}
        c.cell.contents:walk({ RawInline = function(r)
          local _, code = r.text:match('\\lstinline%b[](.)(.-)%1')
          if not code then _, code = r.text:match('\\lstinline([^%[%w])(.-)%1') end
          if code then table.insert(raw, code) end
        end })
        local text = pandoc.utils.stringify(c.cell.contents) .. ' ' .. table.concat(raw, ' ')
        len[c.col] = math.max(len[c.col], math.min(#text, 60))
        for token in text:gmatch('%S+') do
          word[c.col] = math.max(word[c.col], math.min(#token, 30))
        end
        -- code is set in a wider (monospaced) font and should not break
        local function code_tokens(t)
          for token in t:gmatch('%S+') do
            word[c.col] = math.max(word[c.col], math.min(#token * 1.4, 40))
          end
        end
        c.cell.contents:walk({ Code = function(code) code_tokens(code.text) end })
        for _, t in ipairs(raw) do code_tokens(t) end
      end
    end
  end
  for i = 1, #tbl.colspecs do w[i] = math.max(word[i], len[i] / 2.5) end
  return w
end

local function fmt(x)
  return (string.format('%.2f', x):gsub('0+$', ''):gsub('%.$', ''))
end

-- Writes a table; a nested table (in a cell of another table) is a tblr with
-- natural column widths and no caption
render = function(tbl, nested)

  -- all rows: header rows, then body rows (with their own header rows), then foot
  local rows, nhead = {}, 0
  for _, r in ipairs(tbl.head.rows) do table.insert(rows, { row = r }); nhead = nhead + 1 end
  for _, b in ipairs(tbl.bodies) do
    for _, r in ipairs(b.head) do table.insert(rows, { row = r }) end
    for _, r in ipairs(b.body) do table.insert(rows, { row = r }) end
  end
  for _, r in ipairs(tbl.foot.rows) do table.insert(rows, { row = r }) end
  local n = #tbl.colspecs

  -- place the cells, taking merged cells into account
  local covered = {}
  for r = 1, #rows do covered[r] = covered[r] or {} end
  for r, entry in ipairs(rows) do
    entry.cells = {}
    local c = 1
    for _, cell in ipairs(entry.row.cells) do
      while covered[r][c] do c = c + 1 end
      table.insert(entry.cells, { col = c, cell = cell })
      for dr = 0, cell.row_span - 1 do
        covered[r + dr] = covered[r + dr] or {}
        for dc = 0, cell.col_span - 1 do covered[r + dr][c + dc] = true end
      end
      c = c + cell.col_span
    end
  end

  local notes, inner, body, nested_rows = {}, {}, {}, {}
  for r, entry in ipairs(rows) do
    local line = {}
    for c = 1, n do line[c] = '' end
    for _, p in ipairs(entry.cells) do
      line[p.col] = cell_latex(p.cell.contents, notes)
      if #p.cell.contents == 1 and p.cell.contents[1].t == 'Table' then
        -- a nested table fills its cell: no padding (tabularray's colsep is 6pt)
        line[p.col] = '\\hspace*{-6pt}' .. line[p.col] .. '\\hspace*{-6pt}'
        table.insert(nested_rows, ('row{%d}={abovesep=0pt, belowsep=0pt}'):format(r))
      end
      if p.cell.row_span > 1 or p.cell.col_span > 1 then
        table.insert(inner, ('cell{%d}{%d}={r=%d,c=%d}{}'):format(
          r, p.col, p.cell.row_span, p.cell.col_span))
      end
      if p.cell.alignment ~= 'AlignDefault' then
        table.insert(inner, ('cell{%d}{%d}={halign=%s}'):format(r, p.col, ALIGN[p.cell.alignment]))
      end
    end
    table.insert(body, table.concat(line, ' & ') .. ' \\\\')
  end

  -- column spec
  local colspec = tbl.attributes['tblr-colspec']
  if not colspec and nested then
    colspec = string.rep('Q[l]', #tbl.colspecs)
  elseif not colspec then
    local w, parts = widths(tbl, rows), {}
    for i, spec in ipairs(tbl.colspecs) do
      table.insert(parts, ('X[%s,%s]'):format(fmt(w[i]), ALIGN[spec[1]] or 'l'))
    end
    colspec = table.concat(parts, ' ')
  end
  table.insert(inner, 1, 'colspec={' .. colspec .. '}')
  local lines = tbl.attributes['tblr-lines'] or 'hlines, vlines'
  if lines ~= '' then table.insert(inner, 2, lines) end
  if nhead > 0 then
    -- repeated header rows need a row below them (a table of only header
    -- rows fails in tabularray)
    if nhead < #rows then table.insert(inner, ('rowhead=%d'):format(nhead)) end
    table.insert(inner, ('row{1-%d}={font=\\omgtablehead}'):format(nhead))
  end
  if tbl.attributes['tblr-inner'] then table.insert(inner, tbl.attributes['tblr-inner']) end
  -- after a style's settings (e.g. its rowsep): rows with a nested table
  for _, n in ipairs(nested_rows) do table.insert(inner, n) end

  -- outer spec: caption, label, notes
  local env = nested and 'tblr' or tbl.attributes['tblr-env'] or 'longtblr'
  local outer = {}
  local caption = latex({ pandoc.Plain(pandoc.utils.blocks_to_inlines(tbl.caption.long)) })
  if env ~= 'longtblr' then
    -- tblr: no caption
  elseif caption ~= '' then
    table.insert(outer, 'caption={' .. caption .. '}')
    if tbl.identifier ~= '' then table.insert(outer, 'label={' .. tbl.identifier .. '}') end
  else
    table.insert(outer, 'entry=none, label=none, theme=omgplain')
  end
  for k, text in ipairs(notes) do table.insert(outer, ('note{%d}={%s}'):format(k, text)) end
  if tbl.attributes['tblr-outer'] then table.insert(outer, tbl.attributes['tblr-outer']) end

  local tex = (tbl.attributes['tblr-before'] or '') ..
    '\\begin{' .. env .. '}[' .. table.concat(outer, ', ') .. ']{\n  ' ..
    table.concat(inner, ',\n  ') .. '}\n' ..
    table.concat(body, '\n') .. '\n\\end{' .. env .. '}' ..
    (tbl.attributes['tblr-after'] or '')
  return pandoc.RawBlock('latex', tex)
end

-- Top-down, so that tables in cells are written as part of their table
return { {
  traverse = 'topdown',
  Table = function(tbl)
    if FORMAT:match('latex') then return render(tbl, false), false end
  end,
} }
