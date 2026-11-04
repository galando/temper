#!/usr/bin/env python3
"""combine.py OLD_RESULTS NEW_RESULTS OUT: one results folder for report.py, with an earlier Temper's runs renamed.

Every run of OLD_RESULTS is linked into OUT as it is, except the Temper arm's, which are copied with the arm renamed to
temper-9.7.6 (run.json, grade.json, mutation.json, tokens.json, person.jsonl; the transcript and the work folder stay
where they are). Every run of NEW_RESULTS is linked as it is, so its Temper arm is the new version. A run in both
(the TypeScript baselines) is taken from NEW_RESULTS. Standard library only.
"""
import json
import os
import shutil
import sys

KEEP = ("run.json", "grade.json", "mutation.json", "tokens.json", "person.jsonl")


def main():
    old, new, out = (os.path.abspath(p) for p in sys.argv[1:4])
    shutil.rmtree(out, ignore_errors=True)
    os.makedirs(out)
    for d in sorted(os.listdir(old)):
        src = os.path.join(old, d)
        if not os.path.isfile(os.path.join(src, "grade.json")):
            continue
        if "__temper__" in d:
            dst = os.path.join(out, d.replace("__temper__", "__temper-9.7.6__"))
            os.makedirs(dst)
            for f in KEEP:
                p = os.path.join(src, f)
                if not os.path.exists(p):
                    continue
                if f.endswith(".json"):
                    j = json.load(open(p))
                    if isinstance(j, dict) and j.get("arm") == "temper":
                        j["arm"] = "temper-9.7.6"
                    json.dump(j, open(os.path.join(dst, f), "w"), indent=2)
                else:
                    shutil.copy2(p, os.path.join(dst, f))
        elif not os.path.exists(os.path.join(new, d)):
            os.symlink(src, os.path.join(out, d))
    for d in sorted(os.listdir(new)):
        src = os.path.join(new, d)
        if os.path.isfile(os.path.join(src, "grade.json")):
            os.symlink(src, os.path.join(out, d))
    print("combined into %s: %d runs" % (out, len(os.listdir(out))))


if __name__ == "__main__":
    main()
