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
if grep -E "(Reference|reference|Citation) .* undefined|multiply defined" "$log"; then
  echo "[check] FAILED: undefined references or citations, or duplicate labels (see above)"
  status=1
fi

# 2. Markdown references that pandoc did not process, e.g. because pandoc-crossref
#    did not run. Code (\lstinline!...! and lstlisting blocks) is ignored, since
#    it may show the syntax on purpose.
for tex in "$@"; do
  [ -f "$tex" ] || continue
  hits=$(awk '/\\begin\{lstlisting\}/{code=1} !code{print FILENAME": "FNR": "$0} /\\end\{lstlisting\}/{code=0}' "$tex" \
    | sed -E 's/\\lstinline!([^!]*)!//g' \
    | grep -E '@(sec|fig|tbl|eq|lst):|\{\[\}@')
  if [ -n "$hits" ]; then
    echo "$hits"
    echo "[check] FAILED: unprocessed Markdown references or citations in $tex (see above)"
    status=1
  fi
done

if [ $status -eq 0 ]; then
  echo "[check] OK: no undefined references or citations, no unprocessed Markdown references"
fi
exit $status
