#!/bin/bash

docker build -t penangf-kernel-build .

docker run --rm -it \
  -v $(pwd):/workspace \
  -w /workspace \
  penangf-kernel-build
