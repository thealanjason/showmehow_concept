# showyourwork + tinytex (pdflatex preview alongside tectonic)

## Why we need both

- **showyourwork** drives builds locally and on GitHub CI; it uses **tectonic
  (XeTeX)** internally.
- The journal (ECEASST) renders submissions with **pdflatex**.
- XeTeX under tectonic operates in TU (Unicode) encoding by default, but
  `eceasst.cls` loads `mathptmx`, `helvet`, and `courier` — packages that
  only register OT1/T1 shapes. Under TU, those fonts don't exist, so LaTeX
  silently substitutes Latin Modern. The visible symptom is that the title
  and section headings render in Latin Modern Regular instead of Times Bold.
- The fontspec workaround (loading `texgyretermes`/`texgyreheros`/`texgyrecursor`
  by filename) restores correct rendering under tectonic — but requires
  XeLaTeX/LuaLaTeX and will hard-error under pdflatex. So it can't ship in
  the submitted source.
- Goal: keep showyourwork/tectonic as the default build, and emit a second
  PDF built with pdflatex so we always see what the journal will actually
  produce.

## Confirming the tectonic problem in the log

In `.showyourwork/compile/paper.log` (tectonic build):
```
LaTeX Font Warning: Font shape `TU/ptm/m/n' undefined
LaTeX Font Warning: Font shape `TU/ptm/b/n' undefined
LaTeX Font Warning: Font shape `TU/phv/m/n' undefined
LaTeX Font Warning: Font shape `TU/pcr/m/n' undefined
...
LaTeX Font Warning: Some font shapes were not available, defaults substituted.
```

## The fontspec block in paper.tex

Kept commented out so the source remains submission-clean. Re-enable only
for local tectonic visual checks; never commit enabled. Block lives just
after `\usepackage{hyperref}` in `src/tex/paper.tex`.

## eceasst.cls patch (separate gotcha, already applied)

The pristine publisher `eceasst.cls` calls `\includegraphics{easst}` for the
header/cover logo. showyourwork's `\includegraphics` redefinition logs every
call into `<GRAPHICS>` XML records, so `easst` (no extension) ends up tracked
as a free-floating graphic and snakemake fails with
`MissingInputException ... affected files: src/tex/easst`.

Fix in `eceasst.cls`:
```latex
\RequirePackage{graphicx}
\let\eceasst@includegraphics\includegraphics
```
and three call sites changed from `\includegraphics[...]{easst}` to
`\eceasst@includegraphics[...]{easst}`.

Pristine version kept at `src/tex/eceasst.cls.publisher` (LaTeX ignores the
suffix). For submission, copy it over `eceasst.cls`.

## tinytex setup

`env-tinytex.yml` (root):
```yaml
name: tinytex
dependencies:
  - genomedk::tinytex
```

Tinytex installs minimal — extra packages must be added via `tlmgr install`.
Known required for this paper:
```
tlmgr install hypcap caption booktabs pgf orcidlink rsfs courier
```
Bundle quirks:
- `subcaption.sty` lives inside the `caption` bundle.
- `pgf` covers tikz.

Tinytex/TeX Live version mismatch: a fresh tinytex may be TL2025 while CTAN
serves TL2026. Pin tlmgr to the frozen 2025 archive:
```
tlmgr option repository https://ftp.math.utah.edu/pub/tex/historic/systems/texlive/2025/tlnet-final
```

## Local pdflatex build (manual)

```bash
cd src/tex
pdflatex -interaction=nonstopmode paper.tex
bibtex paper
pdflatex -interaction=nonstopmode paper.tex
pdflatex -interaction=nonstopmode paper.tex
```

`latexmk -pdf -bibtex paper.tex` is the one-shot equivalent.

## Implemented setup (root Snakefile)

User rules live in the repo-root `Snakefile`. showyourwork ingests them on
build and gives user rules higher `ruleorder` than its own, so the first
rule in the file becomes the default target.

Rules:

- **`all`** — depends on `paper.pdf` (showyourwork/tectonic) and
  `article.pdf` + `article.tar.gz` (pdflatex). First in the file, so it's
  the default. `showyourwork build` builds all three.
- **`setup_tinytex`** — runs `tlmgr install` for the packages pdflatex
  needs that don't ship in `genomedk::tinytex`. Sentinel at
  `build/.tinytex-installed` makes this a one-time check.
- **`submission_stage`** — rsyncs `src/tex/` into `build/submission/`,
  excluding `showyourwork.sty`, the patched `eceasst.cls`, the
  `.publisher` sibling, and all LaTeX build artifacts. Then drops the
  pristine `eceasst.cls.publisher` in as `eceasst.cls`, renames
  `paper.tex` to `article.tex` (publisher expects that filename), and
  strips the `\usepackage{showyourwork}` line.
- **`submission_pdf`** — runs `pdflatex / bibtex / pdflatex / pdflatex`
  inside `build/submission/` using the `env-tinytex.yml` conda env.
  Copies the resulting PDF to `article.pdf` at the repo root.
- **`submission_tarball`** — tars `build/submission/` (source only, no
  build artifacts) into `article.tar.gz`.

What this guarantees:

- The submission PDF is built from the exact tree we ship in the tarball;
  no drift between "what we see" and "what the publisher gets".
- `src/tex/eceasst.cls` can stay patched (so `showyourwork build` keeps
  working with tectonic); the publisher copy lives at
  `src/tex/eceasst.cls.publisher` and gets swapped in at stage time.
- Local and CI use the same path. showyourwork-action runs snakemake with
  conda enabled, so `env-tinytex.yml` is provisioned automatically.

Outputs are gitignored (`/build/`, `/article.tar.gz`; `/article.pdf` is
covered by the `/*.pdf` rule).

## CI publishing (publish-submission.yml)

`showyourwork-action` only publishes a hardcoded list to `main-pdf`
(`paper.pdf`, optionally `arxiv.tar.gz`, optionally `dag.pdf`). To get our
extras onto the same branch (so the README badges work), a separate workflow
`.github/workflows/publish-submission.yml` handles it independently.

Why a standalone workflow rather than editing `build.yml`:

- The submission rules (`submission_stage`, `submission_pdf`,
  `submission_tarball`) don't depend on `paper.pdf`. They build straight
  from `src/tex/`, so they don't need showyourwork's output.
- Keeps `build.yml` / `build-pull-request.yml` (showyourwork-managed) clean.
- Tinytex install + conda env cached via `actions/cache`, so subsequent
  runs are fast.

What the workflow does:

- On PR: builds the artifacts, uploads them as a workflow artifact for
  preview.
- On push to `main`: builds the artifacts, then checks out `main-pdf` and
  drops the two files in alongside showyourwork's outputs.

The README badges link to `raw/main-pdf/article.pdf` and
`raw/main-pdf/article.tar.gz`, so clicking always gives the latest.

## Known log warnings to ignore

- `'h' float specifier changed to 'ht'` — LaTeX standard behavior.
- `hyperref Token not allowed in PDF string` — from `\textbf{...}` inside
  intro sentence captured for PDF metadata; cosmetic.

## Known log warnings that need fixing (pdflatex)

- `Font ... rsfs10 ... not loadable` → `tlmgr install rsfs`
- `Font ... pcrr7t ... not loadable` → `tlmgr install courier`
