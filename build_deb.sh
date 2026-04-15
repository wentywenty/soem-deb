#!/bin/bash
set -euo pipefail

PACKAGE_NAME="libsoem-dev"
VERSION="2.0.0.1"
UPSTREAM_VERSION="2.0.0"

WORK_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE_DIR="$WORK_DIR/SOEM"
DEBIAN_DIR="$WORK_DIR/debian"
BUILD_ROOT="$WORK_DIR/build"
OUTPUT_DIR="$WORK_DIR/output"

if [[ "$(uname -s)" != "Linux" ]]; then
    echo "Error: build_deb.sh only supports Linux builds."
    exit 1
fi

if [[ ! -d "$SOURCE_DIR" ]]; then
    echo "Error: SOEM submodule not found at $SOURCE_DIR"
    echo "Run: git submodule update --init --recursive"
    exit 1
fi

if [[ ! -d "$DEBIAN_DIR" ]]; then
    echo "Error: Debian packaging directory not found at $DEBIAN_DIR"
    exit 1
fi

detect_arch() {
    local detected

    if command -v dpkg >/dev/null 2>&1; then
        detected="$(dpkg --print-architecture)"
    else
        detected="$(uname -m)"
    fi

    case "$detected" in
        amd64|x86_64)
            echo "amd64"
            ;;
        arm64|aarch64)
            echo "arm64"
            ;;
        *)
            echo "$detected"
            ;;
    esac
}

ARCH="${ARCH:-$(detect_arch)}"

case "$ARCH" in
    amd64)
        GNU_TRIPLET="x86_64-linux-gnu"
        CMAKE_PROCESSOR="x86_64"
        ;;
    arm64)
        GNU_TRIPLET="aarch64-linux-gnu"
        CMAKE_PROCESSOR="aarch64"
        ;;
    *)
        echo "Error: unsupported ARCH '$ARCH'. Use amd64 or arm64."
        exit 1
        ;;
esac

install_build_dependencies() {
    local packages=(build-essential dpkg-dev python3-pip)

    if [[ "$ARCH" == "arm64" ]]; then
        packages+=(gcc-aarch64-linux-gnu g++-aarch64-linux-gnu)
    fi

    if ! command -v sudo >/dev/null 2>&1; then
        echo "Error: sudo is required when INSTALL_DEPS=1."
        exit 1
    fi

    sudo apt-get update
    sudo apt-get install -y "${packages[@]}"
    python3 -m pip install --user "cmake>=3.28"
    export PATH="$HOME/.local/bin:$PATH"
    hash -r
}

if [[ "${INSTALL_DEPS:-0}" == "1" ]]; then
    install_build_dependencies
fi

if ! command -v cmake >/dev/null 2>&1; then
    echo "Error: cmake is required but was not found in PATH."
    exit 1
fi

cmake_version="$(cmake --version | awk 'NR==1 {print $3}')"
if [[ "$(printf '%s\n' "3.28.0" "$cmake_version" | sort -V | head -n 1)" != "3.28.0" ]]; then
    echo "Error: SOEM v$UPSTREAM_VERSION requires CMake 3.28 or newer."
    echo "Detected: $cmake_version"
    exit 1
fi

if ! command -v dpkg-deb >/dev/null 2>&1; then
    echo "Error: dpkg-deb is required but was not found in PATH."
    exit 1
fi

BUILD_DIR="$BUILD_ROOT/$ARCH"
STAGE_DIR="$BUILD_DIR/stage"
PACKAGE_DIR="$BUILD_DIR/package-root"
DEB_PATH="$OUTPUT_DIR/${PACKAGE_NAME}_${VERSION}_${ARCH}.deb"

echo "=== Build Configuration ==="
echo "Work Dir:         $WORK_DIR"
echo "Source Dir:       $SOURCE_DIR"
echo "Package Name:     $PACKAGE_NAME"
echo "Package Version:  $VERSION"
echo "Upstream Version: $UPSTREAM_VERSION"
echo "Architecture:     $ARCH"
echo "GNU Triplet:      $GNU_TRIPLET"
echo "Cross Prefix:     ${CROSS_PREFIX:-<native>}"
echo "Artifact Path:    $DEB_PATH"
echo "==========================="

rm -rf "$BUILD_DIR" "$PACKAGE_DIR" "$DEB_PATH"
mkdir -p "$BUILD_DIR" "$OUTPUT_DIR"

CMAKE_ARGS=(
    -S "$SOURCE_DIR"
    -B "$BUILD_DIR"
    -DCMAKE_BUILD_TYPE=Release
    -DCMAKE_INSTALL_PREFIX=/usr
    -DBUILD_SHARED_LIBS=ON
    -DSOEM_BUILD_SAMPLES=OFF
)

