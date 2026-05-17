# =============================================================================
# Root Snakefile — user rules loaded by showyourwork.
#
# Produces, alongside the default tectonic-built `paper.pdf`:
#   - paper-submission.pdf : built with pdflatex from a staged clean copy of
#                            src/tex (publisher eceasst.cls, no showyourwork).
#                            This is the journal-equivalent rendering.
#   - paper-submission.tar.gz : the staged source tree, ready to send to the
#                               publisher.
#
# See notes/showyourwork-tinytex.md for background.
# =============================================================================

# The first rule is the default target. `showyourwork build` ends up running
# this, so both the tectonic preview and the pdflatex submission build run.
rule all:
    input:
        "paper.pdf",
        "paper-submission.pdf",
        "paper-submission.tar.gz"


# -----------------------------------------------------------------------------
# tinytex package setup (one-time per environment)
# -----------------------------------------------------------------------------
# pdflatex needs a handful of CTAN packages that tinytex does not ship by
# default. tlmgr is idempotent, but a sentinel file lets snakemake skip the
# install check on every build.
#
# The sentinel lives under build/ so it's gitignored and disposable.
rule setup_tinytex:
    output:
        touch("build/.tinytex-installed")
    conda:
        "env-tinytex.yml"
    shell:
        r"""
        # Pin tlmgr to the frozen TL2025 archive (tinytex from conda is
        # currently TL2025; CTAN now serves TL2026 which tlmgr refuses to mix).
        tlmgr option repository \
            https://ftp.math.utah.edu/pub/tex/historic/systems/texlive/2025/tlnet-final \
            || true
        tlmgr install hypcap caption booktabs pgf orcidlink rsfs courier
        """


# -----------------------------------------------------------------------------
# Stage a clean copy of src/tex for submission
# -----------------------------------------------------------------------------
# rsync everything from src/tex except:
#   - showyourwork.sty (showyourwork-specific)
#   - LaTeX build artifacts left over from local pdflatex runs
#   - the patched eceasst.cls and its .publisher sibling
# Then drop the pristine publisher .cls in as eceasst.cls and strip the
# \usepackage{showyourwork} line from paper.tex.
rule submission_stage:
    input:
        tex           = "src/tex/paper.tex",
        bib           = "src/tex/bib.bib",
        cls_publisher = "src/tex/eceasst.cls.publisher",
    output:
        directory("build/submission")
    shell:
        r"""
        rm -rf {output}
        mkdir -p {output}
        # Use tar with excludes for a portable copy (rsync isn't in tinytex env).
        tar -c -C src/tex \
            --exclude='showyourwork.sty' \
            --exclude='eceasst.cls' \
            --exclude='eceasst.cls.publisher' \
            --exclude='*.aux' \
            --exclude='*.bbl' \
            --exclude='*.blg' \
            --exclude='*.log' \
            --exclude='*.fls' \
            --exclude='*.fdb_latexmk' \
            --exclude='*.out' \
            --exclude='*.synctex.gz' \
            --exclude='missfont.log' \
            --exclude='paper.pdf' \
            --exclude='.gitignore' \
            . | tar -x -C {output}
        cp {input.cls_publisher} {output}/eceasst.cls
        sed -i '/\\usepackage{{showyourwork}}/d' {output}/paper.tex
        """


# -----------------------------------------------------------------------------
# Build paper-submission.pdf via pdflatex from the staged tree
# -----------------------------------------------------------------------------
rule submission_pdf:
    input:
        srcdir = "build/submission",
        setup  = "build/.tinytex-installed"
    output:
        pdf = "paper-submission.pdf"
    conda:
        "env-tinytex.yml"
    shell:
        r"""
        cd {input.srcdir}
        pdflatex -interaction=nonstopmode paper.tex
        # bibtex may exit non-zero on warnings (malformed entries, missing
        # fields). Tolerate it here — undefined refs surface as LaTeX warnings,
        # and we'd rather have a PDF for review than no PDF.
        bibtex paper || true
        pdflatex -interaction=nonstopmode paper.tex
        pdflatex -interaction=nonstopmode paper.tex
        cd - >/dev/null
        cp {input.srcdir}/paper.pdf {output.pdf}
        """


# -----------------------------------------------------------------------------
# Submission tarball: clean source only, no build artifacts
# -----------------------------------------------------------------------------
# Depends on submission_pdf so the build is proven to succeed from the same
# tree we ship. The tarball itself excludes pdflatex's intermediate files.
rule submission_tarball:
    input:
        srcdir = "build/submission",
        pdf    = "paper-submission.pdf"
    output:
        "paper-submission.tar.gz"
    shell:
        r"""
        tar czf {output} -C build \
            --exclude='*.aux' \
            --exclude='*.bbl' \
            --exclude='*.blg' \
            --exclude='*.log' \
            --exclude='*.fls' \
            --exclude='*.fdb_latexmk' \
            --exclude='*.out' \
            --exclude='*.synctex.gz' \
            --exclude='missfont.log' \
            --exclude='paper.pdf' \
            submission
        """
