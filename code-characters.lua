-- Reports typographic characters in code, such as curly quotes, which word
-- processors insert automatically and which get into specifications by copying
-- code from Word or PDF documents. Code allows only ASCII; the listings package
-- stops the build on these characters with "Invalid UTF-8 byte sequence", which
-- does not say where they are. This filter names the file, line and character,
-- and, in GitHub Actions, adds an annotation to that line of a pull request.
--
-- Characters a specification needs in code on purpose (e.g. an emoji in an
-- example) are not in the list below; declare them with the 'literate' option of
-- \lstset in _Specification_AuthorSettings.tex.

-- character -> what to write instead
local TYPOGRAPHIC = {
  ['‘'] = "'", ['’'] = "'", ['‚'] = "'", ['‛'] = "'", ['′'] = "'",
  ['“'] = '"', ['”'] = '"', ['„'] = '"', ['‟'] = '"', ['″'] = '"',
  ['«'] = '"', ['»'] = '"', ['‹'] = "'", ['›'] = "'",
  ['‐'] = '-', ['‑'] = '-', ['‒'] = '-', ['–'] = '-', ['—'] = '-', ['―'] = '-', ['−'] = '-',
  ['…'] = '...',
  ['\u{a0}'] = 'a space', ['\u{202f}'] = 'a space', ['\u{2009}'] = 'a space',
  ['\u{200b}'] = 'nothing', ['\u{ad}'] = 'nothing', ['\u{feff}'] = 'nothing',
  ['→'] = '->', ['←'] = '<-', ['⇒'] = '=>', ['⇐'] = '<=',
  ['©'] = '(c)', ['®'] = '(r)', ['™'] = '(tm)', ['•'] = '*',
}

local this_file = PANDOC_STATE.input_files[1] or ''
local this_name = this_file:match('([^/]*)$')
local annotate = os.getenv('GITHUB_ACTIONS') == 'true'

local source_lines
local function line_of(needle)
  if not source_lines then
    source_lines = {}
    local f = io.open(this_file, 'r')
    if f then
      for line in f:lines() do table.insert(source_lines, line) end
      f:close()
    end
  end
  for n, line in ipairs(source_lines) do
    if line:find(needle, 1, true) then return n end
  end
end

local function check(code)
  for line in (code .. '\n'):gmatch('(.-)\n') do
    local seen = {}
    for _, cp in utf8.codes(line) do
      local ch = utf8.char(cp)
      local instead = TYPOGRAPHIC[ch]
      if instead and not seen[ch] then
        seen[ch] = true
        local n = line_of(line)
        local msg = ('code contains %s (U+%04X), probably copied from a word processor or PDF; write %s instead')
          :format(ch, cp, instead)
        io.stderr:write(('[code-characters] %s%s: %s\n')
          :format(this_name, n and (':' .. n) or '', msg))
        if annotate then
          io.stderr:write(('::error file=%s%s,title=Code::%s\n')
            :format(this_name, n and (',line=' .. n) or '', msg))
        end
      end
    end
  end
end

return {
  { Code = function(el) check(el.text) end,
    CodeBlock = function(el) check(el.text) end },
}