if [[ -n "${CROSS_PREFIX:-}" ]]; then
    if ! command -v "${CROSS_PREFIX}gcc" >/dev/null 2>&1; then
        echo "Error: compiler ${CROSS_PREFIX}gcc was not found in PATH."
        exit 1
    fi

    if ! command -v "${CROSS_PREFIX}g++" >/dev/null 2>&1; then
        echo "Error: compiler ${CROSS_PREFIX}g++ was not found in PATH."
        exit 1
    fi

    CMAKE_ARGS+=(
        -DCMAKE_SYSTEM_NAME=Linux
        -DCMAKE_SYSTEM_PROCESSOR="$CMAKE_PROCESSOR"
        -DCMAKE_C_COMPILER="${CROSS_PREFIX}gcc"
        -DCMAKE_CXX_COMPILER="${CROSS_PREFIX}g++"
    )
fi

echo "[1/4] Configuring project..."
cmake "${CMAKE_ARGS[@]}"

echo "[2/4] Building project..."
cmake --build "$BUILD_DIR" --parallel "$(nproc)"

echo "[3/4] Installing into staging directory..."
rm -rf "$STAGE_DIR"
DESTDIR="$STAGE_DIR" cmake --install "$BUILD_DIR"

echo "[4/4] Preparing Debian package layout..."
mkdir -p "$PACKAGE_DIR"
cp -a "$STAGE_DIR/." "$PACKAGE_DIR/"

mkdir -p "$PACKAGE_DIR/usr/lib/$GNU_TRIPLET"
if compgen -G "$PACKAGE_DIR/usr/lib/libsoem*" >/dev/null; then
    mv "$PACKAGE_DIR"/usr/lib/libsoem* "$PACKAGE_DIR/usr/lib/$GNU_TRIPLET/"
fi

if [[ -d "$PACKAGE_DIR/usr/cmake" ]]; then
    mkdir -p "$PACKAGE_DIR/usr/lib/$GNU_TRIPLET/cmake/soem"
    cp -a "$PACKAGE_DIR/usr/cmake/." "$PACKAGE_DIR/usr/lib/$GNU_TRIPLET/cmake/soem/"
    rm -rf "$PACKAGE_DIR/usr/cmake"
fi

if [[ -d "$PACKAGE_DIR/usr/scripts" ]]; then
    mkdir -p "$PACKAGE_DIR/usr/share/soem/scripts"
    cp -a "$PACKAGE_DIR/usr/scripts/." "$PACKAGE_DIR/usr/share/soem/scripts/"
    rm -rf "$PACKAGE_DIR/usr/scripts"
fi

mkdir -p "$PACKAGE_DIR/usr/share/doc/$PACKAGE_NAME"
for doc_file in README.md LICENSE.md; do
    if [[ -f "$PACKAGE_DIR/usr/$doc_file" ]]; then
        mv "$PACKAGE_DIR/usr/$doc_file" "$PACKAGE_DIR/usr/share/doc/$PACKAGE_NAME/$doc_file"
    fi
done

mkdir -p "$PACKAGE_DIR/usr/lib/$GNU_TRIPLET/pkgconfig"
cat > "$PACKAGE_DIR/usr/lib/$GNU_TRIPLET/pkgconfig/soem.pc" <<EOF
prefix=/usr
exec_prefix=\${prefix}
includedir=\${prefix}/include
libdir=\${prefix}/lib/$GNU_TRIPLET

Name: soem
Description: Simple Open EtherCAT Master library
Version: $VERSION
Libs: -L\${libdir} -lsoem
Cflags: -I\${includedir}
EOF

if [[ -d "$PACKAGE_DIR/usr/lib/$GNU_TRIPLET/cmake/soem" ]]; then
    find "$PACKAGE_DIR/usr/lib/$GNU_TRIPLET/cmake/soem" -type f \( -name '*.cmake' -o -name '*Config*' \) -print0 | while IFS= read -r -d '' cmake_file; do
        sed -i "s#/usr/lib/#/usr/lib/$GNU_TRIPLET/#g" "$cmake_file"
        sed -i "s#\${_IMPORT_PREFIX}/lib/#\${_IMPORT_PREFIX}/lib/$GNU_TRIPLET/#g" "$cmake_file"
    done
fi

mkdir -p "$PACKAGE_DIR/usr/lib/cmake"
ln -sfn "../$GNU_TRIPLET/cmake/soem" "$PACKAGE_DIR/usr/lib/cmake/soem"

find "$PACKAGE_DIR" -type d -empty -delete

mkdir -p "$PACKAGE_DIR/DEBIAN"
sed \
    -e "s/ARCH_PLACEHOLDER/$ARCH/g" \
    -e "s/VERSION_PLACEHOLDER/$VERSION/g" \
    "$DEBIAN_DIR/control" > "$PACKAGE_DIR/DEBIAN/control"

for maintainer_script in preinst postinst prerm postrm; do
    if [[ -f "$DEBIAN_DIR/$maintainer_script" ]]; then
        cp "$DEBIAN_DIR/$maintainer_script" "$PACKAGE_DIR/DEBIAN/$maintainer_script"
        chmod 755 "$PACKAGE_DIR/DEBIAN/$maintainer_script"
    fi
done

dpkg-deb --root-owner-group --build "$PACKAGE_DIR" "$DEB_PATH"

echo "=== Build Success ==="
echo "Output: $DEB_PATH"