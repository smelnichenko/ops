# Plan 111 — masi: face matching measured and tuned before it is switched on

**Status:** asked for 2026-11-08 by the operator: "yes, we need face matching tuned proper way before enabling it".
Face matching stays off in production (`masiService.enrich.contactPictures.face: false`) until step 5.

## Why

- **The failure.** Face matching links two contacts as one person when their faces' ArcFace fingerprints are close. When it ran
  (2026-10-23..27), different people measured 0.05–0.40 apart by cosine distance; ArcFace usually puts different people
  near 0.6 or further. masi's pipeline produces wrong distances, and with them almost any two faces counted as one
  person, so strangers would have been merged. It was switched off.
- **The threshold.** It was later raised from 0.4 to 0.7, which with distances that small would link even more pairs.
- **The cause is unknown.** Where masi's pipeline goes wrong has not been found.

What production holds (2026-11-08): 697 pictures, 67 with a fingerprint, and 3 people with pictures from two sources. That
is far too few labelled pairs to tune on.

## Steps

1. **Benchmark masi's own pipeline on LFW.** LFW is Labeled Faces in the Wild: 6,000 standard pairs, 3,000 of the same
   person and 3,000 of different people. It is the usual verification benchmark for ArcFace.
   - A test-scope harness (never in production) runs `FaceEmbedder`, unchanged, on every pair.
   - **Output:** the two distance distributions, the ROC, the accuracy, and the share of pairs with no face found.
   - Data and results are saved in `109-data`'s fashion, beside this plan.
2. **The same pairs through the reference pipeline.** InsightFace's own Python, with the same `buffalo_l` models
   (det_10g + w600k_r50), compared with masi pair by pair. A wide gap locates the fault; the suspects are:
   - the colour order the model expects (RGB vs BGR);
   - the input scaling ((x − 127.5) / 127.5);
   - the order of the five landmarks;
   - the similarity transform onto the 112×112 template;
   - the detector's input size, padding and anchors;
   - normalising the 512 floats.
3. **Fix and measure again.** The step is done when masi's distances match the reference's within a small tolerance
   on every pair, and LFW accuracy reaches the model's published level (about 99.8% for w600k_r50; below 99.5% is not
   done).
4. **Choose the threshold from the measurements.** Pick the distance where false matches between different people are
   rare enough for the gallery's size: at 0.1% (the first target) about 240 of production's 240,000 pairs would be
   false links, so measure over all of LFW's pairs of different people (see Progress). Record the figure in the chart's
   comment. Then do a dry run on production's pictures: compute
   every pair masi would link at that threshold, write nothing, and show the operator a sample of the pairs it would
   link.
5. **Switch on with the operator's OK.** Links are written; a metric counts links made a day; and the first day's links
   are checked by hand.

## Progress

### Steps 1–3 (2026-11-08): measured, cause found, fixed on branch `fix/face-pipeline-reference`

Data and scripts are in `111-data/` (its README).

**Measurements on LFW**

- **masi as deployed:** 54.05% accuracy, coin-flip. Its fingerprints did not resemble the reference's: median cosine
  0.016.
- **Reference:** 96.97% taking the largest face, 99.55% taking LFW's centred face.
- **masi fixed:** 96.97% and 99.55%, the reference's own on both. Taking the centred face, every picture's fingerprint
  matches the reference's.

**Faults fixed, each a step where masi differed from InsightFace**

1. **The detector's grid (the main fault).** SCRFD ran at the picture's own size, but its grid was computed as size ÷
   stride. At 250 px that gives 15 and 7 cells where the model has 16 and 8, so face boxes and landmarks of medium and
   large faces landed in the wrong place. Now the picture is letterboxed into 640×640, as InsightFace does.
