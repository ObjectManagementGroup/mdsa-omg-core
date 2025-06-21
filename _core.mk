.PHONY: gen clean core local md

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

clean:
	@echo --- Cleaning
	rm -rf build/
	rm -f "${pdfname}"

${build}:
	mkdir -p "${build}"

# This is a raw copy, it could be smarter, but this is sufficiently fast
${build}/GeneratedContent: ${build}
	cp -R ./GeneratedContent "${build}/GeneratedContent"

# LaTeX files support (local and core)
coretex := $(wildcard mdsa-omg-core/*.tex) $(wildcard mdsa-omg-core/*.sty) $(wildcard mdsa-omg-core/*.bib)
localtex := $(wildcard ./*.tex) $(wildcard ./*.bib)
markdowns := $(filter-out ./README.md, $(wildcard ./*.md))
core: $(subst mdsa-omg-core,${build},${coretex})
local: $(subst ./,${build}/,${localtex}) 
md: ${build} $(subst ./,${build}/,$(subst .md,.tex,${markdowns}))

# Order of rules is important. This order allows local .tex files to override core .tex files, 
# and local .md files to override both
${build}/%.tex: mdsa-omg-core/%.tex
	cp $< $@

${build}/%.tex: ./%.tex
	cp $< $@

# Zero length files converted by pandoc end up non-zero-length, which breaks OMG templates
${build}/%.tex: ./%.md
	@target=$$0 ; \
	size=$(shell du -ks $< | cut -f1) ; \
	if (( $${size} > 0 )); then \
		pandoc $< -f markdown --defaults ./omgLaTeX.yaml -t latex -o $@ ; \
	else \
		touch $@ ; \
	fi

${build}/%.sty: mdsa-omg-core/%.sty
	cp $< $@

# As above, local *.bib files override core *.bib files if both exist.
${build}/%.bib: mdsa-omg-core/%.bib
	cp $< $@

${build}/%.bib: ./%.bib
	cp $< $@


