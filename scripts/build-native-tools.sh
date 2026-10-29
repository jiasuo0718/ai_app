#!/usr/bin/env bash
# 交叉编译 android/arm64 固件手术工具 -> assets/tools/
# 用法: build-native-tools.sh <android-ndk 路径>
set -euo pipefail

NDK="${1:?用法: build-native-tools.sh <android-ndk路径>}"
TC="$NDK/toolchains/llvm/prebuilt/linux-x86_64"
CLANG="$TC/bin/aarch64-linux-android24-clang"
AR="$TC/bin/llvm-ar"

OUT="assets/tools"
WORK=".build-tools"
STAGE="$WORK/stage"
mkdir -p "$OUT" "$WORK" "$STAGE"

log() { echo -e "\n### $1 ###"; }

# ---- 1. lz4 静态库 (供 erofs 链接) ----
build_lz4() {
  [ -f "$STAGE/lib/liblz4.a" ] && { log "lz4 已存在, 跳过"; return; }
  log "编译 lz4 (android/arm64)"
  rm -rf "$WORK/lz4"
  git clone --depth 1 -q https://github.com/lz4/lz4.git "$WORK/lz4"
  make -C "$WORK/lz4/lib" CC="$CLANG" AR="$AR" liblz4.a -j"$(nproc)"
  make -C "$WORK/lz4/lib" CC="$CLANG" AR="$AR" PREFIX="$STAGE" install
}

# ---- 2. erofs-utils: mkfs.erofs / dump.erofs / fsck.erofs ----
build_erofs() {
  [ -f "$OUT/mkfs.erofs" ] && { log "erofs 已存在, 跳过"; return; }
  log "编译 erofs-utils (android/arm64)"
  rm -rf "$WORK/erofs"
  git clone --depth 1 -q -b dev https://github.com/erofs/erofs-utils.git "$WORK/erofs"
  cd "$WORK/erofs"
  ./autogen.sh
  PKG_CONFIG_PATH="$STAGE/lib/pkgconfig" \
  CC="$CLANG" AR="$AR" \
  CPPFLAGS="-I$STAGE/include" \
  LDFLAGS="-L$STAGE/lib" \
  LIBS="-llz4" \
  ./configure --host=aarch64-linux-android --disable-lzma --disable-zstd
  make -j"$(nproc)"
  cd -
  cp "$WORK/erofs/mkfs/mkfs.erofs" "$OUT/"
  cp "$WORK/erofs/dump/dump.erofs" "$OUT/"
  cp "$WORK/erofs/fsck/fsck.erofs" "$OUT/"
}

# ---- 3. payload-dumper-go (OZIP/payload.bin 拆包) ----
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
