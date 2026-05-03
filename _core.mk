.PHONY: gen clean core local md images rfp spec debug

# Several things break if only plain sh is used
SHELL := /bin/bash

# Target 'debug' re-enables output from LaTeX run
_outputstream := 2>&1 > /dev/null
debug: _outputstream := ""
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
	cd "${build}" && latexmk -bibtex -pdf -auxdir=. -outdir="${source}" "./${pdfnamebase}.tex" ${_outputstream}

spec: doc="Specification"
spec: ${build} tools ${gencondir} core local md images 
	@echo --- Creating PDF ;
	mv "${build}/${doc}.tex" "${build}/${pdfnamebase}.tex" ;
	cd "${build}" && latexmk -bibtex -pdf -auxdir=. -outdir="${source}" "./${pdfnamebase}.tex" ${_outputstream}

# Only generate from the model if there is an appropriate ${specacro}.config file. I.e. UML.config or BPMN.config.
gen: ${gencondir}
	@echo --- Generating from model
	@if [ -f "${specacro}.config" ]; then \
		./mdsa-tools/omgmdsa/md2LaTeX.py --config "${specacro}.config"; \
	else \
		echo "[MDSA] No "${specacro}.config" file, not building from model"; \
	fi

${gencondir}:
	mkdir -p "${gencondir}"

specsetupfile := $(shell command -v specsetup 2> /dev/null)

tools:
ifndef specsetupfile
	cd ./mdsa-tools ; pip install -e .
endif

clean:
	@echo --- Cleaning
	rm -rf "${build}"
	rm -f "${pdfnamebase}.pdf"

${build}:
	mkdir -p "${build}"

# This is a raw copy, it could be smarter, but this is sufficiently fast
${build}/GeneratedContent: ${build}
	cp -R "${source}/GeneratedContent" "${build}/GeneratedContent"


# LaTeX files support (local and core)
coretex := $(wildcard mdsa-omg-core/*.sty) $(wildcard mdsa-omg-core/*.bib) $(wildcard mdsa-omg-core/*.yaml) 
localtex := $(wildcard ${source}/*.tex) $(wildcard ${source}/*.bib)
markdowns := $(filter-out ${source}/README.md, $(wildcard ${source}/*.md))
core: $(subst mdsa-omg-core,${build},${coretex} $(wildcard mdsa-omg-core/*.tex) )
rfp_core: $(subst mdsa-omg-core,${build},$(wildcard mdsa-omg-core/RFP*) ${coretex})
spec_core: $(subst mdsa-omg-core,${build},$(wildcard mdsa-omg-core/*pecification*) ${coretex})
local: $(subst ${source}/,${build}/,${localtex}) 
md: ${build} $(subst ${source}/,${build}/,$(subst .md,.tex,${markdowns}))
imagefiles := $(subst ${source}/,${build}/,$(wildcard ${source}/Images/*.svg))
images: ${imagefiles}
# echo ${imagefiles}
# ${build}/Images: ${build}
# 	mkdir -p ${build}/Images


# Order of rules is important. This order allows local .tex files to override core .tex files, 
# and local .md files to override both
${build}/%.tex: mdsa-omg-core/%.tex
	cp $< $@

${build}/%.tex: ${source}/%.tex
	cp $< $@

# Zero length files converted by pandoc end up non-zero-length, which breaks OMG templates
# Don't convert empty files, just touch
${build}/%.tex: ${source}/%.md
	@size=$(shell du -ks $< | cut -f1) ; \
	if (( $${size} > 0 )); then \
		pandoc $< -f markdown --defaults "${build}/omgLaTeX.yaml" -t latex -o $@ ; \
	else \
		touch $@ ; \
	fi

${build}/%.sty: mdsa-omg-core/%.sty
	cp $< $@

# As above, local *.bib files override core *.bib files if both exist.
${build}/%.bib: mdsa-omg-core/%.bib
	cp $< $@

${build}/%.bib: ${source}/%.bib
	cp $< $@

${build}/%.yaml: mdsa-omg-core/%.yaml
	cp $< $@

${build}/%.yaml: ${source}/%.yaml
	cp $< $@

# SVG is the only format formally accepted by OMG for documents
${build}/Images/%.svg: ${source}/Images/%.svg
	echo $<
	cp $< $0
