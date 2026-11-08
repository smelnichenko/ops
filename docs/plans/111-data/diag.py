"""Why the reference misses: for every image in a pair it gets wrong at its own threshold, every face it finds, and the
distance when the face nearest the centre (LFW centres its person) is taken instead of the largest."""
import csv, os, sys, json
import numpy as np
from multiprocessing import Pool
F = sys.argv[1]; LFW = os.path.join(F, "dl", "lfw"); THR = float(sys.argv[2])
APP = None
def init():
    global APP
    os.environ["OMP_NUM_THREADS"] = "1"
    import onnxruntime as ort
    from insightface.app import FaceAnalysis
    so = ort.SessionOptions(); so.intra_op_num_threads = 1; so.inter_op_num_threads = 1
    APP = FaceAnalysis(name="buffalo_l", root=os.path.join(F, "insight"), allowed_modules=["detection", "recognition"], providers=["CPUExecutionProvider"])
    for m in APP.models.values():
        m.session = ort.InferenceSession(m.model_file, sess_options=so, providers=["CPUExecutionProvider"])
    APP.prepare(ctx_id=-1, det_size=(640, 640))
def faces(rel):
    import cv2
    img = cv2.imread(os.path.join(LFW, rel)); h, w = img.shape[:2]
    fs = APP.get(img)
    out = []
    for f in fs:
        b = f.bbox; c = ((b[0] + b[2]) / 2 - w / 2) ** 2 + ((b[1] + b[3]) / 2 - h / 2) ** 2
        out.append({"area": float((b[2] - b[0]) * (b[3] - b[1])), "centre_d2": float(c), "score": float(f.det_score), "emb": f.normed_embedding.astype(np.float32)})
    return rel, out
if __name__ == "__main__":
    rows = list(csv.DictReader(open(os.path.join(F, "ref-pairs.csv"))))
    wrong = [r for r in rows if r["distance"] == "" or ((float(r["distance"]) < THR) != (r["same"] == "1"))]
    imgs = sorted({r[k] for r in wrong for k in ("a", "b")})
    with Pool(6, initializer=init) as p:
        res = dict(p.map(faces, imgs, chunksize=4))
    def pick(fs, how):
        if not fs: return None
        return (max(fs, key=lambda f: f["area"]) if how == "largest" else min(fs, key=lambda f: f["centre_d2"]))["emb"]
    fixed = 0; multi = 0
    for r in wrong:
        if len(res[r["a"]]) > 1 or len(res[r["b"]]) > 1: multi += 1
        a, b = pick(res[r["a"]], "centre"), pick(res[r["b"]], "centre")
        if a is not None and b is not None and ((1 - float(a @ b)) < THR) == (r["same"] == "1"): fixed += 1
    print(json.dumps({"wrong_pairs": len(wrong), "wrong_same": sum(r["same"] == "1" for r in wrong), "with_more_than_one_face": multi,
                      "right_with_centre_face": fixed, "images": len(imgs), "faces_per_image": np.bincount([len(v) for v in res.values()]).tolist()}))
