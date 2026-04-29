#!/usr/bin/env bash
# build.sh — compila projeto Sankhya Java e empacota em JAR com timestamp + hash git.
#
# Uso:
#   ./build.sh                      # compila projeto no cwd (env=prod default)
#   ./build.sh /caminho/do/projeto  # compila projeto em outro lugar
#   ./build.sh --env homol          # marca JAR como build de homologação (logs full)
#   ./build.sh --env prod           # marca como produção (default — só erro vai pro Slack)
#   ./build.sh --release            # compila + cria GitHub Release (precisa de gh auth)
#   ./build.sh /path --env prod --release  # combinável em qualquer ordem
#
# Env vars:
#   SNK_DEPLOY_ENV=prod|homol       # equivalente a --env (default: prod)
#   SNK_DEPLOY_CREATE_RELEASE=1     # equivalente a --release
#   SNK_DEPLOY_SKIP_MANIFEST=1      # não embute META-INF/snk-deploy/manifest.json
#                                   # (retrocompatibilidade com JAR antigo)
#   SNK_DEPLOY_OUTPUT_DIR=<dir>     # diretório customizado pra salvar o JAR.
#                                   # Default: ~/Documents/deploy/<projeto>
#                                   # Use "." pra voltar ao comportamento antigo
#                                   # (<projeto>/dist).
#
# Modo de log Slack (REGRA OBRIGATÓRIA):
#   O env do build é embutido em manifest.json como campo `env`. A lib
#   br.com.lbi.slack.SlackLogger lê via DeployManifest.getEnv() e ajusta o flush:
#     - env=homol: envia tudo (INICIO/INFO/SUCCESS/FIM/FATAL).
#     - env=prod (default): só envia se buffer contém ao menos 1 entry de severity ERROR.
#   Decisão é do operador no momento do deploy, não em runtime via pref Sankhya.
#
# Saída:
#   ~/Documents/deploy/<projeto>/<nome>-YYYYMMDD-HHMMSS-<hash8>.jar  (default)
#   com META-INF/snk-deploy/manifest.json embutido (salvo se SKIP_MANIFEST).
#
# Pré-requisitos:
#   - javac e jar no PATH (JDK 8+).
#   - Projeto com .classpath (Eclipse) listando JARs kind="lib".
#   - Código-fonte em src/.
#   - git inicializado (obrigatório pro release tracking).
#   - gh CLI autenticado (opcional, usado pra PR lookup + release).

set -euo pipefail

# Parse argumentos — aceita [dir] [--release] [--env prod|homol] em qualquer ordem.
PROJETO_DIR="."
CREATE_RELEASE="${SNK_DEPLOY_CREATE_RELEASE:-0}"
DEPLOY_ENV="${SNK_DEPLOY_ENV:-prod}"
EXPECT_ENV_VALUE=0
for arg in "$@"; do
  if [ "$EXPECT_ENV_VALUE" = "1" ]; then
    DEPLOY_ENV="$arg"
    EXPECT_ENV_VALUE=0
    continue
  fi
  case "$arg" in
    --release) CREATE_RELEASE=1 ;;
    --env) EXPECT_ENV_VALUE=1 ;;
    *) PROJETO_DIR="$arg" ;;
  esac
done

# Normaliza + valida env.
DEPLOY_ENV="$(echo "$DEPLOY_ENV" | tr '[:upper:]' '[:lower:]')"
case "$DEPLOY_ENV" in
  prod|homol) ;;
  *) echo "[FAIL] --env deve ser 'prod' ou 'homol' (recebido: $DEPLOY_ENV)"; exit 1 ;;
esac

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
# Diretório de saída: default ~/Documents/deploy/<projeto>; SNK_DEPLOY_OUTPUT_DIR=. volta pra <projeto>/dist.
if [ "${SNK_DEPLOY_OUTPUT_DIR:-}" = "." ]; then
  DIST="dist"
elif [ -n "${SNK_DEPLOY_OUTPUT_DIR:-}" ]; then
  DIST="$(eval echo "$SNK_DEPLOY_OUTPUT_DIR")/$NOME"
