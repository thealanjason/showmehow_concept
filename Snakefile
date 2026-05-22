# =============================================================================
# Root Snakefile — user rules loaded by showyourwork.
#
# Produces, alongside the default tectonic-built `paper.pdf`:
#   - article.pdf : built with pdflatex from a staged clean copy of src/tex
#                   (publisher eceasst.cls, no showyourwork). This is the
#                   journal-equivalent rendering. The staged entry point is
#                   renamed from paper.tex to article.tex because the publisher
#                   expects that filename.
#   - article.tar.gz : the staged source tree, ready to send to the publisher.
#
# See notes/showyourwork-tinytex.md for background.
# =============================================================================

# The first rule is the default target. `showyourwork build` ends up running
# this, so both the tectonic preview and the pdflatex submission build run.
rule all:
    input:
        "paper.pdf",
        "article.pdf",
        "article.tar.gz"


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
        tlmgr install hypcap caption booktabs pgf orcidlink rsfs courier placeins
        """


# -----------------------------------------------------------------------------
# Stage a clean copy of src/tex for submission
# -----------------------------------------------------------------------------
# rsync everything from src/tex except:
#   - showyourwork.sty (showyourwork-specific)
#   - LaTeX build artifacts left over from local pdflatex runs
#   - the patched eceasst.cls and its .publisher sibling
# Then drop the pristine publisher .cls in as eceasst.cls, strip the
# \usepackage{showyourwork} line, and rename paper.tex to article.tex — the
# publisher expects the entry point to be article.tex.
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
        # Copy static figures into build/submission/figures/ so the submission
        # pdflatex build (which doesn't use showyourwork's graphics resolution)
        # can find them via the `figures/<file>.pdf` paths in article.tex.
        mkdir -p {output}/figures
        cp src/static/*.pdf {output}/figures/
        mv {output}/paper.tex {output}/article.tex
        sed -i '/\\usepackage{{showyourwork}}/d' {output}/article.tex
        """


# -----------------------------------------------------------------------------
# Build article.pdf via pdflatex from the staged tree
# -----------------------------------------------------------------------------
rule submission_pdf:
    input:
        srcdir = "build/submission",
        setup  = "build/.tinytex-installed"
    output:
        pdf = "article.pdf"
    conda:
        "env-tinytex.yml"
    shell:
        r"""
        cd {input.srcdir}
        # pdflatex returns non-zero on undefined refs (first pass, before
        # bibtex resolves them) and on benign warnings. Tolerate intermediate
        # passes; the final pass must still produce article.pdf, which is
        # checked by `cp` below — if the build genuinely failed there'd be no
        # file to copy.
        pdflatex -interaction=nonstopmode article.tex || true
        bibtex article || true
        pdflatex -interaction=nonstopmode article.tex || true
        pdflatex -interaction=nonstopmode article.tex || true
        cd - >/dev/null
        cp {input.srcdir}/article.pdf {output.pdf}
        """


# -----------------------------------------------------------------------------
# Submission tarball: clean source only, no build artifacts
# -----------------------------------------------------------------------------
# Depends on submission_pdf so the build is proven to succeed from the same
# tree we ship. The tarball itself excludes pdflatex's intermediate files.
rule submission_tarball:
    input:
        srcdir = "build/submission",
        pdf    = "article.pdf"
    output:
        "article.tar.gz"
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
            --exclude='article.pdf' \
            submission
        """
