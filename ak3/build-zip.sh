#!/usr/bin/env bash
# Build a flashable AnyKernel3 zip from the kernel you just compiled.
#
# Usage (from the kernel source root, after building into ./out):
#   ./ak3/build-zip.sh
#
# Optional environment variables:
#   OUT=<dir>       kernel build output dir        (default: <root>/out)
#   ZIP_NAME=<name> zip name without ".zip"        (default: OP6-SUSFS230-ReSukiSU-<date>)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${OUT:-$ROOT/out}"
IMG="$OUT/arch/arm64/boot/Image.gz-dtb"
WORK="$ROOT/out-ak3"
NAME="${ZIP_NAME:-OP6-SUSFS230-ReSukiSU-$(date +%Y%m%d)}"
ZIP="$ROOT/$NAME.zip"

for tool in git zip; do
  command -v "$tool" >/dev/null 2>&1 || { echo "missing tool: $tool" >&2; exit 1; }
done
[ -f "$IMG" ] || { echo "not found: $IMG (build the kernel first)" >&2; exit 1; }

rm -rf "$WORK" "$ZIP"
git clone --depth=1 https://github.com/osm0sis/AnyKernel3.git "$WORK"
echo "AnyKernel3 commit: $(git -C "$WORK" rev-parse --short HEAD)"

# keep only what a kernel-only zip needs
rm -rf "$WORK/.git" "$WORK/.github" "$WORK/README.md" \
       "$WORK/ramdisk" "$WORK/patch" "$WORK/modules"

cp "$ROOT/ak3/anykernel.sh" "$WORK/anykernel.sh"
cp "$IMG" "$WORK/Image.gz-dtb"

( cd "$WORK" && zip -r9 "$ZIP" . -x ".git*" >/dev/null )

echo
echo "Built: $ZIP"
ls -la "$ZIP"
sha256sum "$ZIP"
