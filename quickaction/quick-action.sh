#!/bin/bash
#
# Finder 우클릭 → Quick Action 진입점
#
#   quick-action.sh convert <파일...>   설정값 그대로 바로 변환
#   quick-action.sh ask     <파일...>   크기·배경을 물어본 뒤 변환
#
# macOS 기본 bash 는 3.2 이므로 그 문법 범위 안에서 작성한다.

SUPPORT="$HOME/Library/Application Support/svg2png"
BIN="$SUPPORT/bin/svg2png"

# ── 기본 설정. config.sh 에서 덮어쓸 수 있다 ──────────────────────────
SCALE=2                 # 원본 대비 배율
BACKGROUND=transparent  # transparent | white | #RRGGBB …
OVERWRITE=ask           # ask | always | never
NOTIFY=1                # 완료 알림 표시
REVEAL=0                # 변환 후 Finder 에서 결과 파일 선택
[ -f "$SUPPORT/config.sh" ] && . "$SUPPORT/config.sh"

osa() { /usr/bin/osascript "$@" 2>/dev/null; }

# 백그라운드에서 실행되는 osascript 는 스스로 앞으로 나오지 못해, 대화상자가 다른 창
# 뒤에 뜬 것처럼 보인다. System Events 를 activate 해서 앞으로 끌어낸다.
# 다만 그러려면 '자동화' 권한이 필요하므로, 권한이 없어 실패하면 감싸지 않은 형태로
# 되돌린다. 이때도 대화상자는 뜨고 다만 포커스만 오지 않는다.
show_dialog() {          # $1=준비 코드  $2=대화상자 코드  $3=마무리 코드  나머지=인자
  local pre="$1" body="$2" post="$3"; shift 3
  local out
  if out=$(osa -e "$pre
tell application \"System Events\"
	activate
	$body
end tell
$post" "$@" 2>/dev/null); then
    printf '%s' "$out"
    return 0
  fi
  osa -e "$pre
$body
$post" "$@" 2>/dev/null
}

alert() {
  show_dialog 'on run argv' \
    'display alert (item 1 of argv) message (item 2 of argv) as critical' \
    'end run' "$1" "$2" >/dev/null
}

notify() {
  [ "$NOTIFY" = "1" ] || return 0
  osa -e 'on run argv
    display notification (item 2 of argv) with title (item 1 of argv)
  end run' "$1" "$2" >/dev/null
}

MODE="$1"
[ -n "$MODE" ] && shift

if [ ! -x "$BIN" ]; then
  alert "svg2png 를 찾을 수 없습니다" \
        "$BIN 이(가) 없습니다. 프로젝트 폴더에서 ./install.sh 를 다시 실행해 주세요."
  exit 1
fi

# ── 선택된 항목 중 .svg 만 추린다 ────────────────────────────────────
files=()
for f in "$@"; do
  [ -f "$f" ] || continue
  ext=$(printf '%s' "${f##*.}" | tr '[:upper:]' '[:lower:]')
  if [ "$ext" = "svg" ]; then files+=("$f"); fi
done

if [ ${#files[@]} -eq 0 ]; then
  alert "변환할 SVG 가 없습니다" "선택한 항목 중 .svg 파일이 없습니다."
  exit 1
fi

ARGS=()

# ── ask 모드: 크기와 배경을 물어본다 ─────────────────────────────────
if [ "$MODE" = "ask" ]; then
  size=$(show_dialog \
    'set opts to {"1배 (원본 크기)", "2배", "3배", "4배", "가로 512px", "가로 1024px", "가로 2048px", "직접 입력…"}' \
    'set r to choose from list opts with title "SVG → PNG" with prompt "출력 크기를 선택하세요" default items {"2배"}' \
    'if r is false then return "CANCEL"
return item 1 of r')

  case "$size" in
    "1배 (원본 크기)") ARGS+=(-s 1) ;;
    "2배")             ARGS+=(-s 2) ;;
    "3배")             ARGS+=(-s 3) ;;
    "4배")             ARGS+=(-s 4) ;;
    "가로 512px")      ARGS+=(-w 512) ;;
    "가로 1024px")     ARGS+=(-w 1024) ;;
    "가로 2048px")     ARGS+=(-w 2048) ;;
    "직접 입력…")
      custom=$(show_dialog '' \
        'set r to display dialog "가로 크기를 픽셀로 입력하세요" default answer "1024" with title "SVG → PNG" buttons {"취소", "확인"} default button "확인"' \
        'if button returned of r is "취소" then return "CANCEL"
return text returned of r')
      case "$custom" in
        CANCEL|"") exit 0 ;;
        *[!0-9]*|0) alert "숫자를 입력해 주세요" "가로 크기는 1 이상의 정수여야 합니다. (입력: $custom)"; exit 1 ;;
        *) ARGS+=(-w "$custom") ;;
      esac ;;
    *) exit 0 ;;   # 취소
  esac

  bg=$(show_dialog '' \
    'set r to choose from list {"투명", "흰색", "검정"} with title "SVG → PNG" with prompt "배경을 선택하세요" default items {"투명"}' \
    'if r is false then return "CANCEL"
return item 1 of r')
  case "$bg" in
    "흰색") ARGS+=(-b white) ;;
    "검정") ARGS+=(-b black) ;;
    "투명") ;;
    *) exit 0 ;;   # 취소
  esac
