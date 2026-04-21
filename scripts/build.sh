#!/usr/bin/env bash
# build.sh — compila projeto Sankhya Java e empacota em JAR com timestamp + hash git.
#
# Uso:
#   ./build.sh                      # compila projeto no cwd
#   ./build.sh /caminho/do/projeto  # compila projeto em outro lugar
#   ./build.sh --release            # compila + cria GitHub Release (precisa de gh auth)
#   ./build.sh /path --release      # idem, em outro diretório
#
# Env vars:
#   SNK_DEPLOY_CREATE_RELEASE=1     # equivalente a --release
#   SNK_DEPLOY_SKIP_MANIFEST=1      # não embute META-INF/snk-deploy/manifest.json
#                                   # (retrocompatibilidade com JAR antigo)
#
# Saída:
#   <projeto>/dist/<nome>-YYYYMMDD-HHMMSS-<hash8>.jar
#   com META-INF/snk-deploy/manifest.json embutido (salvo se SKIP_MANIFEST).
#
# Pré-requisitos:
#   - javac e jar no PATH (JDK 8+).
#   - Projeto com .classpath (Eclipse) listando JARs kind="lib".
#   - Código-fonte em src/.
#   - git inicializado (obrigatório pro release tracking).
#   - gh CLI autenticado (opcional, usado pra PR lookup + release).

set -euo pipefail

# Parse argumentos — aceita [dir] [--release] em qualquer ordem.
PROJETO_DIR="."
CREATE_RELEASE="${SNK_DEPLOY_CREATE_RELEASE:-0}"
for arg in "$@"; do
  case "$arg" in
    --release) CREATE_RELEASE=1 ;;
    *) PROJETO_DIR="$arg" ;;
  esac
done

cd "$PROJETO_DIR"

if [ ! -f .classpath ]; then
  echo "[FAIL] .classpath não encontrado em $(pwd)"
  echo "       Este script espera um projeto Sankhya Java (Eclipse)."
  exit 1
fi

if [ ! -d src ]; then
  echo "[FAIL] diretório src/ não encontrado em $(pwd)"
  exit 1
fi

NOME="$(basename "$(pwd)")"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
DIST="dist"
mkdir -p "$DIST" target/classes

# Montar classpath a partir do .classpath (Eclipse) — JARs absolutos.
CLASSPATH=$(grep -oE 'path="[^"]+\.jar"' .classpath 2>/dev/null \
  | sed 's/path="//;s/"$//' \
  | tr '\n' ':' \
  | sed 's/:$//')

if [ -z "$CLASSPATH" ]; then
  echo "[FAIL] .classpath não contém entries JAR (kind=\"lib\")."
  echo "       Verifique se é mesmo projeto Sankhya com deps da IBL."
  exit 1
fi

# Validar que pelo menos 1 JAR do classpath existe em disco (iCloud pode falhar).
FIRST_JAR="$(echo "$CLASSPATH" | cut -d: -f1)"
if [ ! -f "$FIRST_JAR" ]; then
  echo "[FAIL] JAR referenciado no .classpath não existe em disco:"
  echo "       $FIRST_JAR"
  echo "       Cheque o sync do iCloud ou o path absoluto."
  exit 1
fi

echo "==> projeto: $NOME"
echo "==> classpath: $(echo "$CLASSPATH" | tr ':' '\n' | wc -l | tr -d ' ') JARs"

# ----------------------------------------------------------------------------
# Release tracking — coletar metadados git + gerar manifest.json + hash curto.
# ----------------------------------------------------------------------------
SKIP_MANIFEST="${SNK_DEPLOY_SKIP_MANIFEST:-0}"
HASH8=""
BUILT_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

if [ "$SKIP_MANIFEST" = "1" ]; then
  echo "==> SNK_DEPLOY_SKIP_MANIFEST=1 — manifest.json NÃO será embutido"
