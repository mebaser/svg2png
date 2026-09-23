#!/bin/bash
#
# svg2png 제거 — 설치된 모든 항목을 지운다. 변환해 둔 PNG 파일은 건드리지 않는다.
#
set -euo pipefail

SUPPORT="$HOME/Library/Application Support/svg2png"
SERVICES="$HOME/Library/Services"
CLI_LINK="/usr/local/bin/svg2png"

TARGETS=(
  "$SERVICES/SVG를 PNG로 변환.workflow"
  "$SERVICES/SVG를 PNG로 변환 (옵션).workflow"
  "$SUPPORT"
)

echo "다음 항목을 지웁니다:"
found=0
for t in "${TARGETS[@]}"; do
  if [ -e "$t" ]; then echo "  - $t"; found=1; fi
done
if [ -L "$CLI_LINK" ] && [ "$(readlink "$CLI_LINK")" = "$SUPPORT/bin/svg2png" ]; then
  echo "  - $CLI_LINK"; found=1
fi

if [ "$found" -eq 0 ]; then
  echo "  (설치된 항목이 없습니다)"
  exit 0
fi

echo
printf "계속할까요? [y/N] "
read -r answer
case "$answer" in
  y|Y|yes|YES) ;;
  *) echo "취소했습니다."; exit 0 ;;
esac

for t in "${TARGETS[@]}"; do
  if [ -e "$t" ]; then rm -rf "$t"; echo "지움: $t"; fi
done
if [ -L "$CLI_LINK" ] && [ "$(readlink "$CLI_LINK")" = "$SUPPORT/bin/svg2png" ]; then
  rm -f "$CLI_LINK" && echo "지움: $CLI_LINK"
fi

[ -x /System/Library/CoreServices/pbs ] && /System/Library/CoreServices/pbs -flush >/dev/null 2>&1 || true
echo
echo "제거했습니다. 우클릭 메뉴에서 사라지지 않으면:  killall Finder"