else
  ARGS+=(-s "$SCALE")
  if [ "$BACKGROUND" != "transparent" ]; then ARGS+=(-b "$BACKGROUND"); fi
fi

# ── 같은 이름의 PNG 가 이미 있으면 어떻게 할지 정한다 ────────────────
collisions=0
for f in "${files[@]}"; do
  [ -e "${f%.*}.png" ] && collisions=$((collisions + 1))
done

if [ "$collisions" -gt 0 ]; then
  case "$OVERWRITE" in
    always) ARGS+=(-f) ;;
    never)  : ;;
    *)
      ans=$(show_dialog 'on run argv' \
        'set r to display alert "이미 PNG 파일이 있습니다" message ((item 1 of argv) & "개의 PNG 파일이 같은 이름으로 존재합니다. 어떻게 할까요?") buttons {"취소", "새 이름으로 저장", "덮어쓰기"} default button "새 이름으로 저장"' \
        'return button returned of r
end run' "$collisions")
      case "$ans" in
        "덮어쓰기")        ARGS+=(-f) ;;
        "새 이름으로 저장") : ;;
        *) exit 0 ;;
      esac ;;
  esac
fi

# ── 변환 ─────────────────────────────────────────────────────────────
out=$("$BIN" --porcelain "${ARGS[@]}" "${files[@]}" 2>&1)
rc=$?

ok=0; fail=0; failmsg=""; lastline=""
okpaths=()
while IFS=$'\t' read -r st a b c; do
  case "$st" in
    OK)
      ok=$((ok + 1)); okpaths+=("$b")
      lastline="$(basename "$b")  ($c)" ;;
    FAIL)
      fail=$((fail + 1))
      failmsg="$failmsg• $(basename "$a") — $b
" ;;
  esac
done <<< "$out"

# 결과 줄이 하나도 없다면 변환기 자체가 실행되지 못한 것이다
# (예: config.sh 의 값이 잘못돼 인자 검사에서 걸린 경우). 조용히 끝나면 안 된다.
if [ "$ok" -eq 0 ] && [ "$fail" -eq 0 ]; then
  alert "변환하지 못했습니다" "${out:-알 수 없는 오류가 발생했습니다 (종료 코드 $rc)}

설정을 확인해 주세요:
$SUPPORT/config.sh"
  exit 1
fi

if [ "$fail" -gt 0 ]; then
  alert "변환하지 못한 파일이 있습니다 (${fail}개)" "$failmsg"
fi

if [ "$ok" -gt 0 ]; then
  if [ "$ok" -eq 1 ]; then
    notify "PNG 변환 완료" "$lastline"
  else
    notify "PNG 변환 완료" "${ok}개 파일을 변환했습니다."
  fi
  if [ "$REVEAL" = "1" ]; then
    osa -e 'on run argv
      set sel to {}
      repeat with p in argv
        set end of sel to (POSIX file (p as text) as alias)
      end repeat
      tell application "Finder" to select sel
    end run' "${okpaths[@]}" >/dev/null
  fi
fi

[ "$fail" -gt 0 ] && exit 1
exit 0