else
  DIST="$HOME/Documents/deploy/$NOME"
fi
mkdir -p "$DIST" target/classes

# Montar classpath a partir do .classpath (Eclipse).
# Cada JAR: tenta o path original; se não existir, busca o mesmo basename em
# diretórios fallback (SANKHYA_LIBS, iCloud/Jar, ~/Documents/Sankhya-libs, etc).
raw_paths=$(grep -oEi 'path="[^"]+\.jar"' .classpath 2>/dev/null \
  | sed 's/path="//;s/"$//')

if [ -z "$raw_paths" ]; then
  echo "[FAIL] .classpath não contém entries JAR (kind=\"lib\")."
  echo "       Verifique se é mesmo projeto Sankhya com deps da IBL."
  exit 1
fi

# Diretórios de busca — SEM hardcoded. Fontes em ordem de prioridade:
#   1. Env var $SANKHYA_LIBS (uma ou múltiplos dirs separados por ':')
#   2. Arquivo .snk-deploy.paths na raiz do projeto (1 dir por linha, # comenta)
# Se nada for configurado e o JAR não estiver no path literal, aborta com
# mensagem clara pedindo pra criar o arquivo ou exportar a env.
FALLBACK_DIRS=()

if [ -n "${SANKHYA_LIBS:-}" ]; then
  # Aceita múltiplos dirs separados por ':'
  while IFS= read -r d; do
    [ -n "$d" ] && FALLBACK_DIRS+=("$d")
  done < <(echo "$SANKHYA_LIBS" | tr ':' '\n')
fi

if [ -f .snk-deploy.paths ]; then
  while IFS= read -r line; do
    # Ignora comentários e linhas vazias
    line="${line%%#*}"
    line="$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    [ -z "$line" ] && continue
    # Expande ~ e variáveis ambiente
    expanded="$(eval echo "$line")"
    FALLBACK_DIRS+=("$expanded")
  done < .snk-deploy.paths
fi

resolve_jar() {
  local original="$1"
  # 1. Se o path literal existe, usa direto.
  [ -f "$original" ] && { printf '%s' "$original"; return 0; }
  # 2. Busca por basename nos fallbacks.
  local base
  base="$(basename "$original")"
  local dir
  for dir in "${FALLBACK_DIRS[@]+"${FALLBACK_DIRS[@]}"}"; do
    if [ -f "$dir/$base" ]; then
      printf '%s' "$dir/$base"
      return 0
    fi
  done
  # 3. Placeholder iCloud (arquivo escondido .<nome>.icloud)?
  for dir in "${FALLBACK_DIRS[@]+"${FALLBACK_DIRS[@]}"}"; do
    if [ -f "$dir/.${base}.icloud" ]; then
      # Força download via brctl (assíncrono; espera até 30s).
      brctl download "$dir/$base" 2>/dev/null || true
      local waited=0
      while [ ! -f "$dir/$base" ] && [ "$waited" -lt 30 ]; do
        sleep 1
        waited=$((waited+1))
      done
      if [ -f "$dir/$base" ]; then
        echo "    ⏬ iCloud baixou $base ($(stat -f%z "$dir/$base") bytes)" >&2
        printf '%s' "$dir/$base"
        return 0
      fi
    fi
  done
  return 1
}

RESOLVED=()
MISSING=()
while IFS= read -r original; do
  [ -z "$original" ] && continue
  if jar_path=$(resolve_jar "$original"); then
    RESOLVED+=("$jar_path")
  else
    MISSING+=("$(basename "$original")")
  fi
done <<< "$raw_paths"

