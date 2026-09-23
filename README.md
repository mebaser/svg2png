# svg2png

Finder 에서 SVG 파일을 우클릭해 바로 PNG 로 바꾸는 macOS 도구입니다.

렌더링은 WebKit(Safari 와 같은 엔진)이 담당하므로 그라디언트·필터·마스크·내부 CSS·
웹폰트·외부 이미지 참조까지 브라우저에서 보이는 그대로 나옵니다.
Homebrew·Python·Node 같은 외부 의존성이 전혀 없습니다.

## 설치

```
./install.sh
```

Xcode Command Line Tools 만 있으면 됩니다 (없으면 `xcode-select --install`).

## 사용법

Finder 에서 `.svg` 파일을 우클릭하면 (파일이 여러 개여도 됩니다):

| 메뉴 | 동작 |
|---|---|
| **PNG로 변환** | 설정값 그대로 즉시 변환 |
| **PNG로 변환…** | 크기와 배경을 고른 뒤 변환 |

- 결과 PNG 는 원본 SVG 와 같은 폴더에 같은 이름으로 저장됩니다.
- 기본값은 **원본의 2배 크기, 투명 배경** 입니다.
- 같은 이름의 PNG 가 이미 있으면 덮어쓸지 새 이름(`이름-1.png`)으로 저장할지 물어봅니다.
- SVG 가 아닌 파일에서는 메뉴가 나타나지 않습니다.

메뉴가 보이지 않으면 `killall Finder` 로 Finder 를 다시 시작하세요.
`시스템 설정 → 키보드 → 단축키 → 서비스` 에서 체크 상태와 단축키를 확인할 수 있습니다.

## 설정

`~/Library/Application Support/svg2png/config.sh` 를 고치면 바로 반영됩니다.
재설치해도 이 파일은 그대로 유지됩니다.

```sh
SCALE=2                 # "PNG로 변환" 의 기본 배율. 1 = 원본 크기
BACKGROUND=transparent  # transparent | white | black | #RRGGBB | #RRGGBBAA
OVERWRITE=ask           # ask = 물어봄 · always = 항상 덮어씀 · never = 항상 새 이름
NOTIFY=1                # 1 = 완료 알림 표시 · 0 = 조용히
REVEAL=0                # 1 = 변환 후 Finder 에서 결과 파일 선택
```

## 명령줄에서 쓰기

설치할 때 `/usr/local/bin/svg2png` 로 연결됩니다. 권한이 없어 건너뛰었다면:

```
sudo ln -sf "$HOME/Library/Application Support/svg2png/bin/svg2png" /usr/local/bin/svg2png
```

```
svg2png logo.svg                 # logo.png 를 2배 크기로
svg2png -s 1 logo.svg            # 원본 크기 그대로
svg2png -w 1024 icon.svg         # 가로 1024px (세로는 비율 유지)
svg2png -m 512 icon.svg          # 긴 변을 512px 에 맞춤
svg2png -b white -f *.svg        # 흰 배경, 덮어쓰며 일괄 변환
svg2png -o ~/Desktop/out *.svg   # 다른 폴더로 내보내기
```

`svg2png --help` 로 전체 옵션을 볼 수 있습니다.

## 크기는 어떻게 정해지나

SVG 에 크기가 어떻게 적혀 있든 합리적인 원본 크기를 찾아냅니다.

1. `width`/`height` 속성 — `px` 뿐 아니라 `pt`·`mm`·`cm`·`in` 단위도 환산합니다
2. 값이 `100%` 처럼 뷰포트에 의존하면 무시하고 `viewBox` 크기를 씁니다
3. 둘 다 없으면 실제로 그려진 내용의 경계 상자를 씁니다
4. 그래도 알 수 없으면 512×512

여기에 배율이나 지정한 픽셀 크기를 적용합니다. 가로세로 비율은 항상 유지되며,
출력은 한 변이 20000px 을 넘지 않도록 제한됩니다.
원본과 물리적 크기가 같도록 PNG 의 DPI 도 함께 기록합니다 (2배 → 144dpi).

## 구성

```
src/svg2png.swift          WebKit 으로 렌더링하는 변환기 본체
quickaction/quick-action.sh  우클릭 메뉴가 호출하는 스크립트
install.sh / uninstall.sh    설치·제거
```

설치되는 위치:

```
~/Library/Application Support/svg2png/bin/svg2png
~/Library/Application Support/svg2png/quick-action.sh
~/Library/Application Support/svg2png/config.sh
~/Library/Services/SVG를 PNG로 변환.workflow
~/Library/Services/SVG를 PNG로 변환 (옵션).workflow
/usr/local/bin/svg2png                        (심볼릭 링크)
```

## 문제 해결

변환이 실패하면 터미널에서 직접 실행해 원인을 볼 수 있습니다.

```
SVG2PNG_DEBUG=1 "$HOME/Library/Application Support/svg2png/bin/svg2png" 파일.svg
```

Desktop·Documents·Downloads 안의 파일을 처음 변환할 때 macOS 가 폴더 접근 권한을
물어볼 수 있습니다. 허용해야 PNG 를 만들 수 있습니다.

## 제거

```
./uninstall.sh
```

변환해 둔 PNG 파일은 지우지 않습니다.
