import pytest

import os

from auto import meta
from auto import analyze

import json

FPATH = os.path.dirname(os.path.realpath(__file__))


def test_analyze_succeeds():
    with open(os.path.join(FPATH, "tmp-analyze", "repo.json")) as f:
        j = json.loads(f.read())
        repo = meta.Repo.from_json(j)

    assert analyze.analyze_repo(repo)

    # Just make sure the analysis exists
    for _, p in repo.pkgs.items():
        assert len(p.analysis) != 0

    repo.save(name="tmp.json")

    assert os.path.exists(os.path.join(repo.main_dir, "tmp.json"))
