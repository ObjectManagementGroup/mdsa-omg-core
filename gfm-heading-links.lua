-- Links to headings, written as on GitHub, also work in the PDF.
--
-- Headings get GitHub's identifiers (gfm_auto_identifiers), and pandoc-crossref
-- prefixes them with "sec:" (autoSectionLabels), so that '## Types' can be
-- referenced as @sec:types. Runs before pandoc-crossref:
--
-- - [@sec:types](#types) or [@sec:types](05_Object_Model.md#types): a reference
--   that is also a link on GitHub. The link is dropped, so the PDF shows just
--   the reference ("Section 5.2.4"). A warning is printed if the reference and
--   the link target differ, as GitHub would then lead somewhere else.
-- - [Types](#types) or [Types](05_Object_Model.md#types): a link with its own
--   text. It is pointed to "#sec:types", the identifier of the heading in the
--   PDF. Links to other identifiers in the same file (e.g. a <span id="...">)
--   are left as they are.

local headings, others = {}, {}

local function collect(el)
  if el.identifier and el.identifier ~= '' then
    if el.t == 'Header' then headings[el.identifier] = true
    else others[el.identifier] = true end
  end
end

local function anchor_of(target)
  local file, anchor = target:match('^([^:/?#]*)#(.+)$')
  if not anchor then return nil end
  if file ~= '' and not file:match('%.md$') then return nil end
  return file, anchor
end

local function link(el)
  local file, anchor = anchor_of(el.target)
  if not anchor then return nil end

  -- A link whose text is a single reference: keep only the reference
  if #el.content == 1 and el.content[1].t == 'Cite'
      and #el.content[1].citations == 1 then
    local id = el.content[1].citations[1].id
    if id:match('^%a+:') then
      if id ~= 'sec:' .. anchor and id ~= anchor then
        io.stderr:write(('[gfm-heading-links] WARNING: @%s links to #%s on GitHub\n')
          :format(id, anchor))
      end
      return el.content[1]
    end
  end

  -- A link with its own text
  if anchor:find(':', 1, true) then return nil end
  if file == '' and others[anchor] and not headings[anchor] then return nil end
  el.target = '#sec:' .. anchor
  return el
end

function Pandoc(doc)
  doc:walk({ Block = collect, Inline = collect })
  return doc:walk({ Link = link })
end
