#!/bin/bash
# Checks a finished MDSA build for problems that LaTeX does not treat as errors,
# so that they do not go unnoticed in the PDF. Called by 'make check'.
#
# Usage: check.sh LATEX_LOG [CONVERTED_MARKDOWN.tex ...]
#
# Exit status 1 if any problem is found.

log="$1"; shift
status=0

if [ ! -f "$log" ]; then
  echo "[check] LaTeX log not found: $log"
  exit 1
fi

# 1. Unresolved references and citations, links to missing targets ('Hyper
#    reference'), duplicate labels (show as "??", bold keys or dead links in the PDF)
# The build runs LaTeX with max_print_line=10000, so warnings are not wrapped
# across lines; LaTeX's summary warnings catch them in any case.
problems=$(grep -E "(Reference|reference|Citation) .* undefined|multiply defined|There were undefined references|There were multiply-defined labels" "$log")
if [ -n "$problems" ]; then
  echo "$problems"
  if [ "$GITHUB_ACTIONS" = true ]; then
    echo "$problems" | sed -E 's/^(LaTeX Warning: )?/::error title=make check::/'
  fi
  echo "[check] FAILED: undefined references or citations, or duplicate labels (see above)"
  status=1
fi

# 2. Markdown references that pandoc did not process, e.g. because pandoc-crossref
#    did not run. Code (code blocks, inline code) is ignored, since it may show
#    the syntax on purpose.
for tex in "$@"; do
  [ -f "$tex" ] || continue
  hits=$(perl -0777 -ne '
    s/\\begin\{(lstlisting|Shaded|verbatim|Verbatim)\}.*?\\end\{\1\}//gs;
    s/\\lstinline!([^!]*)!//g;
    s/\\(?:texttt|passthrough)(\{(?:[^{}]++|(?1))*\})//g;
    print "$ARGV: $&\n" while /^.*(?:\@(?:sec|fig|tbl|eq|lst):|\{\[\}\@).*$/mg;
  ' "$tex")
  if [ -n "$hits" ]; then
    echo "$hits"
    if [ "$GITHUB_ACTIONS" = true ]; then
      name=$(basename "$tex" .tex)
      echo "$hits" | sed -E "s/^[^:]*: (.*)$/::error file=$name.md,title=make check::unprocessed reference: \\1/" >&2
    fi
    echo "[check] FAILED: unprocessed Markdown references or citations in $tex (see above)"
    status=1
  fi
done

if [ $status -eq 0 ]; then
  echo "[check] OK: no undefined references or citations, no unprocessed Markdown references"
fi
exit $status
