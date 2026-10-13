"""The baseline a full run proved, for the unit tests that walk every step's default lines from it: production's
defaults phase commits each step's lines to ops main during the rollout (tests/ansible/upgrade/defaults-committed.txt),
so the working tree holds them already. Here they are reverted, newest first."""


def baseline(d, read):
    """{path: content} of the files the committed steps' default lines changed, as before them - `d` the loaded
    scripts/upgrade-defaults.py, `read(path)` the tree. A committed step whose new line is not there fails (ValueError),
    as does a record that is not the first steps with default lines in their order."""
    d.pending(read)
    done = [l.strip() for l in read(d.COMMITTED).split("\n") if l.strip() and not l.startswith("#")]
    files = {}
    for step in reversed(done):
        for path, old, new in reversed(d.default_lines(step)):
            files[path] = d.apply(files[path] if path in files else read(path), new, old, f"{step} reverted: {path}")
    return files
