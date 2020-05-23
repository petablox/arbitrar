FROM ubuntu:20.04
ARG DEBIAN_FRONTEND=noninteractive
FROM nvidia/cuda:10.0-base

###############################################################################
# BASICS
###############################################################################

RUN apt-get update \
    && apt-get install -y python3 curl unzip git vim sudo clang cmake \
    && apt-get install -y llvm llvm-dev python3-pip pkg-config m4

###############################################################################
# SYSTEM SETUP
###############################################################################

# SSH
RUN apt-get install -y ssh && mkdir /var/run/sshd

# User Settings
RUN useradd -m -s /bin/bash -G sudo aspire && \
    (echo "ai4code"; echo "ai4code") | passwd aspire && \
    echo 'export LLVM_COMPILER=clang' >> /home/aspire/.bashrc && \
    echo 'eval `opam env`' >> /home/aspire/.bashrc && \
    echo "alias sudo='sudo LLVM_COMPILER=\$LLVM_COMPILER'" >> /home/aspire/.bashrc

COPY src/*.sh /home/aspire/
RUN chown aspire.aspire -R /home/aspire/* /home/aspire/.[a-z]*

USER root

# SSH Port Exposure
EXPOSE 22

###############################################################################
# DEPENDENCIES (PYTHON)
###############################################################################

USER aspire

# Utilities
RUN pip3 install mypy yapf pytest python-magic termcolor

# PL Related Dependencies
RUN pip3 install wllvm graphviz

# ML Related Dependencies
RUN pip3 install scikit-learn matplotlib pandas

###############################################################################
# DEPENDENCIES (OCAML)
###############################################################################

USER root

# Install with root
RUN curl -sL https://raw.githubusercontent.com/ocaml/opam/master/shell/install.sh > /home/aspire/install-opam.sh
RUN echo "\n" | sh /home/aspire/install-opam.sh
RUN rm /home/aspire/install-opam.sh

# Init & Config with aspire
USER aspire

RUN opam init --disable-sandboxing

# Utilities
RUN opam install -y ocamlbuild ocamlformat merlin
RUN opam install -y ocamlgraph yojson ppx_compare ppx_deriving ppx_deriving_yojson

# LLVM & Z3
RUN opam install -y llvm ctypes ctypes-foreign z3

###############################################################################
# COMMAND
###############################################################################

USER root

# SSHD
CMD ["/usr/sbin/sshd", "-D"]
