# OMG MDSA - CORE 
None of these files are intended to be edited by authors of OMG documents.  These drive the entire LaTeX process, do *not* attempt to replace or edit these files, unless you are 110% sure of what you are doing.  (And, if you do edit because you need something, let OMG Editing know so they can discuss incorporating it into the main branch.)

Periodically OMG staff and the Architecture Board may issue updates to this repository. If you have modified files, you risk merge errors that will prevent you from automatically incorporating fixes, formatting tweaks, updated boilerplate, and other benefits.

If you need to add LaTeX packages, new commands, etc, place them into the appropriate `_*_AuthorSettings.tex` at the top level of your document repository.  That's your sandbox to do with what you please.  Again, the files in this repository are to be considered read-only, and only described here as a warning for the curious.  

Periodically you may be notified of an update to these files by OMG Staff.  If you are working in the Overleaf environment, select each updated file in the file browser, and click "Refresh" to get the newest version.  If you are working from a git clone, fetch changes to your local repository using `git submodule update` within the `mdsa-omg-core` directory.

## Document LaTeX files
- `RFP.tex`
: The main LaTeX file for generating Requests for Proposals (RFPs).  This is what is designated as the 'top' file. It exists solely to give tools a 'real' file to latch onto, and it then passes control to the next file on this list.  While this file is editable, it will do little good to do so, the entire document structure is handled by...

- `RFP_Template.tex`
: The main core template document for RFPs. All formatting and structure is controlled starting with this file.

- `Specification.tex`
: The main LaTeX file for generating specifications.  This is what is designated as the 'top' file. It exists solely to give tools a 'real' file to latch onto, and it then passes control to the next file on this list.  While this file is editable, it will do little good to do so, the entire document structure is handled by...

- `Specification_Template.tex`
: The main core template document for specifications. All formatting and structure is controlled starting with this file.

## Style files
Style (.sty) files are LaTeX command bundles:
- `omg.sty`                     Provides the basics used across all OMG documents.
- `omg_rfp.sty`                 Primary style for creating an RFP.
- `omg_specification.sty`       Primary style for creating a submission in response to an RFP, and maintaining the resulting specification through its lifetime.

## Bibliography files
.bib files are bibliography databases.  These are provided for your convenience.  You can refer to any of these entries via \cite{<entrycode>} and it will build your bibliography for you according to OMG requirements.

- `iso.bib`         ISO standards
- `omg.bib`         OMG standards
- `w3.bib`          W3 standards

## Other
- `_core.mk`
: The core Makefile that is included by Makefiles in the document production repositories.
- `omgLaTeX.yaml`
: A configuration file for generating OMG compliant LaTeX files from Markdown files. _*EXPERIMENTAL*_