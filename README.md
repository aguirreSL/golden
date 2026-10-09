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
- `level3v-internal`: the calls to the local functions of `Tonality_Aures1985` in its
  extraction and level excess validation.
- `level3v-988a3a9`: every call of the validation scripts of SQAT at `988a3a9` (2023).
- `gui`: the fixtures of the GUI of the SQAT fork of PR #84 (`aguirreSL/SQAT` at `b312b58`,
  `dbf721a`, `850437f` and `2409ef5`), long FIR filtering (`filter`) and two probes of
  `writetable` and `matlab.lang.makeUniqueStrings`. `g31_writetable/probe.json` and
  `probe.xlsx` carry the time they were written.

`reference/` holds the SHA-256 of every file of the Mac recording of each set.

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
