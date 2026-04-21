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
for f in docs/passo-a-passo-sankhya-w.md docs/release-tracking.md; do
  if [ -f "$f" ]; then
    say_ok "$f"
  else
    say_fail "$f ausente"
  fi
done

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
echo "==> release tracking — build.sh num repo de teste isolado"

# Criar ambiente isolado com mktemp — NUNCA rodar em projeto real do usuário.
if ! command -v javac >/dev/null 2>&1 || ! command -v jar >/dev/null 2>&1; then
  say_ok "javac/jar ausentes — pulando smoke test de build (esperado em CI mínima)"
else
  TMP="$(mktemp -d)"
  trap 'rm -rf "$TMP"' EXIT

  # Estrutura mínima de projeto Sankhya fake.
  FAKEPROJ="$TMP/snk-deploy-smoke"
  mkdir -p "$FAKEPROJ/src/br/com/lbi/smoke"
  # JAR dummy pra satisfazer a checagem de FIRST_JAR em disco.
  mkdir -p "$FAKEPROJ/lib"
  # Criamos um JAR vazio real (precisa existir em disco).
  (cd "$FAKEPROJ/lib" && printf '' > empty.class && jar cf dummy.jar empty.class && rm -f empty.class) >/dev/null 2>&1

  DUMMY_JAR_PATH="$FAKEPROJ/lib/dummy.jar"
  cat > "$FAKEPROJ/.classpath" <<XML
<?xml version="1.0" encoding="UTF-8"?>
<classpath>
  <classpathentry kind="src" path="src"/>
  <classpathentry kind="lib" path="$DUMMY_JAR_PATH"/>
</classpath>
XML

  cat > "$FAKEPROJ/src/br/com/lbi/smoke/Hello.java" <<'JAVA'
package br.com.lbi.smoke;
public class Hello { public static void main(String[] a){} }
JAVA

  (
    cd "$FAKEPROJ" &&
    git init -q &&
    git config user.email "test@example.com" &&
    git config user.name "Test User" &&
    git add -A &&
    git commit -q -m "initial smoke commit"
  )

  # Rodar build.sh real contra o projeto fake.
  if bash "$ROOT/scripts/build.sh" "$FAKEPROJ" >"$TMP/build.log" 2>&1; then
    say_ok "build.sh rodou no projeto de teste"
  else
    say_fail "build.sh falhou no projeto de teste (ver $TMP/build.log)"
    cat "$TMP/build.log" || true
  fi

  # Encontrar JAR gerado.
  JAR="$(ls "$FAKEPROJ"/dist/*.jar 2>/dev/null | head -n1 || echo "")"
  if [ -n "$JAR" ] && [ -f "$JAR" ]; then
    say_ok "JAR gerado em dist/"

    # Nome do JAR deve ter sufixo -<hash8>.jar (8 hex chars).
    JAR_BASE="$(basename "$JAR")"
    if echo "$JAR_BASE" | grep -qE -- '-[0-9a-f]{8}\.jar$'; then
      say_ok "nome do JAR contém sufixo de hash de 8 hex chars"
    else
      say_fail "nome do JAR sem sufixo de hash válido: $JAR_BASE"
    fi

    # Manifest embutido?
    if unzip -p "$JAR" META-INF/snk-deploy/manifest.json >"$TMP/manifest.json" 2>/dev/null; then
      say_ok "JAR contém META-INF/snk-deploy/manifest.json"

      # Validar JSON.
      if command -v jq >/dev/null 2>&1; then
        if jq -e . "$TMP/manifest.json" >/dev/null 2>&1; then
          say_ok "manifest.json é JSON válido"
        else
          say_fail "manifest.json não é JSON válido"
        fi

        # Campos obrigatórios.
        for field in schema_version hash project built_at git tool; do
          if jq -e ".$field" "$TMP/manifest.json" >/dev/null 2>&1; then
            say_ok "manifest.json tem campo '$field'"
          else
            say_fail "manifest.json sem campo '$field'"
          fi
        done

        # Hash = 8 hex chars.
        HASH="$(jq -r .hash "$TMP/manifest.json")"
        if echo "$HASH" | grep -qE '^[0-9a-f]{8}$'; then
          say_ok "manifest.hash tem 8 hex chars ($HASH)"
        else
          say_fail "manifest.hash não é 8 hex chars: $HASH"
        fi
      else
        say_ok "jq ausente — pulando validação estrutural do JSON"
      fi
    else
      say_fail "JAR não contém META-INF/snk-deploy/manifest.json"
    fi
  else
    say_fail "nenhum JAR encontrado em dist/"
  fi

  # Teste retrocompatibilidade: SNK_DEPLOY_SKIP_MANIFEST=1 remove manifest.
  rm -rf "$FAKEPROJ/dist" "$FAKEPROJ/target"
  if SNK_DEPLOY_SKIP_MANIFEST=1 bash "$ROOT/scripts/build.sh" "$FAKEPROJ" >"$TMP/build2.log" 2>&1; then
    JAR2="$(ls "$FAKEPROJ"/dist/*.jar 2>/dev/null | head -n1 || echo "")"
    if [ -n "$JAR2" ] && [ -f "$JAR2" ]; then
      if unzip -p "$JAR2" META-INF/snk-deploy/manifest.json >/dev/null 2>&1; then
        say_fail "SNK_DEPLOY_SKIP_MANIFEST=1 mas manifest ainda embutido"
      else
        say_ok "SNK_DEPLOY_SKIP_MANIFEST=1 omite manifest (retrocompatível)"
      fi
    else
      say_fail "build com SKIP_MANIFEST não gerou JAR"
    fi
  else
    say_fail "build com SKIP_MANIFEST falhou"
    cat "$TMP/build2.log" || true
  fi
fi

echo ""
echo "==> resumo: $ok ok, $fail fail"

if [ "$fail" -gt 0 ]; then
  exit 1
fi
