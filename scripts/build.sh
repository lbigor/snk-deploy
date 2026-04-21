#!/usr/bin/env bash
# build.sh — compila projeto Sankhya Java e empacota em JAR com timestamp.
#
# Uso:
#   ./build.sh                      # compila projeto no cwd
#   ./build.sh /caminho/do/projeto  # compila projeto em outro lugar
#
# Saída:
#   <projeto>/dist/<nome>-YYYYMMDD-HHMMSS.jar
#
# Pré-requisitos:
#   - javac e jar no PATH (JDK 8+).
#   - Projeto com .classpath (Eclipse) listando JARs kind="lib".
#   - Código-fonte em src/.

set -euo pipefail

PROJETO_DIR="${1:-.}"
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

# Compilar.
find src -name "*.java" > target/sources.txt
if [ ! -s target/sources.txt ]; then
  echo "[FAIL] nenhum .java encontrado em src/"
  exit 1
fi

echo "==> compilando $(wc -l < target/sources.txt | tr -d ' ') arquivos"
javac -encoding UTF-8 -cp "$CLASSPATH" -d target/classes @target/sources.txt

# Copiar resources (se houver) — tudo que não é .java em src/.
if [ -d src ]; then
  (cd src && find . -type f ! -name "*.java" -print0 2>/dev/null \
    | xargs -0 -I{} sh -c 'mkdir -p "../target/classes/$(dirname "{}")" && cp "{}" "../target/classes/{}"' \
    || true)
fi

# Empacotar.
JAR_NAME="${NOME}-${TIMESTAMP}.jar"
jar cf "${DIST}/${JAR_NAME}" -C target/classes .

SIZE="$(du -h "${DIST}/${JAR_NAME}" | cut -f1)"
ABSOLUTE="$(cd "$DIST" && pwd)/${JAR_NAME}"

echo ""
echo "[OK] JAR gerado"
echo "     arquivo:  $ABSOLUTE"
echo "     tamanho:  $SIZE"
echo ""
echo "Próximo passo: Administração → Implantação de Customizações no Sankhya W."
echo "Veja docs/passo-a-passo-sankhya-w.md pro detalhe."
