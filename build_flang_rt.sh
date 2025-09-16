#!/usr/bin/env bash
#
# Build and install the "flang-rt" runtime library.
#
# This requires that you already finished `build.sh`.
# Please refer to README.FLANG-RT.md for details.
#

pushd "${0%/*}" &>/dev/null

DESC=flang-rt
source tools/tools.sh
eval $(tools/osxcross_conf.sh)

if [ $PLATFORM == "Darwin" ]; then
  exit 1
fi

CLANG_VERSION=$(echo "__clang_major__ __clang_minor__ __clang_patchlevel__" | \
 xcrun clang -xc -E - | tail -n1 | tr ' ' '.')

# Drop patch level for <= 3.3.
if [ $(osxcross-cmp $CLANG_VERSION "<=" 3.3) -eq 1 ]; then
  CLANG_VERSION=$(echo $CLANG_VERSION | tr '.' ' ' |
                  awk '{print $1, $2}' | tr ' ' '.')
fi

FLANG_VERSION=$(xcrun flang-new -dumpversion)
FLANG_VERSION_MAJOR=$(echo "${FLANG_VERSION}" | cut -d '.' -f 1)

CLANG_LIB_DIR=$(clang -print-search-dirs | grep "libraries: =" | \
                tr '=' ' ' | tr ':' ' ' | awk '{print $2}')

VERSION=$(echo "${CLANG_LIB_DIR}" | tr '/' '\n' | tail -n1)
CLANG_INCLUDE_DIR="${CLANG_LIB_DIR}/include"
CLANG_DARWIN_LIB_DIR="${CLANG_LIB_DIR}/lib/darwin"

# NOTE: flang did not exist until version 11.x
# NOTE: flang was considered experiemntal until version 20.x
# NOTE: flang-rt was broken out into the flang-rt directory in version 21.x
case $FLANG_VERSION in
  21.* ) BRANCH=release/21.x ;;
  22.* ) BRANCH=main ;;
     * ) echo "Unsupported Flang version, must be >= 21.x and <= 22.x" 1>&2; exit 1;
esac

if [ $(osxcross-cmp $CLANG_VERSION ">=" 3.5) -eq 1 ]; then
  export MACOSX_DEPLOYMENT_TARGET=10.8 # x86_64h
else
  export MACOSX_DEPLOYMENT_TARGET=10.4
fi

if [ $(osxcross-cmp $MACOSX_DEPLOYMENT_TARGET ">" \
                    $SDK_VERSION) -eq 1 ];
then
  echo ">= $MACOSX_DEPLOYMENT_TARGET SDK required" 1>&2
  exit 1
fi

export OSXCROSS_NO_10_5_DEPRECATION_WARNING=1

mkdir -p $BUILD_DIR

pushd $BUILD_DIR &>/dev/null

# Check if a build project for flang-rt already exists.
# Delete any directory that is called flang-rt, but is not a build project.
if [ -d "$BUILD_DIR/flang-rt" ] && [ ! -d "$BUILD_DIR/flang_rt/flang-rt" ]; then
    rm -rf "$BUILD_DIR/flang-rt"
fi

get_sources https://github.com/llvm/llvm-project.git $BRANCH "flang-rt"

