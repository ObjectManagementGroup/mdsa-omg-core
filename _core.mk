.PHONY: gen clean core local md images rfp spec debug check clauses

# Several things break if only plain sh is used
SHELL := /bin/bash

# Target 'debug' re-enables output from LaTeX run
_outputstream := 2>&1 > /dev/null
debug: _outputstream := 
debug: all

# Set if not set in Makefile for local LaTeX installation
build ?= ./build
source ?= /source

specacro = $(shell specsetup --lookup specacro --setupFile "${source}/_${doc}_Setup.tex")
version  = $(shell specsetup --lookup version --setupFile "${source}/_${doc}_Setup.tex")

rfp: doc="RFP"
# RFP files are fragments inside the RFP template's sections: '#' is a section
# there, not a chapter as in specifications
rfp: _pandoc_opts=--top-level-division=section
rfp: "${build}" tools rfp_core local md images
	@echo --- Creating PDF
	mv "${build}/${doc}.tex" "${build}/${pdfnamebase}.tex"
	if [ -f "${source}/.latexmkrc" ]; then cp "${source}/.latexmkrc" "${build}/.latexmkrc" ; fi
	touch "${build}/.latexmkrc" 2>/dev/null ;
	cd "${build}" && max_print_line=10000 latexmk -bibtex -pdf -shell-escape -auxdir=. -outdir="${source}" "./${pdfnamebase}.tex" ${_outputstream}

spec: doc="Specification"
spec: "${build}" tools "${gencondir}" core local md images clauses
	@echo --- Creating PDF ;
	mv "${build}/${doc}.tex" "${build}/${pdfnamebase}.tex" ;
	if [ -f "${source}/.latexmkrc" ]; then cp "${source}/.latexmkrc" "${build}/.latexmkrc" ; fi
	touch "${build}/.latexmkrc" 2>/dev/null ;
	cd "${build}" && max_print_line=10000 latexmk -bibtex -pdf -shell-escape -auxdir=. -outdir="${source}" "./${pdfnamebase}.tex" ${_outputstream}

# Clause files have zero-padded names, so that they sort in clause order: 00_* for the
# submission clause, 01_Scope to 06_Additional, then one file per clause from Clause 7
# on (07_Title, 08_Title, ...), and A_Annexes.
# - Unpadded names of older specifications (1_Scope, 7+_Technical_Content, ...) are
#   copied to the padded names the templates use, so they keep working.
# - Clause 7 and later: every file 07_* to 99_* is included in name order, unless the
#   specification has its own 07+_Technical_Content (or 7+_Technical_Content) with an
#   explicit list.
clauses: local md
	@cd "${build}" && \
	for f in [0-7]_*.tex 7+_*.tex ; do \
		if [ -e "$$f" ] && [ ! -e "0$$f" ] ; then cp "$$f" "0$$f" ; fi ; \
	done ; \
	if [ ! -e 07+_Technical_Content.tex ] ; then \
		for f in $$(ls [0-9][0-9]_*.tex 2>/dev/null | sort) ; do \
			case "$$f" in 0[0-6]_*) ;; *) echo "\\subimport{}{$${f%.tex}}" ;; esac ; \
		done > 07+_Technical_Content.tex ; \
		echo "--- Clauses from 7 on: $$(grep -c subimport 07+_Technical_Content.tex) files" ; \
	fi

# Build, then check for problems that LaTeX does not treat as errors (undefined
# references and citations, unprocessed Markdown references). Fails if any are found.
check: all
	@echo --- Checking ${pdfnamebase}
	@bash mdsa-omg-core/check.sh "${build}/${pdfnamebase}.log" $(subst ${source}/,${build}/,$(subst .md,.tex,${markdowns}))

# Only generate from the model if there is an appropriate ${specacro}.config file. I.e. UML.config or BPMN.config.
gen: "${gencondir}"
	@echo --- Generating from model
	@if [ -f "${specacro}.config" ]; then \
		./mdsa-tools/omgmdsa/md2LaTeX.py --config "${specacro}.config"; \
	else \
		echo "[MDSA] No "${specacro}.config" file, not building from model"; \
	fi

"${gencondir}":
	mkdir -p "${gencondir}"

# Checks to see if specsetupfile is installed correctly
specsetupfile := $(shell command -v specsetup 2> /dev/null)

