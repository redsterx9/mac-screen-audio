#!/bin/bash
# screend 설치: 빌드 → ~/.local/bin 에 복사 → 로그인 자동 실행 등록
set -euo pipefail
cd "$(dirname "$0")"

MIC=""
[[ "${1:-}" == "--mic" ]] && MIC="--mic"

echo "빌드 중..."
swift build -c release

mkdir -p "$HOME/.local/bin"
cp .build/release/screend "$HOME/.local/bin/screend"
echo "설치: $HOME/.local/bin/screend"

"$HOME/.local/bin/screend" install $MIC

case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *) echo; echo "참고: ~/.local/bin 이 PATH 에 없습니다. 추가하려면:"
     echo '  echo '"'"'export PATH="$HOME/.local/bin:$PATH"'"'"' >> ~/.zshrc' ;;
esac
