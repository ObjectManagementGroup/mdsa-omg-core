-- Cross-references written as ordinary Markdown links, as on GitHub, become
-- numbered references in the PDF.
--
-- Sections: link to the heading, with its title as link text.
--   see [Types](#types)                      same file
--   see [Types](05_Object_Model.md#types)    other file
--   see [Object Model](05_Object_Model.md)   other file, its clause
--   PDF: "see 5.2.4", "see Clause 5"; for annexes (A_*.md) "Annex A", "A.2"
--
-- Figures: an image in its own paragraph is a figure; its alt text is the
-- caption. Link to the image file, with the caption as link text.
--   ![Build pipeline](Images/build-pipeline.svg)
--   see [Build pipeline](Images/build-pipeline.svg)       PDF: "see Figure 7.1"
--
-- Tables: a level-6 heading "Table: <caption>" directly before a table is its
-- caption. Link to the heading, with the caption as link text.
--   ###### Table: Markdown files
--   | File | Clause |
--   ...
--   see [Markdown files](07_Pipeline.md#table-markdown-files)  PDF: "see Table 7.1"
--
-- Grammar rules (e.g. FEEL): a numbered list whose referenced items start with
-- an HTML anchor "rule-...". GitHub and LaTeX number the list; alternatives
-- (nested numbered lists) are numbered i, ii, iii, as GitHub shows them.
--   1. <a id="rule-textual-expression"></a>textual expression =
--      1. <a id="rule-textual-expression-i"></a>for expression | ... |
--      1. disjunction ;
--   see [textual expression](10_FEEL.md#rule-textual-expression)  PDF: "see rule 2"
--   see [for expressions](10_FEEL.md#rule-textual-expression-i)   PDF: "see rule 2.i"
--   | [2.i](10_FEEL.md#rule-textual-expression-i) |                 PDF: "2.i" (a link
--                                    whose text is a rule number: the number only)
-- The numbers exist only in LaTeX (\ref), so inserting a rule changes nothing
-- else in the source, and change bars do not mark renumbered rules.
--
-- Other anchors: a link to an HTML anchor <a id="..."></a> keeps its text and
-- becomes a link to that place in the PDF.
--
-- GitHub shows the link text and follows the link; the PDF shows the generated
-- number instead, so the text around a link must read well with either.
--
-- How: headings get GitHub's identifiers (gfm_auto_identifiers). This filter
-- runs before pandoc-crossref and
-- - labels each heading sec:<file>--<identifier>, so that headings with the
--   same title in different files (e.g. "Overview") do not collide; within a
--   file, GitHub and pandoc number repeated titles (overview, overview-1)
-- - labels each figure fig:<image file name>
-- - turns each table caption heading into the caption of its table, labelled
--   tbl:<file>--<heading identifier>
-- - turns each link into the matching reference (@fig:..., @tbl:...,
--   [-@sec:...]), which pandoc-crossref numbers.
-- References written directly as @sec:<identifier>, @fig:..., @tbl:... and
-- {#sec:...}/{#fig:...}/{#tbl:...} labels keep working; section references are
-- shown without "Section" as above.
--
-- Warnings (the link is still converted, or left as it is):
-- - the link text is not the title or caption of its target
-- - the target heading, table, figure or file is not found
-- - a relative link to another kind of file, which the PDF cannot follow
-- - a "Table:" heading that is not directly followed by a table

-- Must match the 'from' setting in omgLaTeX.yaml, for reading linked files
local READER = 'markdown+gfm_auto_identifiers+lists_without_preceding_blankline'
  .. '-blank_before_header-blank_before_blockquote'

local IMAGE = { svg = true, png = true, jpg = true, jpeg = true, gif = true, pdf = true }

local own, others = nil, {}

local this_file = PANDOC_STATE.input_files[1] or ''
local this_name = this_file:match('([^/]*)$')
local folder = this_file:match('^(.*/)') or ''

-- Label prefix of a file: 07_Main.md -> 07_main
local function file_key(name)
  return (name:gsub('%.md$', ''):lower():gsub('[^%w_]', '-'))
end

local function section_label(name, anchor)
  return 'sec:' .. file_key(name) .. '--' .. anchor
end

local function table_label(name, anchor)
  return 'tbl:' .. file_key(name) .. '--' .. anchor
end

-- Line of the first occurrence of a text in this file, for warnings
local source_lines
local function line_of(needles)
  if type(needles) == 'string' then needles = { needles } end
  if not source_lines then
    source_lines = {}
    local f = io.open(this_file, 'r')
    if f then
      for line in f:lines() do table.insert(source_lines, line) end
      f:close()
    end
  end
  for _, needle in ipairs(needles) do
    for n, line in ipairs(source_lines) do
      if line:find(needle, 1, true) then return n end
    end
  end
end

-- Warning on stderr; in GitHub Actions also as an annotation on the line
local annotate = os.getenv('GITHUB_ACTIONS') == 'true'
local function warn(needle, msg, ...)
  msg = msg:format(...)
  local line = needle and line_of(needle)
  io.stderr:write(('[crossref-links] %s%s: %s\n')
    :format(this_name, line and (':' .. line) or '', msg))
  if annotate then
    io.stderr:write(('::warning file=%s%s,title=Link::%s\n')
      :format(this_name, line and (',line=' .. line) or '', msg))
  end
end

local stringify = pandoc.utils.stringify

-- "Table: Caption" -> "Caption", or nil
local function table_caption(header)
  if header.level ~= 6 then return nil end
  local caption = stringify(header.content):match('^Table:%s*(.*)$')
  return caption
end

-- Image file name without folder and extension: Images/a-b.svg -> a-b
local function image_name(src)
  return src:match('([^/]+)%.%w+$') or src:match('([^/]+)$')
end

-- Index of a file: headings (identifier -> {level, title, table}), its first
-- heading, and its figures (image name -> caption)
local function index_of(blocks)
  local idx = { headings = {}, figures = {}, anchors = {} }
  blocks:walk({
    Blocks = function(list)
      for i, el in ipairs(list) do
        if el.t == 'Header' and el.identifier ~= '' then
          local caption = table_caption(el)
          -- other files are read without html-tables.lua: an HTML table is
          -- still raw HTML there
          local nxt = list[i + 1]
          local is_table = caption ~= nil and nxt ~= nil and (nxt.t == 'Table'
            or (nxt.t == 'RawBlock' and nxt.format == 'html' and nxt.text:match('^%s*<table') ~= nil))
          idx.headings[el.identifier] = {
            level = el.level,
            title = is_table and caption or stringify(el.content),
            table = is_table,
          }
          if not is_table then idx.first = idx.first or el.identifier end
        end
      end
    end,
    RawBlock = function(el)
      if el.format == 'html' then
        for id in el.text:gmatch('<a%s+id="([^"]+)"') do idx.anchors[id] = true end
      end
    end,
    RawInline = function(el)
      if el.format == 'html' then
        for id in el.text:gmatch('<a%s+id="([^"]+)"') do idx.anchors[id] = true end
      end
    end,
    Figure = function(el)
      el.content:walk({ Image = function(img)
        idx.figures[image_name(img.src)] = stringify(el.caption.long)
      end })
    end,
  })
  return idx
end

local files = {}
local function file_index(name)
  if files[name] == nil then
    local f = io.open(folder .. name, 'r')
    if f then
      files[name] = index_of(pandoc.read(f:read('a'), READER).blocks)
      f:close()
    else
      files[name] = false
    end
  end
  return files[name]
end

-- All Markdown files of the specification, this one first
local function all_files()
  local names = { this_name }
  local ok, entries = pcall(pandoc.system.list_directory, folder == '' and '.' or folder)
  for _, entry in ipairs(ok and entries or {}) do
    if entry:match('%.md$') and entry ~= this_name then table.insert(names, entry) end
  end
  table.sort(names, function(a, b) return a == this_name or (b ~= this_name and a < b) end)
  return names
end

-- Caption of the figure that shows an image, searched in all Markdown files
local function figure_caption(name)
  for _, entry in ipairs(all_files()) do
    local idx = entry == this_name and own or file_index(entry)
    if idx and idx.figures[name] then return idx.figures[name] end
  end
  return nil
end

-- For comparing link texts and titles: case, spacing and a clause number typed
-- into a heading ("5.2.4 Types") do not matter
local function normalize(s)
  return (s:gsub('^%s*[%dA-Z][%d.]*%s+', ''):lower():gsub('%s+', ' '))
end

local function check_text(el, title, what)
  if #el.content == 1 and el.content[1].t == 'Cite' then return end -- [@sec:x](#x)
  local text = stringify(el.content)
  if normalize(text) ~= normalize(title) then
    warn({ text .. '](' .. el.target, '](' .. el.target }, 'link text "%s" is not the %s "%s"', text, what, title)
  end
end

local function cite(id, mode)
  return pandoc.Cite({}, { pandoc.Citation(id, mode or 'NormalCitation') })
end

-- Reference to a section: number only, "Clause"/"Annex" for a whole clause
local function section_reference(id, level, annex)
  local ref = cite(id, 'SuppressAuthor')
  if level == 1 then
    return { pandoc.Str(annex and 'Annex' or 'Clause'), pandoc.Str('\u{a0}'), ref }
  end
  return ref
end

local function link(el)
  local target = el.target
  if target:match('^%a[%w+.-]*:') or target:match('^//') then return nil end -- URL
  local file, anchor = target:match('^([^#]*)#?(.*)$')

  -- Figure: link to an image file
  local ext = file:match('%.(%w+)$')
  if ext and IMAGE[ext:lower()] and anchor == '' then
    local name = image_name(file)
    local caption = figure_caption(name)
    if caption then
      check_text(el, caption, 'figure caption')
    else
      warn('](' .. target, 'link to "%s": no figure shows this image', target)
    end
    return cite('fig:' .. name)
  end

  if file ~= '' and not file:match('%.md$') then
    warn('](' .. target, 'link to "%s" cannot be followed in the PDF; is it a citation?', target)
    return nil
  end
  if anchor:find(':', 1, true) then return nil end -- e.g. #fig:x, written for the PDF
  local name = (file == '' or file == this_name) and this_name or file
  local idx
  if name == this_name then
    if anchor == '' then return nil end
    if others[anchor] then return nil end -- e.g. <span id="..."> in this file
    idx = own
  else
    idx = file_index(name)
    if not idx then
      warn('](' .. target, 'link to "%s": file not found', target)
      return nil
    end
    if anchor == '' then anchor = idx.first or '' end
  end

  if idx.anchors[anchor] then
    if anchor:match('^rule%-') then
      -- grammar rule: "rule 2" / "rule 2.ii", numbered by LaTeX (no typed numbers);
      -- a link whose text is a rule number ([49.iii](#rule-...)) is the number only
      local ref = pandoc.Link({ pandoc.RawInline('latex', '\\ref*{' .. anchor .. '}') }, '#' .. anchor)
      if pandoc.utils.stringify(el.content):match('^%d+[%.%w]*$') then return ref end
      return { pandoc.Str('rule'), pandoc.Str('\u{a0}'), ref }
    end
    el.target = '#' .. anchor
    return el
  end
  local h = idx.headings[anchor]
  if not h then
    warn('](' .. target, 'link to "%s": no such heading or table', target)
    return section_reference(section_label(name, anchor))
  end
  if h.table then
    check_text(el, h.title, 'table caption')
    return cite(table_label(name, anchor))
  end
  check_text(el, h.title, 'heading title')
  return section_reference(section_label(name, anchor), h.level, name:match('^A_') ~= nil)
end

-- Table caption headings become the captions of their tables
local function blocks(list)
  local out, changed = pandoc.Blocks({}), false
  local i = 1
  while i <= #list do
    local el = list[i]
    local caption = el.t == 'Header' and table_caption(el)
    if caption and list[i + 1] and list[i + 1].t == 'Table' then
      local tbl = list[i + 1]
      if #tbl.caption.long > 0 then
        warn(caption, 'table "%s" has a caption heading and a "Table:" caption line', caption)
      end
      -- the caption is the heading text without "Table:" and the space after it
      local inlines = el.content:clone()
      if inlines[1] and inlines[1].t == 'Str' and inlines[1].text:match('^Table:') then
        local rest = inlines[1].text:gsub('^Table:', '')
        if rest == '' then inlines:remove(1) else inlines[1].text = rest end
        while inlines[1] and (inlines[1].t == 'Space' or inlines[1].t == 'SoftBreak') do
          inlines:remove(1)
        end
      end
      tbl.caption.long = pandoc.Blocks({ pandoc.Plain(inlines) })
      tbl.identifier = table_label(this_name, el.identifier)
      out:insert(tbl)
      i = i + 2
      changed = true
    else
      if caption then
        warn(stringify(el.content), 'heading "%s" is not directly followed by a table', stringify(el.content))
      end
      out:insert(el)
      i = i + 1
    end
  end
  return changed and out or nil
end

-- Figures without an identifier get fig:<image file name>
local function figure(el)
  if el.identifier ~= '' then return nil end
  local src
  el.content:walk({ Image = function(img) src = src or img.src end })
  if src then
    el.identifier = 'fig:' .. image_name(src)
    return el
  end
end

-- Headings are labelled sec:<file>--<identifier>
local function header(el)
  if el.identifier ~= '' and not el.identifier:find(':', 1, true) then
    el.identifier = section_label(this_name, el.identifier)
    return el
  end
end

-- @sec:types written directly: the label of that heading in this or another
-- file, shown as its number only, as for links
local function section_cite(el)
  for _, c in ipairs(el.citations) do
    local anchor = c.id:match('^sec:(.+)$')
    if anchor and not anchor:find('--', 1, true) then
      for _, name in ipairs(all_files()) do
        local idx = name == this_name and own or file_index(name)
        if idx and idx.headings[anchor] and not idx.headings[anchor].table then
          c.id = section_label(name, anchor)
          break
        end
      end
    end
    if anchor and c.mode ~= 'SuppressAuthor' then c.mode = 'SuppressAuthor' end
  end
  return el
end

local function anchor_target(el)
  if el.format ~= 'html' then return nil end
  local id = el.text:match('^%s*<a%s+id="([^"]+)"%s*>%s*</a>%s*$')
    or el.text:match('^%s*<a%s+id="([^"]+)"%s*>%s*$')
  if id then
    local raw = '\\phantomsection\\label{' .. id .. '}'
    return el.t == 'RawBlock' and pandoc.RawBlock('latex', raw) or pandoc.RawInline('latex', raw)
  end
end

local function is_grammar(list)
  local found = false
  list:walk({ RawInline = function(r)
    if r.format == 'html' and r.text:match('^<a%s+id="rule%-') then found = true end
  end })
  return found
end

local function grammar_list(el)
  if not is_grammar(el) then return nil end
  -- grammar text is not prose: keep straight quotes ("," and not “,”)
  el = el:walk({ Quoted = function(q)
    local mark = q.quotetype == 'DoubleQuote' and '"' or "'"
    local out = pandoc.Inlines({ pandoc.Str(mark) })
    out:extend(q.content)
    out:insert(pandoc.Str(mark))
    return out
  end })
  for _, item in ipairs(el.content) do
    for _, b in ipairs(item) do
      if b.t == 'OrderedList' then b.listAttributes = pandoc.ListAttributes(1, 'LowerRoman', 'Period') end
    end
  end
  return { pandoc.RawBlock('latex', '{\\renewcommand{\\theenumii}{\\roman{enumii}}\\makeatletter\\renewcommand{\\p@enumii}{\\theenumi.}\\makeatother'),
           el, pandoc.RawBlock('latex', '}') }
end

function Pandoc(doc)
  own = index_of(doc.blocks)
  doc.blocks:walk({
    Inline = function(el)
      if el.identifier and el.identifier ~= '' then others[el.identifier] = true end
    end,
    Block = function(el)
      if el.t ~= 'Header' and el.identifier and el.identifier ~= '' then
        others[el.identifier] = true
      end
    end,
  })
  -- top-down: only the outermost list of a grammar is a grammar list
  return doc:walk({ traverse = 'topdown', OrderedList = function(el)
              local r = grammar_list(el)
              if r then return r, false end
            end })
            :walk({ Link = link, RawBlock = anchor_target, RawInline = anchor_target })
            :walk({ Cite = section_cite })
            :walk({ Figure = figure })
            :walk({ Blocks = blocks })
            :walk({ Header = header })
end
