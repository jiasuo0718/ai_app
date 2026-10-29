#!/usr/bin/env bash
# 交叉编译 android/arm64 固件手术工具 -> assets/tools/
# 用法: build-native-tools.sh <android-ndk 路径>
set -euo pipefail

NDK="${1:?用法: build-native-tools.sh <android-ndk路径>}"
TC="$NDK/toolchains/llvm/prebuilt/linux-x86_64"
TARGET=aarch64-linux-android
API=24

OUT="assets/tools"
# 关键: 绝对路径(configure 在子目录跑, 相对 -L 会解析错)
WORK="$PWD/.build-tools"
STAGE="$WORK/stage"
mkdir -p "$OUT" "$WORK" "$STAGE"

log() { echo -e "\n### $1 ###"; }

# ---- configure 失败诊断 ----
dump_configure_failure() {
  local log="${1:-config.log}"
  [ -f "$log" ] || { echo "!! $log not found"; return; }
  echo "================ config.log: C compiler sanity check ================"
  awk '/checking whether the C compiler works/ {flag=1} flag {print} /checking whether we are cross compiling/ {if(flag){exit}}' "$log" | head -120
  echo "================ config.log: conftest.c blocks (link tests) ================"
  grep -n -B2 -A25 'conftest\.c' "$log" | head -300
  echo "================ config.log: real errors ================"
  grep -n -iE '(error:|undefined reference|cannot find|No such file|not found|fatal error|cannot open)' "$log" | head -80
  echo "================ config.log: tail 120 ================"
  tail -n 120 "$log"
  local cmd
  cmd=$(grep -m1 -E '^configure:[0-9]+: .*clang' "$log" | sed 's/^configure:[0-9]*: //' || true)
  if [ -n "$cmd" ]; then
    echo "================ replay first CC check ================"
    echo "+ $cmd"
    ( cd "$(dirname "$log")" && eval "$cmd" ) || echo "!! replay exit=$?"
  fi
}

# ---- 1. lz4 静态库 ----
build_lz4() {
  [ -f "$STAGE/lib/liblz4.a" ] && { log "lz4 已存在, 跳过"; return; }
  log "编译 lz4 (android/arm64)"
  rm -rf "$WORK/lz4"
  git clone --depth 1 -q https://github.com/lz4/lz4.git "$WORK/lz4"
  make -C "$WORK/lz4/lib" CC="$TC/bin/${TARGET}${API}-clang" AR="$TC/bin/llvm-ar" liblz4.a -j"$(nproc)"
  make -C "$WORK/lz4/lib" CC="$TC/bin/${TARGET}${API}-clang" AR="$TC/bin/llvm-ar" PREFIX="$STAGE" install
  rm -f "$STAGE"/lib/liblz4.so*   # 双保险: 只留静态, 避免 .so 干扰链接
  echo "lz4 静态库: $(ls -la "$STAGE/lib/liblz4.a" | awk '{print $5}') bytes"
}

# ---- 2. erofs-utils ----
build_erofs() {
  [ -f "$OUT/mkfs.erofs" ] && { log "erofs 已存在, 跳过"; return; }
  log "编译 erofs-utils (android/arm64)"
  rm -rf "$WORK/erofs"
  git clone --depth 1 -q -b dev https://github.com/erofs/erofs-utils.git "$WORK/erofs"
  cd "$WORK/erofs"
  ./autogen.sh

  export CC="$TC/bin/${TARGET}${API}-clang"
  export CXX="$TC/bin/${TARGET}${API}-clang++"
  export AR="$TC/bin/llvm-ar"
  export LD="$TC/bin/ld.lld"
  export RANLIB="$TC/bin/llvm-ranlib"
  export STRIP="$TC/bin/llvm-strip"
  export CFLAGS="-O2 -fPIC -Wl,--allow-multiple-definition"
  export CXXFLAGS="-O2 -fPIC -Wl,--allow-multiple-definition"
  export LDFLAGS="-Wl,--allow-multiple-definition -L$STAGE/lib"
  export CPPFLAGS="-I$STAGE/include"
  export LZ4_CFLAGS="-I$STAGE/include"
  export LZ4_LIBS="-L$STAGE/lib -llz4"
  export PKG_CONFIG_PATH="$STAGE/lib/pkgconfig"

  if ! ./configure \
       --host="$TARGET" \
       --prefix="$STAGE" \
       --enable-static --disable-shared \
       --without-selinux --without-uuid \
       LZ4_CFLAGS="$LZ4_CFLAGS" LZ4_LIBS="$LZ4_LIBS" \
       > configure.out 2>&1; then
    echo "!! configure failed"; tail -n 60 configure.out
    dump_configure_failure config.log
    exit 1
  fi

  make -j"$(nproc)"
  cd -
  cp "$WORK/erofs/mkfs/mkfs.erofs" "$OUT/"
  cp "$WORK/erofs/dump/dump.erofs" "$OUT/"
  cp "$WORK/erofs/fsck/fsck.erofs" "$OUT/"
}

# ---- 3. payload-dumper-go ----
build_payload() {
  [ -f "$OUT/payload-dumper-go" ] && { log "payload-dumper-go 已存在, 跳过"; return; }
  log "编译 payload-dumper-go (android/arm64)"
  rm -rf "$WORK/payload"
  git clone --depth 1 -q https://github.com/ssut/payload-dumper-go.git "$WORK/payload"
  cd "$WORK/payload"
  CGO_ENABLED=0 GOOS=android GOARCH=arm64 go build -ldflags "-s -w" -o payload-dumper-go .
  cd -
  cp "$WORK/payload/payload-dumper-go" "$OUT/"
}

build_lz4
build_erofs
build_payload

chmod 755 "$OUT"/mkfs.erofs "$OUT"/dump.erofs "$OUT"/fsck.erofs "$OUT"/payload-dumper-go

log "=== 产物清单 ==="
ls -la "$OUT"
echo ""
echo "=== 文件类型(确认 arm64) ==="
file "$OUT"/mkfs.erofs "$OUT"/dump.erofs "$OUT"/fsck.erofs "$OUT"/payload-dumper-go 2>/dev/null || true
