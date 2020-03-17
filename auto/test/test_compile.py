import pytest

import os
import shutil

from auto import meta
from auto import fetch
from auto import compile

FPATH = os.path.dirname(os.path.realpath(__file__))


@pytest.fixture
def clean_slate():
    if os.path.exists(os.path.join(FPATH, "tmp")):
        shutil.rmtree(os.path.join(FPATH, "tmp"))
    os.mkdir(os.path.join(FPATH, "tmp"))


def test_config_compile(clean_slate):
    repo = meta.Repo(os.path.join(FPATH, "tmp"))
    fetch.read_package_json(repo, os.path.join(FPATH, "github.json"))
    fetch.fetch_repo(repo)

    compile.build_repo(repo)

    # Just make sure the bc exists
    for _, p in repo.pkgs.items():
        assert p.build.result == meta.BuildResult.success
        bc = p.build.bc_files[0]
        assert os.path.exists(os.path.join(FPATH, bc))

    repo.save()

    assert os.path.exists(os.path.join(repo.main_dir, "repo.json"))
