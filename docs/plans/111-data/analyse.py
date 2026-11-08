"""Plan 111: masi's face pipeline against InsightFace's reference on LFW's 6,000 standard pairs.
Inputs: ref-progress.tsv (reference: absolute path -> 512 floats hex | none), masi-emb.tsv (masi: lfw-relative path -> base64 floats | none).
Checks the inputs before any figure; LFW's 10-fold protocol for accuracy."""
import base64, json, os, sys
import numpy as np

F = sys.argv[1]
LFW = os.path.join(F, "dl", "lfw")

def rel(p):
    return os.path.relpath(p, LFW)

ref = {}
REF = sys.argv[3] if len(sys.argv) > 3 else "ref-progress.tsv"
for line in open(os.path.join(F, REF)):
    k, v = line.rstrip("\n").split("\t")
    ref[rel(k)] = None if v == "none" else np.frombuffer(bytes.fromhex(v), dtype=np.float32)
masi = {}
MASI = sys.argv[2] if len(sys.argv) > 2 else "masi-emb.tsv"
zero_vectors = 0
for line in open(os.path.join(F, MASI)):
    k, v = line.rstrip("\n").split("\t")
    e = None if v == "none" else np.frombuffer(base64.b64decode(v), dtype="<f4")
    if e is not None and not np.linalg.norm(e) > 0:
        zero_vectors += 1; e = None   # no direction: no face, counted
    masi[k] = e

# the pairs, as LFW states them
rows = [l.rstrip("\n").split("\t") for l in open(os.path.join(F, "dl", "pairs.txt"))][1:]
def img(name, n):
    return "%s/%s_%04d.jpg" % (name, name, int(n))
pairs = []
for i, r in enumerate(rows):
    fold = i // 600
    if len(r) == 3:
        pairs.append((fold, 1, img(r[0], r[1]), img(r[0], r[2])))
    else:
        pairs.append((fold, 0, img(r[0], r[1]), img(r[2], r[3])))

checks = {}
needed = {p for _, _, a, b in pairs for p in (a, b)}
checks["pairs"] = len(pairs)
checks["same_pairs"] = sum(1 for p in pairs if p[1] == 1)
checks["folds_balanced"] = all(sum(1 for p in pairs if p[0] == f and p[1] == 1) == 300 for f in range(10))
checks["images_needed"] = len(needed)
checks["images_exist"] = sum(1 for p in needed if os.path.exists(os.path.join(LFW, p)))
checks["ref_covers"] = len(needed & ref.keys())
checks["masi_covers"] = len(needed & masi.keys())
checks["same_pair_names_match"] = all(a.split("/")[0] == b.split("/")[0] for _, s, a, b in pairs if s == 1)
checks["diff_pair_names_differ"] = all(a.split("/")[0] != b.split("/")[0] for _, s, a, b in pairs if s == 0)
checks["ref_no_face"] = sum(1 for p in needed if ref.get(p) is None)
checks["masi_zero_vectors_counted_as_no_face"] = zero_vectors
checks["masi_no_face"] = sum(1 for p in needed if masi.get(p) is None)
norms = [float(np.linalg.norm(v)) for v in masi.values() if v is not None]
checks["masi_norm_min_max"] = [round(min(norms), 4), round(max(norms), 4)] if norms else None
rnorms = [float(np.linalg.norm(v)) for v in ref.values() if v is not None]
checks["ref_norm_min_max"] = [round(min(rnorms), 4), round(max(rnorms), 4)]
checks["dims"] = sorted({len(v) for v in list(masi.values()) + list(ref.values()) if v is not None})

def unit(v):
    return v / np.linalg.norm(v)

# per image: does masi compute what the reference computes?
agree = np.array([float(np.dot(unit(masi[p]), unit(ref[p]))) for p in needed if masi.get(p) is not None and ref.get(p) is not None])

def distances(emb):
    d = []
    for fold, same, a, b in pairs:
        ea, eb = emb.get(a), emb.get(b)
        d.append((fold, same, None if ea is None or eb is None else 1.0 - float(np.dot(unit(ea), unit(eb)))))
    return d

def tenfold(d):
    """LFW protocol: threshold chosen on 9 folds (best accuracy there), accuracy on the 10th. A pair with a missing face is
    an error (counted), as a deployed matcher could not decide it."""
    accs = []
    thresholds = []
    for test in range(10):
        train = [(s, x) for f, s, x in d if f != test and x is not None]
        cand = sorted({x for _, x in train})
        best, best_t = -1, None
        xs = np.array([x for _, x in train]); ss = np.array([s for s, _ in train])
        for t in np.linspace(0, 2, 2001):
            acc = np.mean((xs < t) == (ss == 1))
            if acc > best:
                best, best_t = acc, t
        tp = [(s, x) for f, s, x in d if f == test]
        correct = sum(1 for s, x in tp if x is not None and ((x < best_t) == (s == 1)))
        accs.append(correct / len(tp)); thresholds.append(best_t)
    return float(np.mean(accs)), float(np.std(accs)), float(np.median(thresholds))

def far_threshold(d, far=0.001):
    diff = sorted(x for _, s, x in d if s == 0 and x is not None)
    t = diff[int(len(diff) * far)] if diff else None
    same = [x for _, s, x in d if s == 1 and x is not None]
    tar = float(np.mean([x < t for x in same])) if t is not None else None
    return t, tar

def pct(xs):
    xs = np.array(xs)
    return {k: round(float(np.percentile(xs, q)), 3) for k, q in [("p1", 1), ("p5", 5), ("p50", 50), ("p95", 95), ("p99", 99)]}

out = {"checks": checks,
       "per_image_agreement_cosine": pct(agree) | {"n": int(len(agree)), "below_0.9": int((agree < 0.9).sum()), "below_0.5": int((agree < 0.5).sum())}}
for name, emb in [("reference", ref), ("masi", masi)]:
    d = distances(emb)
    acc, sd, thr = tenfold(d)
    t001, tar001 = far_threshold(d, 0.001)
    out[name] = {"accuracy_10fold": round(acc, 4), "accuracy_std": round(sd, 4), "threshold_median": round(thr, 3),
                 "same_distance": pct([x for _, s, x in d if s == 1 and x is not None]),
                 "different_distance": pct([x for _, s, x in d if s == 0 and x is not None]),
                 "pairs_missing_a_face": sum(1 for _, _, x in d if x is None),
                 "threshold_at_far_0.1%": None if t001 is None else round(t001, 3), "true_match_rate_at_far_0.1%": None if tar001 is None else round(tar001, 4)}
json.dump(out, open(os.path.join(F, "analysis-" + MASI.replace(".tsv", "") + "-vs-" + REF.replace(".tsv", "") + ".json"), "w"), indent=1)
print(json.dumps(out, indent=1))
