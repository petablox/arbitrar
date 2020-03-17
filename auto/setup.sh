#!/bin/bash

pip3 install mypy flake8 pytest

pushd test/tmp-build/
tar -xzvf tmp-build.tar.gz
popd

pushd test/tmp-analyze/
tar -xzvf tmp-analyze.tar.gz
popd
