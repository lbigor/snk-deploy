# Contribuindo

## Escopo

Esta skill cobre **empacotamento e deploy** de projeto Sankhya Java no Sankhya W.

Está fora do escopo:

- Deploy de código Python/Flask (fora do ecossistema Sankhya).
- Gerenciamento de JARs de terceiros (responsabilidade do `.classpath` do projeto).
- Automação da UI do Sankhya W via browser (não há API pública estável).
- Rollback automático (só documentamos o passo-a-passo manual).

## Rodando localmente

```bash
git clone https://github.com/lbigor/snk-deploy.git
cd snk-deploy
chmod +x install.sh test.sh scripts/*.sh
./test.sh
```

## Pull Requests

1. Fork + branch dedicada (`feature/nome`, `fix/nome`, `docs/nome`).
2. Rode `./test.sh` antes de abrir o PR.
3. Markdown passa em `markdownlint` (config em `.markdownlint.json`).
4. Siga o template do PR (`.github/pull_request_template.md`).
5. Todo PR vai pra revisão do @lbigor (CODEOWNERS).

## Tipos de contribuição

- **Ajuste no `build.sh`**: testar com pelo menos 1 projeto Sankhya real antes de abrir
  PR. Não quebrar o contrato (`dist/<nome>-<timestamp>.jar`).
- **Novo passo no `docs/passo-a-passo-sankhya-w.md`**: só se a UI do Sankhya W mudou e
  você tem screenshot textual (texto literal do botão/menu).
- **Mudança em `SKILL.md`**: precisa justificar no PR — gatilhos e invariantes afetam
  como a skill dispara.

## Testando mudanças no `build.sh`

Use um projeto Sankhya real como referência (sem modificá-lo):

```bash
./scripts/build.sh ~/Documents/Sankhya/fabmed/snk-fabmed-empenho-automatico
ls ~/Documents/Sankhya/fabmed/snk-fabmed-empenho-automatico/dist/
```

Deve aparecer `snk-fabmed-empenho-automatico-<timestamp>.jar`.

## Commit style

Imperativo curto, em pt-br:

- `adiciona checklist de rollback em BOAS_PRATICAS.md`
- `corrige classpath quebrado quando .classpath tem CDATA`
- `documenta botão novo "Importar em lote" do Sankhya W`

Sem emoji, sem corpo obrigatório (só se for mudança não-óbvia).
