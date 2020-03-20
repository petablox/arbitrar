#!/bin/bash

git clone https://github.com/petablox/ll_analyzer.git

cd ll_analyzer
./setup.sh

make examples
make
