# golden

Records the goldens of [SQAT](https://github.com/ggrecow/SQAT) at
`4a9919800c69642fa3c5899838612094ebc7f1f4` with MATLAB R2026a on one computational thread
(`-singleCompThread`) on Linux, Windows and macOS, and compares every file, by SHA-256, with
the goldens recorded on macOS arm64.

Two sets are recorded:

- `data`: the metric cases, with inputs, outputs, internal stages and every warning
  (`tools/matlab/export_goldens.m`, `full` mode, no decimation).
- `level3v`: every call of the SQAT validation scripts, with inputs, outputs and every
  warning (`matlab/export_validation_goldens.m`).

`reference/` holds the SHA-256 of every file of the Mac recording (7259 files in `data`,
330471 in `level3v`).

## Run

Actions, workflow `goldens`, Run workflow. Each job (set and operating system) uploads two
artifacts: `golden-<set>-<os>`, the whole recorded tree of that platform as one tar file, and
`<set>-<os>`, the comparison with the Mac recording (`report.md`, `report.json`, the
`manifest.json` of the recording and every file that is not bit-identical).

## Inputs

- SQAT, checked out at the sha above.
- The SQAT validation sounds, Zenodo [10.5281/zenodo.7933206](https://doi.org/10.5281/zenodo.7933206)
  (CC BY 4.0).
- The NASA flyover sounds of AIAA paper 2020-2582, from `stabservdata.larc.nasa.gov`.

`tools/fetch_sounds.py` downloads both sound sets and checks the SHA-256 of each archive
against the archives the Mac goldens were recorded from.

## Use of AI

This project is developed with the help of Claude (Anthropic) as a programming assistant.
The author reviews and is responsible for all code and data.
