#!/usr/bin/env bash
# install.sh — instala snk-deploy como skill do Claude Code.
#
# Uso:
#   curl -fsSL https://raw.githubusercontent.com/lbigor/snk-deploy/main/install.sh | bash
#
# Ou local:
#   ./install.sh

set -euo pipefail

REPO_URL="https://github.com/lbigor/snk-deploy.git"
TARGET="${CLAUDE_SKILLS_DIR:-$HOME/.claude/skills}/snk-deploy"

echo "==> snk-deploy installer"
echo "    destino: $TARGET"

mkdir -p "$(dirname "$TARGET")"

if [ -d "$TARGET/.git" ]; then
  echo "==> repo já presente, atualizando via git pull"
  git -C "$TARGET" pull --ff-only
else
  echo "==> clonando $REPO_URL"
  git clone --depth 1 "$REPO_URL" "$TARGET"
fi

echo "==> garantindo que scripts são executáveis"
chmod +x "$TARGET/install.sh" "$TARGET/test.sh" "$TARGET/scripts/"*.sh 2>/dev/null || true

echo "==> verificando pré-requisitos"
if command -v javac >/dev/null 2>&1; then
  echo "    [ok] javac $(javac -version 2>&1 | awk '{print $2}')"
else
  echo "    [FAIL] javac não encontrado no PATH — instale o JDK 8+"
  exit 1
fi

if command -v jar >/dev/null 2>&1; then
  echo "    [ok] jar disponível"
else
  echo "    [FAIL] jar não encontrado no PATH (deveria vir com o JDK)"
  exit 1
fi

echo "==> verificando skills relacionadas (opcionais)"
SKILLS_DIR="$(dirname "$TARGET")"
for dep in snk-slack snk-doctor; do
  if [ -d "$SKILLS_DIR/$dep" ]; then
    echo "    [ok] $dep encontrada"
  else
    echo "    [warn] $dep ausente — snk-deploy funciona, mas sem integração"
  fi
done

echo ""
echo "==> snk-deploy instalado em $TARGET"
echo "    teste com: cd $TARGET && ./test.sh"
echo "    use com: 'Claude, faz o deploy desse projeto' (dentro de um projeto Sankhya)"