if [ ${#MISSING[@]} -gt 0 ]; then
  echo "[FAIL] JARs não encontrados em nenhum dir conhecido:"
  for m in "${MISSING[@]}"; do echo "         - $m"; done
  echo ""
  echo "       Dirs pesquisados (em ordem):"
  for d in "${FALLBACK_DIRS[@]+"${FALLBACK_DIRS[@]}"}"; do echo "         - $d"; done
  echo ""
  echo "       Defina SANKHYA_LIBS=<caminho> ou copie os JARs pra ~/Documents/Sankhya-libs/"
  exit 1
fi

# Junta com ':' em uma string classpath.
CLASSPATH="$(IFS=:; echo "${RESOLVED[*]}")"
echo "==> classpath resolvido: ${#RESOLVED[@]} JARs"

# Resolver dependências de projeto Eclipse (kind="src") — adiciona output do projeto irmão.
# Tenta IntelliJ (out/production/<proj>) primeiro, depois Eclipse (bin/), depois target/classes.
PROJ_PARENT="$(dirname "$(pwd)")"
while IFS= read -r sp; do
  [ -z "$sp" ] && continue
  sp="${sp#/}"  # workspace-relative: remove barra inicial
  proj_root="$PROJ_PARENT/$sp"
  resolved=""
  for cand in "$proj_root/out/production/$sp" "$proj_root/target/classes" "$proj_root/bin"; do
    if [ -d "$cand" ]; then
      # Confirma que tem .class real (não 0-byte stub).
      first_class=$(find "$cand" -name "*.class" -not -empty 2>/dev/null | head -1)
      if [ -n "$first_class" ]; then
        resolved="$cand"
        break
      fi
    fi
  done
  if [ -n "$resolved" ]; then
    CLASSPATH="$CLASSPATH:$resolved"
    echo "    [src-ref] $sp → ${resolved#$PROJ_PARENT/}"
  else
    echo "    [src-ref] aviso: nenhum output válido (out/production, target/classes, bin) em $sp — ignorado"
  fi
done < <(grep -oE 'kind="src"[^>]*/>' .classpath \
  | grep -v 'path="src"' \
  | grep -oE 'path="[^"]+"' \
  | sed 's/path="//;s/"$//')

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
  # Se o projeto não é repo git, auto-init + commit inicial (opt-out via env).
  if [ ! -d .git ] && ! git rev-parse --git-dir >/dev/null 2>&1; then
    if [ "${SNK_DEPLOY_NO_AUTO_INIT:-0}" = "1" ]; then
      echo "[FAIL] projeto não é repositório git e SNK_DEPLOY_NO_AUTO_INIT=1."
      echo "       Rode 'git init' + commit manual, ou remova a env var."
      exit 1
    fi

    echo "==> projeto não é repo git — inicializando automaticamente"

    # ---- SECURITY GATE: escaneia secrets antes de QUALQUER commit ----
    # Aborta se detectar webhook Slack, PAT GitHub, chave OpenAI, bot token
    # Slack, ou qualquer padrão óbvio de secret embutido no código.
    SECRET_PATTERNS='hooks\.slack\.com/services/T[A-Z0-9]+/B[A-Z0-9]+/[A-Za-z0-9]+|ghp_[A-Za-z0-9]{30,}|gho_[A-Za-z0-9]{30,}|ghs_[A-Za-z0-9]{30,}|sk-[A-Za-z0-9]{30,}|xoxb-[0-9]+-[0-9]+-[A-Za-z0-9]+|xoxp-[0-9]+-[0-9]+-[0-9]+-[A-Za-z0-9]+|AKIA[0-9A-Z]{16}|-----BEGIN (RSA |EC |DSA |OPENSSH )?PRIVATE KEY-----'
    if SECRET_HIT=$(grep -rEn "$SECRET_PATTERNS" \
        --include="*.java" --include="*.js" --include="*.ts" \
        --include="*.py" --include="*.properties" --include="*.yml" \
        --include="*.yaml" --include="*.xml" --include="*.json" \
        . 2>/dev/null | head -3); then
      if [ -n "$SECRET_HIT" ]; then
        echo ""
        echo "[ABORT] 🚨 Secret detectado no código — NÃO vou fazer commit automático."
        echo ""
        echo "Locais suspeitos:"
        echo "$SECRET_HIT" | sed 's|^|  |' | cut -c1-120
        echo ""
        echo "Webhook/token/chave NÃO pode ir pra git. Ações:"
        echo "  1. Remova o valor hardcoded (use preferência Sankhya ou env var)"
        echo "  2. Se já vazou pra lugar nenhum, apenas substitua no código"
        echo "  3. Se já foi commitado em outro lugar, revogue o secret AGORA"
        echo "  4. Rode build.sh de novo"
        echo ""
        exit 1
      fi
    fi
    echo "    security gate: nenhum secret detectado"

    git init -q -b main
    # .gitignore mínimo: nunca versionar dist/, target/, nem IDE.
    if [ ! -f .gitignore ]; then
      cat > .gitignore <<'EOF'
# Gerado por snk-deploy na inicialização automática
dist/
target/
*.class
*.log
.DS_Store
# IDE (preservar .classpath e .project porque a skill depende deles)
.idea/
*.iml
# Secrets — nunca commitar
*.token
*.secret
.env
.env.local
.sankhya-slack-webhook
EOF
    fi
    git add -A
    # Committer default caso o global não esteja configurado.
    if ! git config user.email >/dev/null 2>&1; then
      git config user.email "snk-deploy@local"
      git config user.name "snk-deploy auto-init"
    fi
    git commit -q -m "Inicializa projeto Sankhya (auto via snk-deploy)

Repo criado automaticamente pelo build.sh pra habilitar release tracking.
Pra inibir a inicialização automática, exporte SNK_DEPLOY_NO_AUTO_INIT=1."
    echo "    git init + commit inicial OK"
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
      --arg env "$DEPLOY_ENV" \
      --argjson pr "$PR_JSON" \
      '{
        schema_version: 1,
        hash: $hash,
        project: $project,
        env: $env,
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
      printf '  "env": "%s",\n' "$(json_esc "$DEPLOY_ENV")"
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

  echo "==> manifest: $MANIFEST_DIR/manifest.json (hash=$HASH8, env=$DEPLOY_ENV)"
  if [ "$DEPLOY_ENV" = "prod" ]; then
    echo "    [LOG] modo PROD: lib SlackLogger só envia ao Slack quando houver erro."
  else
    echo "    [LOG] modo HOMOL: lib SlackLogger envia tudo (INICIO/INFO/SUCCESS/FIM/FATAL)."
  fi
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
# Sankhya W roda em Java 8 (class file v52). Projetos modernos (JDK 17+)
# geram class v61 por default, que falha no servidor com
# "has been compiled by a more recent version of the Java Runtime".
# Detectamos target do Java a partir de (em ordem):
#   1. $SNK_DEPLOY_JAVA_RELEASE (env var, ex: "8", "11", "17")
#   2. <javaTarget> no .project do Eclipse (se houver)
#   3. default 8 — compativel com qualquer Sankhya W desde 2019
JAVA_RELEASE="${SNK_DEPLOY_JAVA_RELEASE:-8}"
JAVAC_VER=$(javac -version 2>&1 | awk '{print $2}' | cut -d. -f1)
# javac < 9 nao suporta --release; usa -source/-target. javac 9+ suporta --release.
if [ "${JAVAC_VER:-0}" -ge 9 ] 2>/dev/null; then
  javac --release "$JAVA_RELEASE" -encoding UTF-8 -cp "$CLASSPATH" -d target/classes @target/sources.txt
else
  javac -source 1."$JAVA_RELEASE" -target 1."$JAVA_RELEASE" -encoding UTF-8 -cp "$CLASSPATH" -d target/classes @target/sources.txt
fi

# Copiar resources (se houver) — tudo que não é .java NEM .class em src/.
# IMPORTANTE: .class tem que ser excluido — se a IDE deixar .class em src/,
# o cp sobrescreve os .class recem-compilados no target/classes com versoes
# antigas (stale). Bug incidente 2026-04-22 em snk-fabmed-empenho-automatico:
# NoSuchMethodError em Estoque.<init> com 5 args (construtor existia no .java
# mas o .class stale no src/ nao tinha). Mesmo com *.class no .gitignore, a
# IDE gera .class localmente ao abrir o projeto.
if [ -d src ]; then
  # shellcheck disable=SC2016
  (cd src && find . -type f ! -name "*.java" ! -name "*.class" -print0 2>/dev/null \
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
