FROM ubuntu:20.04
ARG DEBIAN_FRONTEND=noninteractive
FROM nvidia/cuda:10.0-base

###############################################################################
# BASICS
###############################################################################

RUN apt-get update
RUN apt-get install -y curl unzip git vim sudo clang gcc cmake
RUN apt-get install -y python3 python3-pip pkg-config
RUN apt-get install -y libgmp-dev m4

###############################################################################
# SYSTEM SETUP
###############################################################################

# SSH
RUN apt-get install -y ssh && mkdir /var/run/sshd

# User Settings (username: aspire, password: ai4code)
RUN useradd -m -s /bin/bash -G sudo aspire
RUN (echo "ai4code"; echo "ai4code") | passwd aspire

# Copy shell files
COPY src/*.sh /home/aspire/
RUN chown aspire.aspire -R /home/aspire/* /home/aspire/.[a-z]*

# New tools folder for dependency installation
RUN mkdir -p /home/aspire/tools

###############################################################################
# DEPENDENCIES (LLVM)
###############################################################################

USER root

RUN cd /home/aspire/tools/ \
    && wget https://github.com/llvm/llvm-project/archive/llvmorg-10.0.0.zip \
    && unzip llvmorg-10.0.0.zip \
    && cd llvm-project-llvmorg-10.0.0 \
    && mkdir build \
    && cd build \
    && CC=clang CXX=clang++ cmake -DCMAKE_BUILD_TYPE=Release \
       -DCMAKE_EXE_LINKER_FLAGS="-static-libstdc++" \
       -DLLVM_ENABLE_PROJECTS="clang;lld" \
       -DLLVM_TEMPORARILY_ALLOW_OLD_TOOLCHAIN=on \
       -G "Unix Makefiles" ../llvm \
    && make -j32 \
    && make install

RUN echo "alias sudo='sudo LLVM_COMPILER=\$LLVM_COMPILER'" >> /home/aspire/.bashrc
RUN echo 'export LLVM_COMPILER=clang' >> /home/aspire/.bashrc

###############################################################################
# DEPENDENCIES (PYTHON)
###############################################################################

USER aspire

# Utilities
RUN pip3 install mypy yapf pytest python-magic termcolor

# ML Related Dependencies
RUN pip3 install graphviz scikit-learn matplotlib pandas

# PL Related Dependencies
RUN pip3 install wllvm

###############################################################################
# DEPENDENCIES (CONDA)
###############################################################################

USER root

RUN cd /home/aspire/tools/ \
    && wget https://repo.anaconda.com/archive/Anaconda3-2020.02-Linux-x86_64.sh \
    && chmod +x Anaconda3-2020.02-Linux-x86_64.sh \
    && ./Anaconda3-2020.02-Linux-x86_64.sh -b -p /home/aspire/tools/anaconda3

RUN echo "PATH='/home/aspire/tools/anaconda3/bin/:$PATH'" >> /home/aspire/.bashrc

###############################################################################
# DEPENDENCIES (OCAML)
###############################################################################

# Install ocaml with root
USER root
RUN curl -sL https://raw.githubusercontent.com/ocaml/opam/master/shell/install.sh > /home/aspire/install-opam.sh
RUN echo "\n" | sh /home/aspire/install-opam.sh
RUN rm /home/aspire/install-opam.sh

# Init & Config with aspire
USER aspire
RUN opam init -y --disable-sandboxing

# Utilities
RUN opam install -y ocamlbuild ocamlformat merlin parmap
RUN opam install -y ocamlgraph yojson ppx_compare ppx_deriving ppx_deriving_yojson

# LLVM & Z3
RUN opam install -y llvm ctypes ctypes-foreign z3

# Update bashrc
RUN echo "eval `opam env`" >> /home/aspire/.bashrc

###############################################################################
# Setup Compiler
###############################################################################

USER root

# Link wllvm as default compiler
RUN rm /usr/bin/x86_64-linux-gnu-gcc
RUN rm /usr/bin/x86_64-linux-gnu-g++
RUN ln -s /usr/local/bin/wllvm /usr/bin/x86_64-linux-gnu-gcc
RUN ln -s /usr/local/bin/wllvm++ /usr/bin/x86_64-linux-gnu-g++

###############################################################################
# STARTUP COMMAND
###############################################################################

USER root

# SSH Port Exposure
EXPOSE 22

# SSHD
CMD ["/usr/sbin/sshd", "-D"]
