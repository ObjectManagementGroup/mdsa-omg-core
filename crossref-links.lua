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
-- GitHub shows the link text and follows the link; the PDF shows the generated
-- number instead, so the text around a link must read well with either.
--
-- How: headings get GitHub's identifiers (gfm_auto_identifiers), which
-- pandoc-crossref prefixes with "sec:" (autoSectionLabels). This filter runs
-- before pandoc-crossref. It gives each figure the identifier fig:<image file
-- name>, turns each table caption heading into the caption of its table with
-- the identifier tbl:<heading identifier>, and turns each link into the
-- matching reference (@fig:..., @tbl:..., [-@sec:...]). References written
-- directly as @sec:..., @fig:..., @tbl:... and {#fig:...}/{#tbl:...} labels
-- keep working; section references are shown without "Section" as above.
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

local this_file = PANDOC_STATE.input_files[1] or ''
local this_name = this_file:match('([^/]*)$')
local folder = this_file:match('^(.*/)') or ''

local function warn(msg, ...)
  io.stderr:write(('[crossref-links] %s: ' .. msg .. '\n'):format(this_name, ...))
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
  local idx = { headings = {}, figures = {} }
  blocks:walk({
    Blocks = function(list)
      for i, el in ipairs(list) do
        if el.t == 'Header' and el.identifier ~= '' then
          local caption = table_caption(el)
          local is_table = caption ~= nil and list[i + 1] ~= nil and list[i + 1].t == 'Table'
          idx.headings[el.identifier] = {
            level = el.level,
            title = is_table and caption or stringify(el.content),
            table = is_table,
          }
          if not is_table then idx.first = idx.first or el.identifier end
        end
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

-- Caption of the figure that shows an image, searched in all Markdown files
local function figure_caption(name)
  local ok, entries = pcall(pandoc.system.list_directory, folder == '' and '.' or folder)
  for _, entry in ipairs(ok and entries or {}) do
    if entry:match('%.md$') then
      local idx = file_index(entry)
      if idx and idx.figures[name] then return idx.figures[name] end
    end
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
    warn('link text "%s" is not the %s "%s"', text, what, title)
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

local own, others = nil, {}

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
      warn('link to "%s": no figure shows this image', target)
    end
    return cite('fig:' .. name)
  end

  if file ~= '' and not file:match('%.md$') then
    warn('link to "%s" cannot be followed in the PDF; is it a citation?', target)
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
      warn('link to "%s": file not found', target)
      return nil
    end
    if anchor == '' then anchor = idx.first or '' end
  end

  local h = idx.headings[anchor]
  if not h then
    warn('link to "%s": no such heading or table', target)
    return section_reference('sec:' .. anchor)
  end
  if h.table then
    check_text(el, h.title, 'table caption')
    return cite('tbl:' .. anchor)
  end
  check_text(el, h.title, 'heading title')
  return section_reference('sec:' .. anchor, h.level, name:match('^A_') ~= nil)
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
        warn('table "%s" has a caption heading and a "Table:" caption line', caption)
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
      tbl.identifier = 'tbl:' .. el.identifier
      out:insert(tbl)
      i = i + 2
      changed = true
    else
      if caption then
        warn('heading "%s" is not directly followed by a table', stringify(el.content))
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

-- @sec:types written directly: number only, as for links
local function section_cite(el)
  for _, c in ipairs(el.citations) do
    if c.id:match('^sec:') and c.mode ~= 'SuppressAuthor' then
      c.mode = 'SuppressAuthor'
    end
  end
  return el
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
  return doc:walk({ Link = link })
            :walk({ Cite = section_cite })
            :walk({ Figure = figure })
            :walk({ Blocks = blocks })
end
