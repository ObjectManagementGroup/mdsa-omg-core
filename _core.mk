.PHONY: gen clean core local md images rfp spec debug check

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
rfp: "${build}" tools rfp_core local md images
	@echo --- Creating PDF
	mv "${build}/${doc}.tex" "${build}/${pdfnamebase}.tex"
	if [ -f "${source}/.latexmkrc" ]; then cp "${source}/.latexmkrc" "${build}/.latexmkrc" ; fi
	touch "${build}/.latexmkrc" 2>/dev/null ;
	cd "${build}" && latexmk -bibtex -pdf -shell-escape -auxdir=. -outdir="${source}" "./${pdfnamebase}.tex" ${_outputstream}

spec: doc="Specification"
spec: "${build}" tools "${gencondir}" core local md images 
	@echo --- Creating PDF ;
	mv "${build}/${doc}.tex" "${build}/${pdfnamebase}.tex" ;
	if [ -f "${source}/.latexmkrc" ]; then cp "${source}/.latexmkrc" "${build}/.latexmkrc" ; fi
	touch "${build}/.latexmkrc" 2>/dev/null ;
	cd "${build}" && latexmk -bibtex -pdf -shell-escape -auxdir=. -outdir="${source}" "./${pdfnamebase}.tex" ${_outputstream}

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
${build}/%.tex: ${source}/%.md ${build}/omgLaTeX.yaml ${build}/crossref-links.lua ${build}/code-characters.lua
	@size=$(shell du -ks $< | cut -f1) ; \
	if (( $${size} > 0 )); then \
		echo "pandoc $< -> $@" ; \
		pandoc $< --defaults "${build}/omgLaTeX.yaml" -o $@ ; \
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

${build}/%.lua: mdsa-omg-core/%.lua
	cp $< $@

# SVG is the only format formally accepted by OMG for documents
${build}/Images/%.svg: ${source}/Images/%.svg
	mkdir -p "$(dir $@)"
	cp $< $@