else
  # Git é obrigatório pro release tracking. Se não houver, aborta com mensagem clara.
  if ! command -v git >/dev/null 2>&1; then
    echo "[FAIL] git não encontrado no PATH — release tracking requer git."
    echo "       Para pular o manifest, exporte SNK_DEPLOY_SKIP_MANIFEST=1."
    exit 1
  fi
  if [ ! -d .git ] && ! git rev-parse --git-dir >/dev/null 2>&1; then
    echo "[FAIL] projeto não é repositório git (release tracking obrigatório)."
    echo "       Rode 'git init' e faça o primeiro commit, ou exporte"
    echo "       SNK_DEPLOY_SKIP_MANIFEST=1 para pular o manifest."
    exit 1
  fi

  BRANCH="$(git branch --show-current 2>/dev/null || echo "")"
  COMMIT="$(git rev-parse HEAD 2>/dev/null || echo "")"
  COMMIT_SHORT="$(git rev-parse --short=8 HEAD 2>/dev/null || echo "")"
  AUTHOR="$(git log -1 --format='%an <%ae>' 2>/dev/null || echo "")"
  COMMITTED_AT="$(git log -1 --format='%aI' 2>/dev/null || echo "")"

  if [ -z "$COMMIT" ]; then
    echo "[FAIL] git inicializado mas sem commits — faça o primeiro commit antes."
    exit 1
  fi

  # Hash curto = primeiros 8 hex do SHA-256(commit + timestamp).
  HASH8="$(printf '%s%s' "$COMMIT" "$TIMESTAMP" | shasum -a 256 | cut -c1-8)"

  # PR lookup via gh (silencioso se gh faltar ou não autenticado).
  PR_JSON="null"
  if command -v gh >/dev/null 2>&1 && [ -n "$BRANCH" ]; then
    PR_RAW="$(gh pr list --search "head:$BRANCH" --json number,url,title --limit 1 2>/dev/null || echo "[]")"
    if [ -n "$PR_RAW" ] && [ "$PR_RAW" != "[]" ] && [ "$PR_RAW" != "null" ]; then
      # Extrai o primeiro elemento do array (objeto único).
      if command -v jq >/dev/null 2>&1; then
        FIRST="$(echo "$PR_RAW" | jq -c '.[0] // null')"
        if [ -n "$FIRST" ] && [ "$FIRST" != "null" ]; then
          PR_JSON="$FIRST"
        fi
      fi
    fi
  fi

  # Escapar strings pra embutir em JSON.
  json_esc() {
    # Escapa \ " e quebras de linha básicas.
    printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' | awk 'BEGIN{ORS=""} {print}'
  }

  MANIFEST_DIR="target/classes/META-INF/snk-deploy"
  mkdir -p "$MANIFEST_DIR"

  # Build JSON — preferir jq se disponível (output consistente).
  if command -v jq >/dev/null 2>&1; then
    jq -n \
      --arg hash "$HASH8" \
      --arg project "$NOME" \
      --arg built_at "$BUILT_AT" \
      --arg branch "$BRANCH" \
      --arg commit "$COMMIT" \
      --arg commit_short "$COMMIT_SHORT" \
      --arg author "$AUTHOR" \
      --arg committed_at "$COMMITTED_AT" \
      --argjson pr "$PR_JSON" \
      '{
        schema_version: 1,
        hash: $hash,
        project: $project,
        built_at: $built_at,
        git: {
          branch: $branch,
          commit: $commit,
          commit_short: $commit_short,
          author: $author,
          committed_at: $committed_at
        },
        pr: $pr,
        tool: "snk-deploy",
        tool_version: "1.0.0"
      }' > "$MANIFEST_DIR/manifest.json"
  else
    # Fallback manual sem jq.
    {
      printf '{\n'
      printf '  "schema_version": 1,\n'
      printf '  "hash": "%s",\n' "$(json_esc "$HASH8")"
      printf '  "project": "%s",\n' "$(json_esc "$NOME")"
      printf '  "built_at": "%s",\n' "$(json_esc "$BUILT_AT")"
      printf '  "git": {\n'
      printf '    "branch": "%s",\n' "$(json_esc "$BRANCH")"
      printf '    "commit": "%s",\n' "$(json_esc "$COMMIT")"
      printf '    "commit_short": "%s",\n' "$(json_esc "$COMMIT_SHORT")"
      printf '    "author": "%s",\n' "$(json_esc "$AUTHOR")"
      printf '    "committed_at": "%s"\n' "$(json_esc "$COMMITTED_AT")"
      printf '  },\n'
      printf '  "pr": %s,\n' "$PR_JSON"
      printf '  "tool": "snk-deploy",\n'
      printf '  "tool_version": "1.0.0"\n'
      printf '}\n'
    } > "$MANIFEST_DIR/manifest.json"
  fi

  echo "==> manifest: $MANIFEST_DIR/manifest.json (hash=$HASH8)"
