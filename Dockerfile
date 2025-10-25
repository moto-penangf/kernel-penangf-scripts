FROM ubuntu:22.04

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    clang \
    llvm \
    lld \
    bc \
    cpio \
    flex \
    bison \
    libssl-dev \
    libelf-dev \
    libncurses-dev \
    git \
    python2 \
    kmod \
    curl \
    wget \
    pkg-config \
    ca-certificates \
    gcc-aarch64-linux-gnu \
    g++-aarch64-linux-gnu \
    gcc-arm-linux-gnueabihf \
    g++-arm-linux-gnueabihf \
    binutils-arm-linux-gnueabihf \
    zip \
    vim

WORKDIR /workdir
ENV ARCH=arm64
ENV CROSS_COMPILE=aarch64-linux-gnu-

RUN ln -s /usr/bin/python2 /usr/bin/python

CMD ["/bin/bash"]
