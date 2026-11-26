-- Markdown links to headings, written as on GitHub, also work in the PDF.
--
-- Headings get GitHub's identifiers (gfm_auto_identifiers), and pandoc-crossref
-- prefixes them with "sec:" (autoSectionLabels), so that they can be referenced
-- as @sec:figures. A link written for GitHub, [Figures](#figures) or
-- [Figures](09_Figures.md#figures), then points to "#sec:figures" in the PDF.
-- Runs after pandoc-crossref. Links to identifiers defined in the same file
-- (e.g. a <span id="...">) are left as they are.

local ids = {}

local function collect(el)
  if el.identifier and el.identifier ~= '' then ids[el.identifier] = true end
end

local function retarget(link)
  local file, anchor = link.target:match('^([^:/?#]*)#(.+)$')
  if not anchor then return nil end
  if file ~= '' and not file:match('%.md$') then return nil end
  if file == '' and ids[anchor] then return nil end
  if anchor:find(':', 1, true) then
    link.target = '#' .. anchor
  else
    link.target = '#sec:' .. anchor
  end
  return link
end

function Pandoc(doc)
  doc:walk({ Block = collect, Inline = collect })
  return doc:walk({ Link = retarget })
end
