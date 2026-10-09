# ERCC reference assets

- `ERCC92.fa` — the 92 ERCC spike-in control sequences, from Thermo Fisher's
  [ERCC92.zip](https://assets.thermofisher.com/TFS-Assets/LSG/manuals/ERCC92.zip).
- `ERCC_Controls_Analysis.txt` — Mix 1/Mix 2 molar concentrations per
  transcript, exported from NIST's
  [erccdashboard](https://github.com/usnistgov/erccdashboard) R package
  (`data/ERCC.RData`, object `ERCCMix1and2`).

Used by `scripts/make_ercc_test_data.py` to simulate reads at known
concentrations for RNA-seq quantification-accuracy validation (see
`docs/validation_results.md`).
