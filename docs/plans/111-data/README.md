# Plan 111 data — masi's face pipeline against InsightFace's on LFW (2026-11-08)

## Inputs

- **LFW.** `lfw.tgz`, sha256 `055f7d9c…`, 13,233 pictures. Its `pairs.txt` lists 6,000 pairs in 10 folds of 600; each
  fold has 300 same-person pairs and 300 of different people. The pairs name 7,701 pictures.
- **Models.** InsightFace `buffalo_l`, the asset and sha256 in masi's Dockerfile: `det_10g.onnx` (SCRFD) and
  `w600k_r50.onnx` (ArcFace). masi's build fetches the same file (`faceModels`).
- **Reference.** InsightFace 2.1's `FaceAnalysis`, `det_size` 640, via `ref.py`. It ran in 6 processes with one ONNX
  thread each.
- **masi.** `FaceEmbedder`, unchanged, via the test-scope harness `FaceBenchmarkLfwTest` (`MASI_LFW_DIR`, etc.). The
  harness never runs in production.

Both pipelines read the same picture files, and every pair maps to its files by name; `analyse.py` checks this before
it computes any figure. A picture with no face is counted, never dropped: a pair that names one is an error in the
accuracy.

## Files

| File | What |
|---|---|
| `2026-11-08-pairs-*.csv` | Each pair: fold, same (1/0), the two pictures, cosine distance (empty: a picture has no face) |
| `2026-11-08-analysis-*.json` | Input checks; per-picture agreement with the reference; 10-fold accuracy; distance quantiles; threshold and same-person pairs kept at 0.1% false matches |
| `2026-11-08-impostors-all-lfw-pairs.json` | Every LFW pair of different people (29.6 M) against every same-person pair (8,076): the threshold at lower false-match rates |
| `ref.py` | Reference fingerprints (`largest` or `centre` face) |
| `analyse.py` | The comparison (LFW's 10-fold protocol: the threshold is chosen on 9 folds and tested on the 10th) |
| `diag.py` | Why the reference itself missed pairs (which face it took) |
| `impostors.py` | The all-pairs false-match measurement |

`deployed` = masi as deployed until this plan. `fixed` = branch `fix/face-pipeline-reference`. `largest` = the largest
face is taken, as masi does for a contact's picture. `centred` = the face nearest the centre is taken, as LFW's
protocol does (LFW puts the person it names there). `run1` = the first fixed run, before the input-tensor fix.

## Results

| Pipeline | Face taken | 10-fold accuracy | Same-person kept at 0.1% false | Per picture vs reference (cosine) |
|---|---|---|---|---|
| masi deployed | largest | 54.05% | 0.47% | median 0.016; 7,677 of 7,689 below 0.5 |
| reference | largest | 96.97% | 94.51% | — |
| masi fixed | largest | 96.97% | 94.51% | 99% ≥ 0.9997; 3 another face of a near tie |
| reference | centred | 99.55% | 99.70% | — |
| masi fixed | centred | 99.55% | 99.70% | every picture ≥ 0.9 |

- **No face.** Both pipelines find no face in the same 11 pictures. Those pictures put 17 pairs among the errors;
  without them accuracy is about 99.8%, the model's published figure.
- **Thresholds, over all 29.6 M different-person pairs (masi fixed, centred):**
  - 0.80: 1 in 1,000 pass; 99.86% of same-person pairs kept.
  - 0.74: 1 in 10,000 pass; 99.75% kept.
  - 0.69: 1 in 100,000 pass; 99.55% kept.
  - 0.60: 1.4 in 1,000,000 pass; 99.0% kept.
  - Below about 0.6, what passes is mostly LFW's own label errors. The closest "different people" pair is 0.04 apart:
    one photo filed under two names.