2. **Alignment.** A full affine transform, which can shear the face, replaced by a similarity transform (Umeyama's).
3. **Recogniser input.** Scaled by 128 instead of 127.5.
4. **Picture edges.** Filled from the nearest pixel instead of black.
5. **Resizing.** Not the same interpolation as OpenCV's INTER_LINEAR.
6. **Grey pictures.** Brightened by Java's colour conversion.
7. **Which face.** The surest anchor was taken, not the largest face after non-maximum suppression.
8. **The input tensor's memory.** The ONNX input tensor was never held, so the collector could free its direct buffer
   mid-run. Under load this gave fingerprints of no one, with no error: 3 of 7,701 pictures, embedded several at a time.

**Tests**

- In the suite on every build: `FaceEmbedderReferenceTest` checks 9 LFW pictures against InsightFace's own fingerprints.
  The same person must be close, different people far, and a picture without a face refused.
- The build fetches the shipped models into a persistent cache: CI's `/cache/models/buffalo_l`.

**Before step 5:** production's 67 stored fingerprints (from 2026-10-21 to 10-27) came from the broken pipeline. They
are cleared, with the operator's OK, before the switch is turned on; the backfill then recomputes them.

### Step 4: the threshold (measured, not chosen yet)

- **0.1% false matches is too loose for a gallery.** LFW's 3,000 pairs give 0.774 at that rate, but across production's
  697 pictures (about 240,000 pairs) it would make about 240 false links.
- **Over all 29.6 M LFW pairs of different people:**

  | Threshold | False matches | Same-person pairs kept | Expected false links in 240,000 pairs |
  |---|---|---|---|
  | 0.80 | 1 in 1,000 | 99.86% | about 240 |
  | 0.74 | 1 in 10,000 | 99.75% | about 24 |
  | 0.69 | 1 in 100,000 | 99.55% | about 2 |
  | 0.60 | 1.4 in 1,000,000 | 99.0% | about 0.3 |

- **Candidate: 0.6.** The dry run on production's pictures and the operator's review of its sample decide.

### Step 4: the dry run on production's pictures (2026-11-09, nothing written)

masi's own `FaceEmbedder` (d612195, largest face) ran over a read-only export of production's 834 pictures. Figures are
in `111-data/2026-11-09-dry-run-production.json`; it holds counts only, no names or faces.

- 732 pictures have a face, 102 do not. That makes 267,541 pairs across different contacts.
- **The gap is wide.** Up to 0.60 there are 4 pairs, and nothing lies between 0.322 and 0.661.

  | Threshold | Pairs that would link |
  |---|---|
  | 0.60 | 4 |
  | 0.69 | 6 |
  | 0.70 | 8 |
  | 0.74 | 58 |
  | 0.80 | 678 |

- **The LFW forecast held.** Above 0.60 the pairs carry different people's names: 2 up to 0.69 (forecast about 2) and 4
  up to 0.70, which is why 0.70 is too loose.
- **Of the 4 pairs at 0.60,** 3 are identical files of contacts masi already holds as one person, so they add nothing.
  One is new: two contacts with the same surname at the same company, different first names, different files, distance
  0.322. **The operator's verdict (2026-11-09): two different people.** So 0.60 makes no correct new link on today's
  pictures and one false one, far inside the range where real matches lie: no threshold separates it.
- **A face link is a note, not a merge.** `saveFaceLink` writes a `contact_picture_link` row that the contact's page
  lists; nothing merges people from it.
- **Side finding: name search.** 4 pairs that masi holds as one person (one contact, or one person) have clearly
  different faces (0.873 to 1.077), and every one of them involves a `NAME_SEARCH` picture. A picture found by name can
  be someone else's: of the 3 contacts whose name-search picture can be compared with their GitHub picture, 1 matches
  and 2 do not. 97 name-search pictures are stored. The 1.077 pair is two people merged by a shared mailbox
  (`PersonService` matches on the address), the only person out of 11,941 that holds two different names.

## Process

- A test of `FaceEmbedder` on a few LFW pairs (same person close, different people far) runs in the suite from step 3.
  A change that breaks the pipeline then fails the build, not production.
- No threshold value without a measurement behind it.
