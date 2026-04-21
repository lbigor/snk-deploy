# Release Tracking

A skill `snk-deploy` embute um manifest dentro de todo JAR gerado para que
qualquer erro observado em produção possa ser rastreado até o **commit** e
**PR** exatos que o introduziram — sem depender de infra externa.

## Por quê

Antes: JAR chegava no cliente com nome `projeto-20260421-140300.jar`. Se
quebrasse, o caminho pra achar o responsável era:

1. Perguntar ao dev qual branch estava em produção.
2. Cruzar horário de build com commits do dia.
3. Torcer pra ninguém ter feito rebase.

Agora: o próprio JAR carrega o commit SHA e o link do PR. `snk-slack` lê o
manifest em runtime e anexa aos logs do canal `#logsankhya`; `snk-doctor` usa
o mesmo dado pra clicar direto no PR responsável.

Zero infra adicional — os releases ficam no próprio repo GitHub do cliente
(opcional) e a rastreabilidade mínima já está dentro do JAR.

## Formato do `manifest.json`

Caminho dentro do JAR: `META-INF/snk-deploy/manifest.json`.

```json
{
  "schema_version": 1,
  "hash": "abc12345",
  "project": "snk-fabmed-wms",
  "built_at": "2026-04-21T14:03:00Z",
  "git": {
    "branch": "feat/fix-estoque",
    "commit": "a3f2d1b4c5e6f7089abcdef0123456789abcdef0",
    "commit_short": "a3f2d1b4",
    "author": "Igor Lima <lbigor@icloud.com>",
    "committed_at": "2026-04-21T13:45:00Z"
  },
  "pr": {
    "number": 42,
    "url": "https://github.com/lbigor/snk-fabmed-wms/pull/42",
    "title": "fix: ignora estoque negativo no empenho"
  },
  "tool": "snk-deploy",
  "tool_version": "1.0.0"
}
```

### Campos

| Campo | Tipo | Origem | Observação |
|---|---|---|---|
| `schema_version` | int | fixo | Sobe quando o shape mudar. |
| `hash` | string (8 hex) | `sha256(commit+timestamp)[:8]` | Também vai no nome do JAR. |
| `project` | string | `basename` do dir | Normalmente `snk-fabmed-wms` etc. |
| `built_at` | ISO-8601 UTC | `date -u` | Instante do build. |
| `git.branch` | string | `git branch --show-current` | Pode ser `""` em detached HEAD. |
| `git.commit` | string (40 hex) | `git rev-parse HEAD` | Full SHA. |
| `git.commit_short` | string (8 hex) | `git rev-parse --short=8 HEAD` | Pra display. |
| `git.author` | string | `git log -1 --format='%an <%ae>'` | Nome + e-mail do último commit. |
| `git.committed_at` | ISO-8601 | `git log -1 --format='%aI'` | Com timezone do autor. |
| `pr` | object \| null | `gh pr list --search "head:$branch"` | `null` se gh indisponível ou sem PR. |
| `pr.number` | int | gh | — |
| `pr.url` | string | gh | Link direto pro PR no GitHub. |
| `pr.title` | string | gh | Primeira linha do PR. |
| `tool` | string | fixo (`"snk-deploy"`) | Quem gerou o manifest. |
| `tool_version` | string | fixo (`"1.0.0"`) | Versão da skill. |

## Como outras skills consomem

### `snk-slack`

Em cada envio de log pro `#logsankhya`, `snk-slack` lê
`META-INF/snk-deploy/manifest.json` do classpath e anexa `hash` + link do PR
ao final da mensagem. Exemplo:

```text
[FATAL] snk-fabmed-wms NullPointer em TgfEmpenhoEvent.beforeInsert(...)
        build abc12345 · PR #42
```

### `snk-doctor`

Ao diagnosticar um erro vindo do Slack, `snk-doctor` usa o `hash` pra localizar
o manifest correspondente (cacheado no histórico) e abre o PR linkado pra
entender o que mudou — sem dependência de CHANGELOG manual.

## Como inspecionar um JAR

Qualquer dev pode ver o hash de um JAR instalado no cliente:

```bash
unzip -p projeto-20260421-140300-abc12345.jar META-INF/snk-deploy/manifest.json | jq
```

Se `jq` não estiver disponível:

```bash
unzip -p projeto-20260421-140300-abc12345.jar META-INF/snk-deploy/manifest.json
```

O hash também aparece no **nome do arquivo** — o sufixo `-abc12345.jar` é
idêntico ao campo `hash` do manifest.

## GitHub Release opcional

Se o projeto tiver remote GitHub e o dev rodar com `--release` (ou export
`SNK_DEPLOY_CREATE_RELEASE=1`), o `build.sh` executa:

```bash
gh release create "v${TIMESTAMP}-${HASH8}" "$JAR_PATH" \
  --title "$NOME $TIMESTAMP" \
  --notes "<extraído do manifest>" \
  --target "$COMMIT"
```

Isso publica o JAR como asset no GitHub Releases do próprio repo do cliente.
Se `gh release create` falhar (sem auth, sem permissão, rede etc.), o build
apenas avisa — **não aborta**, porque o manifest embutido já resolve o
rastreio mínimo.

## Como desabilitar

```bash
export SNK_DEPLOY_SKIP_MANIFEST=1
./scripts/build.sh
```

Resultado: JAR antigo sem `META-INF/snk-deploy/manifest.json` e com nome
curto `<nome>-<timestamp>.jar` (sem o sufixo de hash). Útil pra
retrocompatibilidade com automações que dependem do formato antigo.

## Limitações conhecidas

- `gh pr list` só acha PR **aberto** na branch atual — se o dev fez merge
  antes do build, o manifest sai com `pr: null`. Workaround: rodar build
  antes do merge.
- Commits não-assinados funcionam normalmente; GPG/SSH signing não altera
  nada.
- Em detached HEAD (`git checkout <sha>`), `branch` sai como string vazia.
  O commit ainda é registrado corretamente.
- `shasum -a 256` existe em macOS e na maioria das distros Linux. Em
  ambientes mínimos pode ser preciso instalar coreutils.