fi

# ----------------------------------------------------------------------------
# Compilar.
# ----------------------------------------------------------------------------
find src -name "*.java" > target/sources.txt
if [ ! -s target/sources.txt ]; then
  echo "[FAIL] nenhum .java encontrado em src/"
  exit 1
fi

echo "==> compilando $(wc -l < target/sources.txt | tr -d ' ') arquivos"
javac -encoding UTF-8 -cp "$CLASSPATH" -d target/classes @target/sources.txt

# Copiar resources (se houver) — tudo que não é .java em src/.
if [ -d src ]; then
  # shellcheck disable=SC2016
  (cd src && find . -type f ! -name "*.java" -print0 2>/dev/null \
    | xargs -0 -I{} sh -c 'mkdir -p "../target/classes/$(dirname "$1")" && cp "$1" "../target/classes/$1"' _ {} ) \
    || true
fi

# ----------------------------------------------------------------------------
# Empacotar.
# ----------------------------------------------------------------------------
if [ -n "$HASH8" ]; then
  JAR_NAME="${NOME}-${TIMESTAMP}-${HASH8}.jar"
else
  JAR_NAME="${NOME}-${TIMESTAMP}.jar"
fi
jar cf "${DIST}/${JAR_NAME}" -C target/classes .

SIZE="$(du -h "${DIST}/${JAR_NAME}" | cut -f1)"
ABSOLUTE="$(cd "$DIST" && pwd)/${JAR_NAME}"

echo ""
echo "[OK] JAR gerado"
echo "     arquivo:  $ABSOLUTE"
echo "     tamanho:  $SIZE"
if [ -n "$HASH8" ]; then
  echo "     hash:     $HASH8"
fi

# ----------------------------------------------------------------------------
# Opcionalmente criar GitHub Release.
# ----------------------------------------------------------------------------
if [ "$CREATE_RELEASE" = "1" ] && [ -n "$HASH8" ]; then
  if ! command -v gh >/dev/null 2>&1; then
    echo "[warn] --release pedido mas 'gh' não está no PATH — pulando release."
  else
    TAG="v${TIMESTAMP}-${HASH8}"
    MANIFEST_PATH="target/classes/META-INF/snk-deploy/manifest.json"
    if command -v jq >/dev/null 2>&1 && [ -f "$MANIFEST_PATH" ]; then
      NOTES="$(jq -r '"Build \(.hash)\n\nCommit: \(.git.commit)\nBranch: \(.git.branch)\nPR: \(.pr.url // "—")"' "$MANIFEST_PATH")"
    else
      NOTES="Build ${HASH8} — commit ${COMMIT:-unknown}"
    fi

    if gh release create "$TAG" "${DIST}/${JAR_NAME}" \
         --title "$NOME $TIMESTAMP" \
         --notes "$NOTES" \
         --target "$COMMIT" 2>&1; then
      echo "[OK] GitHub Release criado: $TAG"
    else
      echo "[warn] gh release create falhou (auth/permission?) — manifest embutido já rastreia."
    fi
  fi
fi

echo ""
echo "Próximo passo: Administração → Implantação de Customizações no Sankhya W."
echo "Veja docs/passo-a-passo-sankhya-w.md pro detalhe."
