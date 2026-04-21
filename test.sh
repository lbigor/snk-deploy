#!/usr/bin/env bash
# test.sh — valida integridade da skill.
#
# Checa:
#   1. Arquivos obrigatórios presentes (README, SKILL, LICENSE etc.).
#   2. Scripts em scripts/ são executáveis e têm shebang bash.
#   3. SKILL.md tem frontmatter YAML com name/description/type.
#   4. build.sh e detect-project.sh passam sintaxe (bash -n).
#
# Saída: exit 0 se tudo ok, exit 1 se algo falhar.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

fail=0
ok=0

say_ok()   { printf "  [ok]   %s\n" "$1"; ok=$((ok+1)); }
say_fail() { printf "  [FAIL] %s\n" "$1"; fail=$((fail+1)); }

echo "==> arquivos top-level obrigatórios"
for f in README.md SKILL.md LICENSE INSTALACAO.md BOAS_PRATICAS.md CONTRIBUTING.md \
         install.sh test.sh .markdownlint.json; do
  if [ -f "$f" ]; then
    say_ok "$f"
  else
    say_fail "$f ausente"
  fi
done

echo ""
echo "==> scripts em scripts/"
for s in scripts/build.sh scripts/detect-project.sh; do
  if [ ! -f "$s" ]; then
    say_fail "$s ausente"
    continue
  fi
  if head -n1 "$s" | grep -qE '^#!/usr/bin/env bash|^#!/bin/bash'; then
    say_ok "$s tem shebang bash"
  else
    say_fail "$s sem shebang bash"
  fi
  if bash -n "$s" 2>/dev/null; then
    say_ok "$s passa sintaxe bash"
  else
    say_fail "$s falha sintaxe bash"
  fi
done

echo ""
echo "==> docs/"
if [ -f docs/passo-a-passo-sankhya-w.md ]; then
  say_ok "docs/passo-a-passo-sankhya-w.md"
else
  say_fail "docs/passo-a-passo-sankhya-w.md ausente"
fi

echo ""
echo "==> SKILL.md frontmatter"
if head -n1 SKILL.md | grep -qE '^---$'; then
  say_ok "SKILL.md abre com ---"
  for field in name description type; do
    if grep -qE "^${field}:" SKILL.md; then
      say_ok "SKILL.md tem campo '$field'"
    else
      say_fail "SKILL.md sem campo '$field'"
    fi
  done
else
  say_fail "SKILL.md sem frontmatter"
fi

echo ""
echo "==> .github/"
for f in .github/CODEOWNERS .github/pull_request_template.md; do
  if [ -f "$f" ]; then
    say_ok "$f"
  else
    say_fail "$f ausente"
  fi
done

# CI workflow pode estar instalado em workflows/ ou pendente em workflows-template/
# (quando o token GH usado na criação do repo não tem escopo "workflow").
if [ -f .github/workflows/ci.yml ]; then
  say_ok ".github/workflows/ci.yml (CI instalado)"
elif [ -f .github/workflows-template/ci.yml ]; then
  say_ok ".github/workflows-template/ci.yml (template pendente de instalação)"
else
  say_fail "ci.yml ausente (nem em workflows/ nem em workflows-template/)"
fi

echo ""
echo "==> resumo: $ok ok, $fail fail"

if [ "$fail" -gt 0 ]; then
  exit 1
fi
