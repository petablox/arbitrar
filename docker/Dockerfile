# Use 18.04 because cuML uses this
FROM ubuntu:18.04
ARG DEBIAN_FRONTEND=noninteractive
FROM nvidia/cuda:10.0-base

###############################################################################
# BASICS
###############################################################################

RUN apt-get update
RUN apt-get install -y curl unzip git vim sudo clang gcc cmake m4 \
                       libgmp-dev python3-pip python3.7 pkg-config \
                       graphviz

# Use python3.7 to install pip3
# Note: we choose 3.7 because cuML supports python 3.7
RUN python3.7 -m pip install pip

# Set default python3 to python3.7
RUN rm /usr/bin/python3
RUN ln -s /usr/bin/python3.7 /usr/bin/python3

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

# New tools folder for dependency installation
RUN mkdir -p /home/aspire/tools

# Chown
RUN chown aspire.aspire -R /home/aspire/* /home/aspire/.[a-z]*

###############################################################################
# DEPENDENCIES (LLVM)
###############################################################################

USER root

# Download LLVM
WORKDIR /home/aspire/tools/
RUN wget --quiet https://github.com/llvm/llvm-project/archive/llvmorg-10.0.0.zip
RUN unzip -q llvmorg-10.0.0.zip
RUN rm llvmorg-10.0.0.zip

# Compile LLVM
WORKDIR /home/aspire/tools/llvm-project-llvmorg-10.0.0
RUN mkdir build
WORKDIR /home/aspire/tools/llvm-project-llvmorg-10.0.0/build
RUN CC=clang CXX=clang++ cmake -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_EXE_LINKER_FLAGS="-static-libstdc++" \
    -DLLVM_ENABLE_PROJECTS="clang;lld" \
    -DLLVM_TEMPORARILY_ALLOW_OLD_TOOLCHAIN=on \
    -G "Unix Makefiles" ../llvm
RUN make -j32 && make install

# RUN echo "alias sudo='sudo LLVM_COMPILER=\$LLVM_COMPILER'" >> /home/aspire/.bashrc
RUN echo "export LLVM_COMPILER=clang" >> /home/aspire/.bashrc

###############################################################################
# DEPENDENCIES (PYTHON)
###############################################################################

USER aspire

# Utilities
RUN python3.7 -m pip install mypy yapf pytest wllvm

###############################################################################
# DEPENDENCIES (OCAML)
###############################################################################

# Install ocaml with root
USER root

WORKDIR /home/aspire/tools/
RUN wget --quiet https://raw.githubusercontent.com/ocaml/opam/master/shell/install.sh
RUN echo "\n" | sh install.sh
RUN rm install.sh

# Init & Config with aspire
USER aspire
RUN opam init -y --disable-sandboxing

# Dependencies
RUN opam install -y ocamlbuild ocamlformat merlin parmap \
                    ocamlgraph yojson ppx_compare ppx_deriving ppx_deriving_yojson \
                    llvm ctypes ctypes-foreign z3

# Update bashrc
RUN echo "eval `opam env`" >> /home/aspire/.bashrc

###############################################################################
# DEPENDENCIES (CUDA)
###############################################################################

# Install cuda toolkit 10.1 first
USER root

WORKDIR /home/aspire/tools/
ENV CUDA_VERSION=10.1.243_418.87.00
RUN wget --quiet http://developer.download.nvidia.com/compute/cuda/10.1/Prod/local_installers/cuda_${CUDA_VERSION}_linux.run
RUN sh cuda_${CUDA_VERSION}_linux.run --toolkit --silent
RUN rm cuda_${CUDA_VERSION}_linux.run

# RUN echo "/usr/local/cuda-10.1/lib64" >> /etc/ld.so.conf && ldconfig

USER aspire

# Setup cuda
RUN LD_LIBRARY_PATH=/usr/local/cuda-10.1/lib64

###############################################################################
# DEPENDENCIES (CONDA)
###############################################################################

# Then install anaconda3
USER aspire
WORKDIR /home/aspire/tools/
RUN wget --quiet https://repo.anaconda.com/archive/Anaconda3-2020.02-Linux-x86_64.sh
RUN chmod +x Anaconda3-2020.02-Linux-x86_64.sh
RUN ./Anaconda3-2020.02-Linux-x86_64.sh -b -p /home/aspire/tools/anaconda3
RUN rm ./Anaconda3-2020.02-Linux-x86_64.sh

# Setup conda path
RUN echo "PATH=\"/home/aspire/tools/anaconda3/bin/:\$PATH\"" >> /home/aspire/.bashrc

# Use conda to install other dependencies
ENV CONDA=/home/aspire/tools/anaconda3/bin/conda
ENV CONDA_ENV_NAME=arbitrar

# Initialize conda
RUN ${CONDA} init bash
RUN ${CONDA} create --name ${CONDA_ENV_NAME} python=3.7
RUN echo "source activate ${CONDA_ENV_NAME}" >> /home/aspire/.bashrc

# Use conda to install dependencies

RUN ${CONDA} install -n ${CONDA_ENV_NAME} -c conda-forge \
    python-magic termcolor pygraphviz joblib \
    pandas scikit-learn matplotlib

# faiss-gpu (https://github.com/rapidsai/cuml/issues/25)
# RUN /home/aspire/tools/anaconda3/bin/conda install -y -c pytorch faiss-gpu

# RUN /home/aspire/tools/anaconda3/bin/conda install -n ${CONDA_ENV_NAME} \
#     -c rapidsai-nightly -c nvidia -c conda-forge -c defaults \
#     cuml=0.14 python=3.7 cudatoolkit=10.1

RUN ${CONDA} install -n ${CONDA_ENV_NAME} tsnecuda cuda101 -c cannylab

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
