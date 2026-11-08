"""Plan 111 step 4: the threshold at low false-match rates. Every pair of LFW pictures of DIFFERENT people (masi's centred
fingerprints) is an impostor pair, every pair of the same person a genuine one; the distance below which a given share
of impostor pairs fall, and the share of genuine pairs kept there."""
import base64, json, sys, os
import numpy as np
F = sys.argv[1]
keys, vecs = [], []
for l in open(os.path.join(F, sys.argv[2])):
    k, v = l.rstrip("\n").split("\t")
    if v != "none":
        keys.append(k); vecs.append(np.frombuffer(base64.b64decode(v), "<f4"))
X = np.stack(vecs).astype(np.float32)
who = np.array([k.split("/")[0] for k in keys])
_, ident = np.unique(who, return_inverse=True)
n = len(keys)
imp, gen = [], []
for i in range(0, n, 512):
    d = 1 - X[i:i + 512] @ X.T
    rows = np.arange(i, min(i + 512, n))[:, None]
    cols = np.arange(n)[None, :]
    upper = cols > rows
    same = ident[rows] == ident[cols]
    imp.append(d[upper & ~same]); gen.append(d[upper & same])
imp = np.sort(np.concatenate(imp)); gen = np.concatenate(gen)
out = {"pictures": n, "identities": int(ident.max() + 1), "impostor_pairs": int(imp.size), "genuine_pairs": int(gen.size),
       "closest_impostor": round(float(imp[0]), 4), "rates": []}
for far in [1e-3, 1e-4, 1e-5, 1e-6]:
    t = float(imp[int(imp.size * far)])
    out["rates"].append({"false_match_rate": far, "threshold": round(t, 4), "impostors_below": int((imp < t).sum()),
                         "genuine_kept": round(float((gen < t).mean()), 4)})
for t in [0.4, 0.5, 0.55, 0.6, 0.65, 0.7, 0.774]:
    out.setdefault("at", []).append({"threshold": t, "impostor_rate": float((imp < t).mean()), "impostors_below": int((imp < t).sum()),
                                     "genuine_kept": round(float((gen < t).mean()), 4)})
json.dump(out, open(os.path.join(F, "impostors.json"), "w"), indent=1); print(json.dumps(out, indent=1))
