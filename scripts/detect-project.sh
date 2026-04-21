#!/usr/bin/env bash
# detect-project.sh — valida se o cwd (ou dir passado) é projeto Sankhya Java.
#
# Uso:
#   ./detect-project.sh           # valida cwd
#   ./detect-project.sh /path     # valida outro path
#
# Exit 0: é projeto Sankhya válido.
# Exit 1: não é — imprime o que falta.

set -euo pipefail

DIR="${1:-.}"
cd "$DIR"

fail=0

check_file() {
  if [ -f "$1" ]; then
    echo "  [ok]   $1"
  else
    echo "  [FAIL] $1 ausente"
    fail=$((fail+1))
  fi
}

check_dir() {
  if [ -d "$1" ]; then
    echo "  [ok]   $1/"
  else
    echo "  [FAIL] $1/ ausente"
    fail=$((fail+1))
  fi
}

echo "==> detectando projeto Sankhya em $(pwd)"
check_file .classpath
check_dir src

# Validar que .classpath tem entries kind="lib" (JARs da Sankhya).
if [ -f .classpath ]; then
  N_JARS=$(grep -cE 'kind="lib".*\.jar' .classpath 2>/dev/null || echo 0)
  if [ "$N_JARS" -gt 0 ]; then
    echo "  [ok]   .classpath com $N_JARS JARs (kind=\"lib\")"
  else
    echo "  [FAIL] .classpath sem entries kind=\"lib\" — não parece Sankhya"
    fail=$((fail+1))
  fi
fi

# Validar pacote br.com.lbi (padrão do grupo Fabmed/DevStudios).
if [ -d src/br/com/lbi ]; then
  echo "  [ok]   pacote br.com.lbi presente"
else
  echo "  [warn] pacote br.com.lbi ausente — confirmar com usuário"
  # warn não incrementa fail — algum projeto legado pode usar outro pacote.
fi

# Validar que há pelo menos 1 .java.
N_JAVA=$(find src -name "*.java" 2>/dev/null | wc -l | tr -d ' ')
if [ "$N_JAVA" -gt 0 ]; then
  echo "  [ok]   $N_JAVA arquivo(s) .java em src/"
else
  echo "  [FAIL] nenhum .java em src/"
  fail=$((fail+1))
fi

# -----------------------------------------------------------------------------
# Release tracking — verificações novas.
# -----------------------------------------------------------------------------

# Repositório git é obrigatório (release tracking embute commit no manifest).
if git rev-parse --git-dir >/dev/null 2>&1; then
  echo "  [ok]   projeto é repositório git"

  # Remote GitHub é opcional — só necessário se quiser 'gh release create'.
  if git remote get-url origin >/dev/null 2>&1; then
    ORIGIN_URL="$(git remote get-url origin 2>/dev/null || echo "")"
    if echo "$ORIGIN_URL" | grep -q "github.com"; then
      echo "  [ok]   remote origin aponta pra GitHub ($ORIGIN_URL)"
    else
      echo "  [warn] remote origin não é GitHub — 'gh release create' indisponível"
    fi
  else
    echo "  [warn] sem remote 'origin' configurado — 'gh release create' indisponível"
  fi
else
  echo "  [FAIL] projeto não é repositório git — release tracking requer git init"
  fail=$((fail+1))
fi

# gh CLI é informativo (não-fatal) — habilita PR lookup + release.
if command -v gh >/dev/null 2>&1; then
  echo "  [ok]   gh CLI disponível ($(gh --version 2>/dev/null | head -n1))"
else
  echo "  [warn] gh CLI ausente — PR lookup e release pulados silenciosamente"
fi

echo ""
if [ "$fail" -eq 0 ]; then
  echo "[OK] projeto Sankhya válido — pronto pra build.sh"
  exit 0
else
  echo "[FAIL] $fail problema(s) — corrija antes de rodar build.sh"
  exit 1
fi
