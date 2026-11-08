"""Reference: InsightFace's own pipeline (FaceAnalysis, buffalo_l) on LFW's standard pairs. One process per core,
one ONNX thread each. Writes ref-emb.npz (per image: 512 floats, or none) and ref-pairs.csv (fold, same, distance)."""
import os, sys, csv
import numpy as np
from multiprocessing import Pool

F = sys.argv[1]
LFW = os.path.join(F, "dl", "lfw")
APP = None
PICK = sys.argv[3] if len(sys.argv) > 3 else "largest"
TAG = "" if PICK == "largest" else "-" + PICK

def path(name, n):
    return os.path.join(LFW, name, "%s_%04d.jpg" % (name, int(n)))

def pairs():
    rows = [l.rstrip("\n").split("\t") for l in open(os.path.join(F, "dl", "pairs.txt"))][1:]
    out = []
    for i, r in enumerate(rows):
        fold = i // 600
        if len(r) == 3:
            out.append((fold, 1, path(r[0], r[1]), path(r[0], r[2])))
        else:
            out.append((fold, 0, path(r[0], r[1]), path(r[2], r[3])))
    return out

def init():
    global APP
    os.environ["OMP_NUM_THREADS"] = "1"
    import onnxruntime as ort
    from insightface.app import FaceAnalysis
    so = ort.SessionOptions(); so.intra_op_num_threads = 1; so.inter_op_num_threads = 1
    APP = FaceAnalysis(name="buffalo_l", root=os.path.join(F, "insight"), allowed_modules=["detection", "recognition"],
                       providers=["CPUExecutionProvider"])
    for m in APP.models.values():
        m.session = ort.InferenceSession(m.model_file, sess_options=so, providers=["CPUExecutionProvider"])
    APP.prepare(ctx_id=-1, det_size=(640, 640))

def embed(p):
    import cv2
    img = cv2.imread(p)
    faces = APP.get(img)
    if not faces:
        return p, None
    if PICK == "centre":   # LFW's protocol: the face nearest the centre, where LFW puts the person it names
        h, w = img.shape[:2]
        f = min(faces, key=lambda x: ((x.bbox[0] + x.bbox[2]) / 2 - w / 2) ** 2 + ((x.bbox[1] + x.bbox[3]) / 2 - h / 2) ** 2)
    else:
        f = max(faces, key=lambda x: (x.bbox[2] - x.bbox[0]) * (x.bbox[3] - x.bbox[1]))
    return p, f.normed_embedding.astype(np.float32)

if __name__ == "__main__":
    ps = pairs()
    images = sorted({p for _, _, a, b in ps for p in (a, b)})
    procs = int(sys.argv[2]) if len(sys.argv) > 2 else 6
    # each image written as it is done, so a run shows its progress and a stopped one is resumed, not redone
    done_path = os.path.join(F, "ref" + TAG + "-progress.tsv")
    emb = {}
    if os.path.exists(done_path):
        for line in open(done_path):
            k, v = line.rstrip("\n").split("\t")
            emb[k] = None if v == "none" else np.frombuffer(bytes.fromhex(v), dtype=np.float32)
    todo = [p for p in images if p not in emb]
    with Pool(procs, initializer=init) as pool, open(done_path, "a") as fh:
        for k, v in pool.imap_unordered(embed, todo, chunksize=4):
            emb[k] = v
            fh.write(k + "\t" + ("none" if v is None else v.tobytes().hex()) + "\n")
            fh.flush()
    np.savez_compressed(os.path.join(F, "ref" + TAG + "-emb.npz"), **{k: (v if v is not None else np.zeros(0, np.float32)) for k, v in emb.items()})
    with open(os.path.join(F, "ref" + TAG + "-pairs.csv"), "w", newline="") as fh:
        w = csv.writer(fh); w.writerow(["fold", "same", "a", "b", "distance"])
        for fold, same, a, b in ps:
            ea, eb = emb.get(a), emb.get(b)
            d = "" if ea is None or eb is None else "%.6f" % (1.0 - float(np.dot(ea, eb)))
            w.writerow([fold, same, os.path.relpath(a, LFW), os.path.relpath(b, LFW), d])
    print(len(images), "images,", sum(1 for v in emb.values() if v is None), "without a face")
