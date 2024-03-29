#!/bin/bash

set -exuo pipefail

export CXXFLAGS="${CXXFLAGS} -std=c++17"

if [[ "${target_platform}" == osx-* ]]; then
  export CXXFLAGS="${CXXFLAGS} -D_LIBCPP_DISABLE_AVAILABILITY"
  export LDFLAGS="${LDFLAGS} -lz -framework CoreFoundation -Xlinker -undefined -Xlinker dynamic_lookup"
else
  export LDFLAGS="${LDFLAGS} -lrt"
fi

pushd utils/bazel
# Omit building the unit tests
rm -rf llvm-project-overlay/llvm/unittests/ llvm-project-overlay/mlir/unittests/ llvm-project-overlay/mlir/examples
source gen-bazel-toolchain
bazel build \
    --repo_env=BAZEL_LLVM_ZLIB_STRATEGY=system \
    --@llvm-project//libc:mpfr=disable \
    --@llvm-project//llvm:pfm=disable \
    --crosstool_top=//bazel_toolchain:toolchain \
    --cpu ${TARGET_CPU} \
    -- \
    @llvm-project//llvm/... @llvm-project//mlir/... \
    -@llvm-project//llvm:yaml2obj -@llvm-project//llvm:obj2yaml -@llvm-project//llvm:llvm-pdbutil -@llvm-project//llvm:llvm-rc \
    -@llvm-project//mlir:mlir-pdll -@llvm-project//mlir/python/...
popd

mkdir -p ${PREFIX}/share/llvm-bazel-cache
# Copy headers and other sources to be re-used in the downstream project.
cp -ap llvm mlir utils ${PREFIX}/share/llvm-bazel-cache/
cp utils/bazel/bazel-bazel/external/llvm-project/vars.bzl ${PREFIX}/share/llvm-bazel-cache/

# Remove bazel-build artifacts
rm -rf ${PREFIX}/share/llvm-bazel-cache/utils/bazel/bazel-*
rsync -a utils/bazel/llvm-project-overlay/ ${PREFIX}/share/llvm-bazel-cache/
# These files will be generated by the Python script below, ensure that we
# don't accidentially keep the original.
rm ${PREFIX}/share/llvm-bazel-cache/llvm/BUILD.bazel
rm ${PREFIX}/share/llvm-bazel-cache/mlir/BUILD.bazel

# Delete some files that break LIEF (and aren't needed)
rm -rf ${PREFIX}/share/llvm-bazel-cache/clang/test/
rm -rf ${PREFIX}/share/llvm-bazel-cache/llvm/test/
rm -rf ${PREFIX}/share/llvm-bazel-cache/llvm/utils/lit/tests
find ${PREFIX}/share/llvm-bazel-cache -name '*.a' -delete
find ${PREFIX}/share/llvm-bazel-cache -name '*.exe' -delete
find ${PREFIX}/share/llvm-bazel-cache -name '*.dll' -delete
find ${PREFIX}/share/llvm-bazel-cache -name '*.o' -delete

mkdir -p ${PREFIX}/lib/llvm-bazel-cache
# Copy over the static libraries and generate bazel BUILD files that reference them.
python $RECIPE_DIR/compile_bundle.py
