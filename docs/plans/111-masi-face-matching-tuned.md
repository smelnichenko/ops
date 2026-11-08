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
4. **Choose the threshold from the measurements.** Pick the distance where false matches between different people are at
   most 0.1% on LFW, and record the figure in the chart's comment. Then do a dry run on production's pictures: compute
   every pair masi would link at that threshold, write nothing, and show the operator a sample of the pairs it would
   link.
5. **Switch on with the operator's OK.** Links are written; a metric counts links made a day; and the first day's links
   are checked by hand.

## Process

- A test of `FaceEmbedder` on a few LFW pairs (same person close, different people far) runs in the suite from step 3.
  A change that breaks the pipeline then fails the build, not production.
- No threshold value without a measurement behind it.