tools:
ifndef specsetupfile
	cd ./mdsa-tools ; pip install -e .
endif

clean:
	@echo --- Cleaning
	rm -rf "${build}"
	rm -f "${pdfnamebase}.pdf"

"${build}":
	mkdir -p "${build}"

# This is a raw copy, it could be smarter, but this is sufficiently fast
"${build}/GeneratedContent": "${build}"
	cp -R "${source}/GeneratedContent" "${build}/GeneratedContent"


# LaTeX files support (local and core)
coretex := $(wildcard mdsa-omg-core/*.sty) $(wildcard mdsa-omg-core/*.bib) $(wildcard mdsa-omg-core/*.yaml) $(wildcard mdsa-omg-core/*.latex) $(wildcard mdsa-omg-core/*.lua)
localtex := $(wildcard ${source}/*.tex) $(wildcard ${source}/*.bib)
markdowns := $(filter-out ${source}/README.md, $(wildcard ${source}/*.md))
core: $(subst mdsa-omg-core,${build},${coretex} $(wildcard mdsa-omg-core/*.tex) )
rfp_core: $(subst mdsa-omg-core,${build},$(wildcard mdsa-omg-core/RFP*) ${coretex})
spec_core: $(subst mdsa-omg-core,${build},$(wildcard mdsa-omg-core/*pecification*) ${coretex})
local: $(subst ${source}/,${build}/,${localtex}) 
md: ${build} $(subst ${source}/,${build}/,$(subst .md,.tex,${markdowns})) ${build}/pandoc-preamble.tex

# LaTeX definitions that content converted from Markdown depends on (tables, images,
# inline code). Generated from pandoc's own template, so they match the pandoc version
# in use. Included by the templates with \InputIfFileExists.
${build}/pandoc-preamble.tex: ${markdowns} ${build}/omgPreamble.yaml ${build}/pandoc-preamble.latex
	@if [ -n "${markdowns}" ]; then \
		echo "pandoc -> $@" ; \
		pandoc ${markdowns} --defaults "${build}/omgPreamble.yaml" -o $@ ; \
	else \
		touch $@ ; \
	fi
imagefiles := $(subst ${source}/,${build}/,$(wildcard ${source}/Images/*.svg))
images: ${imagefiles}
# echo ${imagefiles}
# ${build}/Images: ${build}
# 	mkdir -p ${build}/Images


# Order of rules is important: for pattern rules with the same stem, GNU make
# uses the FIRST matching rule. Local .md files therefore come first, then local
# .tex files, then core .tex files: local .md files override local .tex files,
# and both override core .tex files.

# Zero length files converted by pandoc end up non-zero-length, which breaks OMG templates
# Don't convert empty files, just touch
corelua := $(addprefix ${build}/,$(notdir $(wildcard mdsa-omg-core/*.lua)))

${build}/%.tex: ${source}/%.md ${build}/omgLaTeX.yaml ${corelua}
	@size=$(shell du -ks $< | cut -f1) ; \
	if (( $${size} > 0 )); then \
		echo "pandoc $< -> $@" ; \
		pandoc $< --defaults "${build}/omgLaTeX.yaml" ${_pandoc_opts} -o $@ ; \
	else \
		touch $@ ; \
	fi

${build}/%.tex: ${source}/%.tex
	cp $< $@

${build}/%.tex: mdsa-omg-core/%.tex
	cp $< $@

${build}/%.sty: mdsa-omg-core/%.sty
	cp $< $@

# As above, local *.bib and *.yaml files override core files if both exist.
${build}/%.bib: ${source}/%.bib
	cp $< $@

${build}/%.bib: mdsa-omg-core/%.bib
	cp $< $@

${build}/%.yaml: ${source}/%.yaml
	cp $< $@

${build}/%.yaml: mdsa-omg-core/%.yaml
	cp $< $@

${build}/%.latex: mdsa-omg-core/%.latex
	cp $< $@

# A specification's own specification.lua (or other filter) overrides the core's
${build}/%.lua: ${source}/%.lua
	cp $< $@

${build}/%.lua: mdsa-omg-core/%.lua
	cp $< $@

# SVG is the only format formally accepted by OMG for documents
${build}/Images/%.svg: ${source}/Images/%.svg
	mkdir -p "$(dir $@)"
	cp $< $@