if [ $f_res -eq 1 ]; then
  pushd "$CURRENT_BUILD_PROJECT_NAME/flang-rt" &>/dev/null

  EXTRA_MAKE_FLAGS=""
  if [ -n "$OCDEBUG" ]; then
    EXTRA_MAKE_FLAGS+="VERBOSE=1 "
  fi

  function build
  {
    local arch=$1
    local build_dir="build"
    local extra_cmake_flags=""

    if [ -n "$arch" ]; then
      build_dir+="_$arch"

      extra_cmake_flags+="-DCMAKE_OSX_ARCHITECTURES=$arch "

      echo ""
      echo "Building for arch $arch ..."
      echo ""
    fi

    mkdir $build_dir
    pushd $build_dir &>/dev/null

    COMPILER_DIR=$(dirname $(xcrun -f clang))
    TARGET_SUFFIX=$(xcrun clang --version | grep Target | cut -d ':' -f 2 | cut -d '-' -f 2-)
    TARGET="${arch}-${TARGET_SUFFIX}"
    C_COMPILER="${COMPILER_DIR}/${TARGET}-clang"
    CXX_COMPILER="${COMPILER_DIR}/${TARGET}-clang++"
    Fortran_COMPILER="${COMPILER_DIR}/${TARGET}-flang-new"
    LIPO_EXEC="${COMPILER_DIR}/${TARGET}-lipo"
    AR_EXEC="${COMPILER_DIR}/${TARGET}-ar"
    NM_EXEC="${COMPILER_DIR}/${TARGET}-nm"
    RANLIB_EXEC="${COMPILER_DIR}/${TARGET}-ranlib"
    STRIP_EXEC="${COMPILER_DIR}/${TARGET}-strip"
    INSTALL_NAME_TOOL_EXEC="${COMPILER_DIR}/${TARGET}-install_name_tool"
    LINKER="${COMPILER_DIR}/${TARGET}-ld"

    CC="${C_COMPILER}" CXX="${CXX_COMPILER}" FC="${Fortran_COMPILER}" $CMAKE \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_SYSTEM_NAME=Darwin \
      -DCMAKE_OSX_SYSROOT="$(xcrun --show-sdk-path)" \
      -DCMAKE_AR="${AR_EXEC}" \
      -DCMAKE_NM="${NM_EXEC}" \
      -DCMAKE_RANLIB="${RANLIB_EXEC}" \
      -DCMAKE_STRIP="${STRIP_EXEC}" \
      -DCMAKE_INSTALL_NAME_TOOL="${INSTALL_NAME_TOOL_EXEC}" \
      -DLLVM_ENABLE_RUNTIMES="flang-rt" \
      -DFLANG_RT_ENABLE_SHARED=ON \
      -DFLANG_RT_ENABLE_STATIC=ON \
      -DCMAKE_Fortran_COMPILER_WORKS=TRUE \
      $extra_cmake_flags \
      ../../runtimes

    $MAKE -j $JOBS $EXTRA_MAKE_FLAGS

    popd &>/dev/null
  }

  if [ $(osxcross-cmp $SDK_VERSION ">=" 11.0) -eq 1 ] &&
     [ $(osxcross-cmp $CLANG_VERSION ">=" 4.0) -eq 1 ]; then
    # https://github.com/tpoechtrager/osxcross/issues/258
    # https://github.com/tpoechtrager/osxcross/issues/286

    function check_archs
    {
      tmp=$(mktemp -d)
      [ -z "$tmp" ] && exit 1
      pushd $tmp &>/dev/null

      for arch in $*; do
        # We still use clang for the test because flang doesn't' support the '-arch' option
        if echo "int main(){}" | xcrun clang -arch $arch -xc -o test - &>/dev/null; then
          rm test
          [ -n "$ARCHS" ] && ARCHS+=" "
          ARCHS+="$arch"
        fi
      done

      popd &>/dev/null
      rmdir $tmp
    }

    ARCHS=""
    check_archs i386 x86_64 x86_64h arm64 arm64e
 
    if [ -z "$ARCHS" ]; then
      echo "Compiler does not seem to work"
      exit 1
    fi

    echo ""
    echo "Building for archs $ARCHS ..."
    echo ""

    if [ -z "$DISABLE_PARALLEL_ARCH_BUILD" ] && [ $JOBS -gt 2 ]; then
      build_pids="";
      jobs_per_build_job=$(awk "BEGIN{print int($JOBS/$(echo $ARCHS | wc -w)+0.5)}")
      ((jobs_per_build_job=jobs_per_build_job+1))

      for arch in $ARCHS; do
        JOBS=$jobs_per_build_job build $arch &
        build_pids+=" $!"
      done

      for pid in $build_pids; do
        wait $pid || {
          echo ""
          echo "Build failed!"
          echo "Use DISABLE_PARALLEL_ARCH_BUILD=1 to disable parallel building of architectures"
          echo ""
          exit 1
        }
      done
    else
      for arch in $ARCHS; do
        build $arch
      done
    fi

    # Find static and shared libraries generated for each architecture
    static_libs=()
    shared_libs=()
    for arch in $ARCHS; do
      lib=$BUILD_DIR/flang-rt/flang-rt/build_${arch}/flang-rt/lib/libflang_rt.runtime.a
      if [ -f "${lib}" ]; then
        static_libs+=("${lib}")
      fi
      lib=$BUILD_DIR/flang-rt/flang-rt/build_${arch}/flang-rt/lib/libflang_rt.runtime.dylib
      if [ -f "${lib}" ]; then
        shared_libs+=("${lib}")
      fi 
    done

    # Combine the separate static libraries for each architecture into a single "fat" 
    # library that supports all architectures
    if (( ${#static_libs[@]} > 0 )); then
      xcrun lipo -create "${static_libs[@]}" -output "${BUILD_DIR}/flang-rt/flang-rt/libflang_rt.runtime.a"
    fi

    # Combine the separate shared libraries for each architecture into a single "fat" 
    # library that supports all architectures
    if (( ${#shared_libs[@]} > 0 )); then
      xcrun lipo -create "${shared_libs[@]}" -output "${BUILD_DIR}/flang-rt/flang-rt/libflang_rt.runtime.dylib"
    fi

  else
    build
  fi

  build_success
fi

# We must re-build every time. git clean -fdx
# removes the libraries.
rm -f $BUILD_DIR/.flang-rt_build_complete


# Installation. Can be either automated (ENABLE_FLANG_RT_INSTALL) or will
# print the commands that the user should run manually.

function print_or_run() {
  if [ -z "$ENABLE_FLANG_RT_INSTALL" ]; then
    echo "$@"
  else
    $@
  fi
}

ENABLE_FLANG_RT_INSTALL=0

echo ""
echo ""
echo ""
if [ -z "$ENABLE_FLANG_RT_INSTALL" ]; then
  echo "Please run the following commands by hand to install flang-rt:"
else
  echo "Installing flang-rt headers and libraries to the following paths:"
  echo "  ${CLANG_DARWIN_LIB_DIR}"
fi
echo ""

print_or_run mkdir -p ${CLANG_DARWIN_LIB_DIR}

if [ -f "${BUILD_DIR}/flang-rt/flang-rt/libflang_rt.runtime.dylib" ]; then
  print_or_run cp -v "${BUILD_DIR}/flang-rt/flang-rt/libflang_rt.runtime.dylib" "${CLANG_DARWIN_LIB_DIR}"
fi

if [ -f "${BUILD_DIR}/flang-rt/flang-rt/libflang_rt.runtime.a" ]; then
  print_or_run cp -v "${BUILD_DIR}/flang-rt/flang-rt/libflang_rt.runtime.a" "${CLANG_DARWIN_LIB_DIR}"
fi


echo ""
