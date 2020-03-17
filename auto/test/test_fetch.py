import pytest

import os
import shutil

from auto import meta
from auto import fetch

FPATH = os.path.dirname(os.path.realpath(__file__))


@pytest.fixture
def clean_slate():
    if os.path.exists(os.path.join(FPATH, "tmp")):
        shutil.rmtree(os.path.join(FPATH, "tmp"))
    os.mkdir(os.path.join(FPATH, "tmp"))


def test_github_fetch(clean_slate):
    repo = meta.Repo(os.path.join(FPATH, "tmp"))
    fetch.read_package_json(repo, os.path.join(FPATH, "github.json"))
    fetch.fetch_repo(repo)

    for n in repo.pkgs:
        path = os.path.join(repo.main_dir, n)
        assert os.path.exists(path)
        assert len(os.listdir(path)) != 0

    repo.save()

    assert os.path.exists(os.path.join(repo.main_dir, "repo.json"))
