# Instalação

## Via curl

```bash
curl -fsSL https://raw.githubusercontent.com/lbigor/snk-deploy/main/install.sh | bash
```

Instala em `~/.claude/skills/snk-deploy` (ou `$CLAUDE_SKILLS_DIR` se definida).

## Manual

```bash
git clone https://github.com/lbigor/snk-deploy.git ~/.claude/skills/snk-deploy
chmod +x ~/.claude/skills/snk-deploy/scripts/*.sh
```

## Verificar instalação

```bash
cd ~/.claude/skills/snk-deploy
./test.sh
```

Deve imprimir `[ok]` pros arquivos obrigatórios.

## Pré-requisitos

- **JDK 8+** — `javac -version` deve funcionar.
- **`jar`** no PATH (vem com o JDK).
- **Projeto Sankhya** com `.classpath` (Eclipse) válido listando JARs da IBL.
- **Pacote Java** `br.com.lbi` (padrão do grupo Fabmed/DevStudios).

## Primeiro uso

1. `cd` no projeto Sankhya (ex.: `~/Documents/Sankhya/fabmed/snk-fabmed-wms`).
2. No Claude Code: `"Claude, faz o deploy desse projeto"`.
3. Skill detecta, pergunta ambiente, compila, gera JAR em `dist/`.
4. Copia o JAR pro lugar onde você acessa pelo navegador (Downloads, Desktop).
5. Segue o passo-a-passo exibido (resumo em
   [docs/passo-a-passo-sankhya-w.md](docs/passo-a-passo-sankhya-w.md)).

## Deploy no Sankhya W — resumo

Detalhe completo em [docs/passo-a-passo-sankhya-w.md](docs/passo-a-passo-sankhya-w.md).

1. **Login** no ambiente (URL do cliente, usuário administrador).
2. **Administração → Implantação de Customizações**.
3. **Adicionar** → selecionar JAR → descrição (`<projeto> <data>`) → **Salvar**.
4. **Ativar Selecionados**.
5. **Testar** o botão/rotina customizada em outra aba.
6. Confirmar logs no `#logsankhya` (se o projeto usar `snk-slack`).

## Troubleshooting

### `build.sh` falha com "`.classpath` sem JARs"

- Verifique se o projeto tem `.classpath` (Eclipse). IntelliJ puro não gera.
- Abra o arquivo, confirme que há linhas `<classpathentry kind="lib" path="..."/>`.

### `javac` falha com "cannot find symbol"

- Algum JAR do `.classpath` sumiu do iCloud (sync quebrado).
- Rode `ls` no path do JAR que o erro aponta. Se não existir, force o sync do iCloud.

### JAR sobe mas rotina não aparece no Sankhya

- Confira o campo `NOME_RTP` cadastrado na rotina no Sankhya W.
- Classe Java implementada bate com o `NOME_RTP`? Pacote completo?
- Veja [snk-doctor](https://github.com/lbigor/snk-doctor) pra diagnóstico via logs.

### Rollback necessário

- Ver [BOAS_PRATICAS.md](BOAS_PRATICAS.md) seção Rollback.
