import pytest

import os
import shutil

from auto import meta
from auto import fetch
from auto import compile

import json

FPATH = os.path.dirname(os.path.realpath(__file__)) 

@pytest.fixture
def good_build():
    if os.path.exists(os.path.join(FPATH, "tmp-build/openssl")):
        shutil.rmtree(os.path.join(FPATH, "tmp-build/openssl"))
    shutil.copytree(os.path.join(FPATH, "tmp-build/openssl-orig"), os.path.join(FPATH, "tmp-build/openssl"))


@pytest.fixture
def bad_build():
    if os.path.exists(os.path.join(FPATH, "tmp-build/openssl")):
        shutil.rmtree(os.path.join(FPATH, "tmp-build/openssl"))
    shutil.copytree(os.path.join(FPATH, "tmp-build/openssl-broken"), os.path.join(FPATH, "tmp-build/openssl"))


def test_config_compile_succeeds(good_build):
    with open(os.path.join(FPATH, "tmp-build", "repo.json")) as f:
        j = json.loads(f.read())
        repo = meta.Repo.from_json(j)

    assert compile.build_repo(repo)

    # Just make sure the bc exists
    for _, p in repo.pkgs.items():
        assert p.build.result == meta.BuildResult.success
        bc = p.build.bc_files[0]
        assert os.path.exists(bc)

    repo.save(name="tmp.json")

    assert os.path.exists(os.path.join(repo.main_dir, "tmp.json"))


def test_config_compile_fails(bad_build):
    with open(os.path.join(FPATH, "tmp-build", "repo.json")) as f:
        j = json.loads(f.read())
        repo = meta.Repo.from_json(j)

    assert not compile.build_repo(repo)

    repo.save(name="tmp.json")

    assert os.path.exists(os.path.join(repo.main_dir, "repo.json"))
