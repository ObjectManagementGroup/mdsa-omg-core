-- Links to sections, written as on GitHub, become numbered references in the PDF.
--
-- Authors link to a heading as in any Markdown file on GitHub:
--   see [Types](#types)                      same file
--   see [Types](05_Object_Model.md#types)    other file
--   see [Object Model](05_Object_Model.md)   other file, its clause
-- GitHub shows the link text; the PDF shows the generated number instead:
-- "see 5.2.4", "see Clause 5", or "Annex A" / "A.2" for annexes (A_*.md). The
-- text around a link must therefore read well with either.
--
-- Headings get GitHub's identifiers (gfm_auto_identifiers), which
-- pandoc-crossref prefixes with "sec:" (autoSectionLabels). This filter runs
-- before pandoc-crossref and turns each such link into the reference
-- [-@sec:anchor]. References written as @sec:anchor are numbered the same way.
--
-- Warnings (the link is still converted, or left as it is):
-- - the link text is not the title of the heading it links to
-- - the heading or file is not found
-- - a relative link to another kind of file, which the PDF cannot follow

-- Must match the 'from' setting in omgLaTeX.yaml, for reading linked files
local READER = 'markdown+gfm_auto_identifiers+lists_without_preceding_blankline'
  .. '-blank_before_header-blank_before_blockquote'

local this_file = PANDOC_STATE.input_files[1] or ''
local this_name = this_file:match('([^/]*)$')
local folder = this_file:match('^(.*/)') or ''

-- Headings of a file: identifier -> {level, title}
local function headings_of(blocks)
  local h, first = {}, nil
  blocks:walk({ Header = function(el)
    if el.identifier ~= '' then
      h[el.identifier] = { level = el.level, title = pandoc.utils.stringify(el.content) }
      first = first or el.identifier
    end
  end })
  return h, first
end

local files = {}
local function file_headings(name)
  if files[name] == nil then
    local f = io.open(folder .. name, 'r')
    if f then
      local doc = pandoc.read(f:read('a'), READER)
      f:close()
      local h, first = headings_of(doc.blocks)
      files[name] = { headings = h, first = first }
    else
      files[name] = false
    end
  end
  return files[name]
end

local function warn(msg, ...)
  io.stderr:write(('[section-links] %s: ' .. msg .. '\n'):format(this_name, ...))
end

-- Reference to a section: number only, "Clause"/"Annex" for a whole clause
local function reference(id, level, annex)
  local cite = pandoc.Cite({}, { pandoc.Citation(id, 'SuppressAuthor') })
  if level == 1 then
    return { pandoc.Str(annex and 'Annex' or 'Clause'), pandoc.Str('\u{a0}'), cite }
  end
  return cite
end

-- For comparing link texts and titles: case, spacing and a clause number typed
-- into the heading ("5.2.4 Types") do not matter
local function normalize(s)
  return (s:gsub('^%s*[%dA-Z][%d.]*%s+', ''):lower():gsub('%s+', ' '))
end

local others = {}
local own = {}

local function link(el)
  local target = el.target
  if target:match('^%a[%w+.-]*:') or target:match('^//') then return nil end -- URL
  local file, anchor = target:match('^([^#]*)#?(.*)$')
  if file ~= '' and not file:match('%.md$') then
    warn('link to "%s" cannot be followed in the PDF; is it a citation?', target)
    return nil
  end
  if anchor:find(':', 1, true) then return nil end -- e.g. #fig:x, written for the PDF
  local name = (file == '' or file == this_name) and this_name or file
  local info
  if name == this_name then
    if anchor == '' then return nil end
    if others[anchor] then return nil end -- e.g. <span id="..."> in this file
    info = own
  else
    local f = file_headings(name)
    if not f then
      warn('link to "%s": file not found', target)
      return nil
    end
    info = f.headings
    if anchor == '' then anchor = f.first or '' end
  end
  local h = info[anchor]
  if not h then
    warn('link to "%s": no such heading', target)
    return reference('sec:' .. anchor)
  end
  -- A link whose text is a reference, [@sec:types](#types): keep the reference
  local text = pandoc.utils.stringify(el.content)
  if not (#el.content == 1 and el.content[1].t == 'Cite')
      and normalize(text) ~= normalize(h.title) then
    warn('link text "%s" is not the heading title "%s"', text, h.title)
  end
  return reference('sec:' .. anchor, h.level, name:match('^A_') ~= nil)
end

-- @sec:types written directly: number only, as for links
local function cite(el)
  for _, c in ipairs(el.citations) do
    if c.id:match('^sec:') and c.mode ~= 'SuppressAuthor' then
      c.mode = 'SuppressAuthor'
    end
  end
  return el
end

function Pandoc(doc)
  own = headings_of(doc.blocks)
  doc.blocks:walk({ Inline = function(el)
    if el.identifier and el.identifier ~= '' then others[el.identifier] = true end
  end, Block = function(el)
    if el.t ~= 'Header' and el.identifier and el.identifier ~= '' then
      others[el.identifier] = true
    end
  end })
  return doc:walk({ Link = link }):walk({ Cite = cite })
end
