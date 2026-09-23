#!/bin/bash
#
# svg2png 설치 — 변환기를 빌드하고 Finder 우클릭 메뉴에 등록한다.
#
set -euo pipefail
cd "$(dirname "$0")"

SUPPORT="$HOME/Library/Application Support/svg2png"
SERVICES="$HOME/Library/Services"
CLI_LINK="/usr/local/bin/svg2png"

step() { printf '\033[1;34m▸\033[0m %s\n' "$1"; }
ok()   { printf '  \033[32m✓\033[0m %s\n' "$1"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$1"; }

# ── 1. 빌드 ──────────────────────────────────────────────────────────
step "변환기 빌드"
if ! command -v swiftc >/dev/null 2>&1; then
  echo "  swiftc 를 찾을 수 없습니다. Xcode Command Line Tools 가 필요합니다:" >&2
  echo "      xcode-select --install" >&2
  exit 1
fi
mkdir -p "$SUPPORT/bin"
TMPBIN="$(mktemp -t svg2png-build)"
# 빌드가 실패해도 기존에 설치된 실행 파일이 망가지지 않도록 임시 파일에 먼저 만든다.
swiftc -O src/svg2png.swift -o "$TMPBIN"
mv -f "$TMPBIN" "$SUPPORT/bin/svg2png"
chmod +x "$SUPPORT/bin/svg2png"
ok "$SUPPORT/bin/svg2png ($("$SUPPORT/bin/svg2png" --version))"

# ── 2. Quick Action 스크립트와 설정 ──────────────────────────────────
step "스크립트·설정 설치"
cp quickaction/quick-action.sh "$SUPPORT/quick-action.sh"
chmod +x "$SUPPORT/quick-action.sh"
ok "$SUPPORT/quick-action.sh"

if [ -f "$SUPPORT/config.sh" ]; then
  ok "config.sh 는 이미 있어 그대로 둡니다"
else
  cat > "$SUPPORT/config.sh" <<'CONF'
# svg2png 설정 — 값을 고친 뒤 저장하면 바로 반영됩니다. (재설치 시에도 유지됩니다)

SCALE=2                 # "PNG로 변환" 의 기본 배율. 1 = 원본 크기, 2 = 2배 …
BACKGROUND=transparent  # transparent | white | black | #RRGGBB | #RRGGBBAA
OVERWRITE=ask           # ask = 물어봄 · always = 항상 덮어씀 · never = 항상 새 이름
NOTIFY=1                # 1 = 완료 알림 표시 · 0 = 조용히
REVEAL=0                # 1 = 변환 후 Finder 에서 결과 파일 선택
CONF
  ok "$SUPPORT/config.sh (기본값 생성)"
fi

# ── 3. Quick Action 번들 생성 ────────────────────────────────────────
make_workflow() {
  local bundle="$1" title="$2" mode="$3"
  local dir="$SERVICES/$bundle.workflow/Contents"
  rm -rf "$SERVICES/$bundle.workflow"
  mkdir -p "$dir"

  cat > "$dir/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>NSServices</key>
	<array>
		<dict>
			<key>NSMenuItem</key>
			<dict>
				<key>default</key>
				<string>$title</string>
			</dict>
			<key>NSMessage</key>
			<string>runWorkflowAsService</string>
			<key>NSSendFileTypes</key>
			<array>
				<string>public.svg-image</string>
			</array>
		</dict>
	</array>
</dict>
</plist>
PLIST

  # 셸에서 확장되면 안 되는 \$HOME · \$@ 는 그대로 남겨 실행 시점에 풀리게 한다.
  local u1 u2 u3
  u1="$(uuidgen)"; u2="$(uuidgen)"; u3="$(uuidgen)"
  cat > "$dir/document.wflow" <<WFLOW
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>AMApplicationBuild</key>
	<string>528</string>
	<key>AMApplicationVersion</key>
	<string>2.10</string>
	<key>AMDocumentVersion</key>
	<string>2</string>
	<key>actions</key>
	<array>
		<dict>
			<key>action</key>
			<dict>
				<key>AMAccepts</key>
				<dict>
					<key>Container</key>
					<string>List</string>
					<key>Optional</key>
					<true/>
					<key>Types</key>
					<array>
						<string>com.apple.cocoa.string</string>
					</array>
				</dict>
				<key>AMActionVersion</key>
				<string>2.0.3</string>
				<key>AMApplication</key>
				<array>
					<string>Automator</string>
				</array>
				<key>AMParameterProperties</key>
				<dict>
					<key>COMMAND_STRING</key>
					<dict/>
					<key>CheckedForUserDefaultShell</key>
					<dict/>
					<key>inputMethod</key>
					<dict/>
					<key>shell</key>
					<dict/>
					<key>source</key>
					<dict/>
				</dict>
				<key>AMProvides</key>
				<dict>
					<key>Container</key>
					<string>List</string>
					<key>Types</key>
					<array>
						<string>com.apple.cocoa.string</string>
					</array>
				</dict>
				<key>ActionBundlePath</key>
				<string>/System/Library/Automator/Run Shell Script.action</string>
				<key>ActionName</key>
				<string>Run Shell Script</string>
				<key>ActionParameters</key>
				<dict>
					<key>COMMAND_STRING</key>
					<string>"\$HOME/Library/Application Support/svg2png/quick-action.sh" $mode "\$@"</string>
					<key>CheckedForUserDefaultShell</key>
					<true/>
					<key>inputMethod</key>
					<integer>1</integer>
					<key>shell</key>
					<string>/bin/bash</string>
					<key>source</key>
					<string></string>
				</dict>
				<key>BundleIdentifier</key>
				<string>com.apple.Automator.RunShellScript</string>
				<key>CFBundleVersion</key>
				<string>2.0.3</string>
				<key>CanShowSelectedItemsWhenRun</key>
				<false/>
				<key>CanShowWhenRun</key>
				<true/>
				<key>Category</key>
				<array>
					<string>AMCategoryUtilities</string>
				</array>
				<key>Class Name</key>
				<string>RunShellScriptAction</string>
				<key>InputUUID</key>
				<string>$u1</string>
				<key>Keywords</key>
				<array>
					<string>Shell</string>
					<string>Script</string>
					<string>Command</string>
					<string>Run</string>
					<string>Unix</string>
				</array>
				<key>OutputUUID</key>
				<string>$u2</string>
				<key>UUID</key>
				<string>$u3</string>
				<key>UnlocalizedApplications</key>
				<array>
					<string>Automator</string>
				</array>
				<key>arguments</key>
				<dict>
					<key>0</key>
					<dict>
						<key>default value</key>
						<integer>0</integer>
						<key>name</key>
						<string>inputMethod</string>
						<key>required</key>
						<string>0</string>
						<key>type</key>
						<string>0</string>
						<key>uuid</key>
						<string>0</string>
					</dict>
					<key>1</key>
					<dict>
						<key>default value</key>
						<false/>
						<key>name</key>
						<string>CheckedForUserDefaultShell</string>
						<key>required</key>
						<string>0</string>
						<key>type</key>
						<string>0</string>
						<key>uuid</key>
						<string>1</string>
					</dict>
					<key>2</key>
					<dict>
						<key>default value</key>
						<string></string>
						<key>name</key>
						<string>source</string>
						<key>required</key>
						<string>0</string>
						<key>type</key>
						<string>0</string>
						<key>uuid</key>
						<string>2</string>
					</dict>
					<key>3</key>
					<dict>
						<key>default value</key>
						<string></string>
						<key>name</key>
						<string>COMMAND_STRING</string>
						<key>required</key>
						<string>0</string>
						<key>type</key>
						<string>0</string>
						<key>uuid</key>
						<string>3</string>
					</dict>
					<key>4</key>
					<dict>
						<key>default value</key>
						<string>/bin/sh</string>
						<key>name</key>
						<string>shell</string>
						<key>required</key>
						<string>0</string>
						<key>type</key>
						<string>0</string>
						<key>uuid</key>
						<string>4</string>
					</dict>
				</dict>
				<key>isViewVisible</key>
				<integer>1</integer>
				<key>location</key>
				<string>309.000000:253.000000</string>
				<key>nibPath</key>
				<string>/System/Library/Automator/Run Shell Script.action/Contents/Resources/Base.lproj/main.nib</string>
			</dict>
			<key>isViewVisible</key>
			<integer>1</integer>
		</dict>
	</array>
	<key>connectors</key>
	<dict/>
	<key>workflowMetaData</key>
	<dict>
		<key>applicationBundleIDsByPath</key>
		<dict/>
		<key>applicationPaths</key>
		<array/>
		<key>inputTypeIdentifier</key>
		<string>com.apple.Automator.fileSystemObject</string>
		<key>outputTypeIdentifier</key>
		<string>com.apple.Automator.nothing</string>
		<key>presentationMode</key>
		<integer>11</integer>
		<key>processesInput</key>
		<integer>0</integer>
		<key>serviceApplicationBundleID</key>
		<string></string>
		<key>serviceApplicationPath</key>
		<string></string>
		<key>serviceInputTypeIdentifier</key>
		<string>com.apple.Automator.fileSystemObject</string>
		<key>serviceOutputTypeIdentifier</key>
		<string>com.apple.Automator.nothing</string>
		<key>serviceProcessesInput</key>
		<integer>0</integer>
		<key>systemImageName</key>
		<string>NSActionTemplate</string>
		<key>useAutomaticInputType</key>
		<integer>0</integer>
		<key>workflowTypeIdentifier</key>
		<string>com.apple.Automator.servicesMenu</string>
	</dict>
</dict>
</plist>
WFLOW

  plutil -lint "$dir/Info.plist" >/dev/null
  plutil -lint "$dir/document.wflow" >/dev/null
  ok "$title"
}

step "Finder 우클릭 메뉴 등록"
mkdir -p "$SERVICES"
make_workflow "SVG를 PNG로 변환"         "PNG로 변환"      convert
make_workflow "SVG를 PNG로 변환 (옵션)"  "PNG로 변환…"     ask

# ── 4. 명령줄에서도 쓸 수 있게 ───────────────────────────────────────
step "명령줄 도구 연결"
if [ -d "$(dirname "$CLI_LINK")" ] && [ -w "$(dirname "$CLI_LINK")" ]; then
  ln -sf "$SUPPORT/bin/svg2png" "$CLI_LINK"
  ok "$CLI_LINK"
else
  warn "$(dirname "$CLI_LINK") 에 쓸 수 없어 건너뜁니다."
  warn "터미널에서 쓰려면:  sudo ln -sf \"$SUPPORT/bin/svg2png\" $CLI_LINK"
fi

# ── 5. Services 목록 갱신 ────────────────────────────────────────────
step "메뉴 갱신"
if [ -x /System/Library/CoreServices/pbs ]; then
  /System/Library/CoreServices/pbs -flush >/dev/null 2>&1 || true
fi
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
  -f "$SERVICES/SVG를 PNG로 변환.workflow" "$SERVICES/SVG를 PNG로 변환 (옵션).workflow" >/dev/null 2>&1 || true
ok "완료"

cat <<'DONE'

설치가 끝났습니다.

  Finder 에서 .svg 파일을 우클릭하면 아래 항목이 보입니다
  (빠른 동작 / Quick Actions 하위에 있을 수 있습니다):

      PNG로 변환      설정값 그대로 바로 변환
      PNG로 변환…     크기와 배경을 고르고 변환

  기본값은 원본의 2배 크기, 투명 배경입니다.
  바꾸려면:  ~/Library/Application Support/svg2png/config.sh

  메뉴가 보이지 않으면 Finder 를 다시 시작하세요:  killall Finder

DONE
