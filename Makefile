CURRENT_DIR = $(shell pwd)

.PHONY: all install build format

all: build

setup: install-env

install:
	ln -s $(CURRENT_DIR)/arbitrar $(HOME)/.local/bin/arbitrar
	ln -s $(CURRENT_DIR)/scripts/a2bc $(HOME)/.local/bin/a2bc

install-env:
	conda env create -f environment.yml

dump-env:
	conda env export > environment.yml

build: build-rs

# build-ml:
# 	make -C src/old_analyzer

build-rs:
	cd src/analyzer ; cargo build --release

clean:
	make clean -C src/analyzer

format: format-py format-rs

format-py:
	yapf -i --recursive arbitrar src/

format-rs:
	cd src/analyzer ; cargo fmt
