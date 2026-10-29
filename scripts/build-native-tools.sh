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

  # ---- Android bionic 把 pthread/rt/dl 并入 libc, 无独立库 —— 建带真符号的桩库满足 -lxxx ----
  build_stub() {
    local name="$1"; local sym="__${name}_stub"; local tmp
    tmp="$(mktemp -d)"
    cat > "$tmp/stub.c" <<EOF
/* $name stub for Android bionic: real symbols live in libc. */
void $sym(void) {}
EOF
    "$TC/bin/${TARGET}${API}-clang" -c "$tmp/stub.c" -o "$tmp/stub.o"
    "$TC/bin/llvm-ar" rcs "$STAGE/lib/lib${name}.a" "$tmp/stub.o"
    "$TC/bin/llvm-ranlib" "$STAGE/lib/lib${name}.a"
    rm -rf "$tmp"
    echo "桩库: $STAGE/lib/lib${name}.a ($sym)"
  }
  build_stub pthread
  build_stub rt
  build_stub dl
  echo "桩库符号校验:"; "$TC/bin/llvm-nm" -s "$STAGE/lib/libpthread.a" 2>/dev/null | head -3 || true

  # ---- 优先 --disable-multithread(最干净) ----
  EXTRA_CONF=()
  if ./configure --help 2>/dev/null | grep -qi 'disable-multithread'; then
    EXTRA_CONF+=('--disable-multithread')
    echo ">> erofs-utils 支持 --disable-multithread, 已启用(无需线程)"
  fi

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
  # PKG_CONFIG_LIBDIR: 只搜我们的 stage, 隐藏宿主机 libxml2/zstd 等避免交叉污染
  export PKG_CONFIG_LIBDIR="$STAGE/lib/pkgconfig"

  # 若支持 --without-libxml2 / --disable-libxml2 就关掉(erofs 核心不需要它)
  if ./configure --help 2>/dev/null | grep -qiE 'with-libxml2|disable-libxml2'; then
    EXTRA_CONF+=('--without-libxml2')
    echo ">> 检测到 libxml2 选项, 追加 --without-libxml2"
  fi

  if ! ./configure \
       --host="$TARGET" \
       --prefix="$STAGE" \
       --enable-static --disable-shared \
       --without-selinux --without-uuid \
       "${EXTRA_CONF[@]+"${EXTRA_CONF[@]}"}" \
       LZ4_CFLAGS="$LZ4_CFLAGS" LZ4_LIBS="$LZ4_LIBS" \
       ac_cv_search_pthread_create="none required" \
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

# ---- 2.5 liblzma(xz): payload-dumper-go 的 go-xz(cgo) 需要 lzma.h ----
build_lzma() {
  [ -f "$STAGE/lib/liblzma.a" ] && { log "liblzma 已存在, 跳过"; return; }
  log "编译 liblzma(xz) (android/arm64)"
  rm -rf "$WORK/xz"
  git clone --depth 1 -q https://github.com/tukaani-project/xz.git "$WORK/xz"
  cd "$WORK/xz"
  ./autogen.sh >/dev/null 2>&1 || true
  CC="$TC/bin/${TARGET}${API}-clang" AR="$TC/bin/llvm-ar" \
  ./configure --host="$TARGET" --prefix="$STAGE" \
      --disable-shared --enable-static \
      --disable-xz --disable-xzdec --disable-lzmadec --disable-lzmainfo --disable-doc \
      > configure.out 2>&1 \
      || { echo "xz configure failed:"; tail -20 configure.out; exit 1; }
  make -C src/liblzma -j"$(nproc)" >/dev/null 2>&1
  make -C src/liblzma install >/dev/null 2>&1
  cd -
  echo "liblzma: $(ls -la "$STAGE/lib/liblzma.a" 2>/dev/null | awk '{print $5}') bytes"
}

# ---- 3. payload-dumper-go ----
build_payload() {
  [ -f "$OUT/payload-dumper-go" ] && { log "payload-dumper-go 已存在, 跳过"; return; }
  log "编译 payload-dumper-go (android/arm64)"
  rm -rf "$WORK/payload"
  git clone --depth 1 -q https://github.com/ssut/payload-dumper-go.git "$WORK/payload"
  cd "$WORK/payload"
  # gozstd(cgo 包) + go-xz(cgo 包, 需 liblzma): 开 CGO + NDK clang + stage 里的静态 lzma
  CC="$TC/bin/${TARGET}${API}-clang" \
  CXX="$TC/bin/${TARGET}${API}-clang++" \
  CGO_ENABLED=1 GOOS=android GOARCH=arm64 \
  CGO_CFLAGS="-I$STAGE/include" \
  CGO_LDFLAGS="-L$STAGE/lib -llzma" \
  go build -ldflags "-s -w" -o payload-dumper-go .
  cd -
  cp "$WORK/payload/payload-dumper-go" "$OUT/"
}

build_lz4
build_lzma
build_erofs
build_payload

chmod 755 "$OUT"/mkfs.erofs "$OUT"/dump.erofs "$OUT"/fsck.erofs "$OUT"/payload-dumper-go

log "=== 产物清单 ==="
ls -la "$OUT"
echo ""
echo "=== 文件类型(确认 arm64) ==="
file "$OUT"/mkfs.erofs "$OUT"/dump.erofs "$OUT"/fsck.erofs "$OUT"/payload-dumper-go 2>/dev/null || true
