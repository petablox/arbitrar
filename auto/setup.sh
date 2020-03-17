#!/bin/bash

pip3 install mypy flake8 pytest

pushd test/tmp-build/
tar -xzvf tmp-build.tar.gz
popd
