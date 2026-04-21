# snk-deploy

> Empacota projeto Sankhya Java em JAR e guia o deploy via Administração → Implantação
> de Customizações no Sankhya W.

**Problema:** dev gasta 20 min por deploy mexendo em IDE, empacotando na mão, subindo
JAR, tentando lembrar qual checkbox marcar no Sankhya W.
**Solução:** skill detecta o projeto, monta classpath a partir do `.classpath`, compila,
empacota com timestamp e gera checklist passo-a-passo da UI Sankhya W.
**Você faz:** `"Claude, faz o deploy desse projeto"`.

## Instalação

```bash
curl -fsSL https://raw.githubusercontent.com/lbigor/snk-deploy/main/install.sh | bash
```

Pré-requisitos:

- `javac` e `jar` no PATH (JDK 8+).
- Projeto Sankhya Java com `.classpath` (Eclipse) e pacote `br.com.lbi`.
- JARs da IBL em path absoluto no `.classpath` (padrão
  `~/Library/Mobile Documents/com~apple~CloudDocs/DevStudios/Java/Libs/Sankhya/`).

## Como funciona

1. Usuário roda o gatilho (`"Claude, faz o deploy desse projeto"`).
2. Skill detecta via `scripts/detect-project.sh` se o cwd é projeto Sankhya válido.
3. Pergunta ambiente de destino: **homologação** ou **produção**.
4. Roda `scripts/build.sh`: lê `.classpath`, compila com `javac`, empacota em
   `dist/<nome>-<timestamp>.jar`.
5. Exibe checklist com textos exatos da UI Sankhya W (ver
   [docs/passo-a-passo-sankhya-w.md](docs/passo-a-passo-sankhya-w.md)).
6. Se produção, pede confirmação extra antes de exibir o passo-a-passo.

Veja [SKILL.md](SKILL.md) pro fluxo completo, [BOAS_PRATICAS.md](BOAS_PRATICAS.md) pras
regras de produção vs homologação, rollback e versionamento, e
[INSTALACAO.md](INSTALACAO.md) pro detalhamento dos passos.

## Estrutura

| Arquivo | Conteúdo |
|---|---|
| [SKILL.md](SKILL.md) | Gatilhos e fluxo da skill |
| [INSTALACAO.md](INSTALACAO.md) | Instalação + passo-a-passo completo do deploy |
| [BOAS_PRATICAS.md](BOAS_PRATICAS.md) | Produção vs homologação, rollback, versionamento |
| [docs/passo-a-passo-sankhya-w.md](docs/passo-a-passo-sankhya-w.md) | UI Sankhya W — textos e cliques exatos |
| [scripts/build.sh](scripts/build.sh) | Compila projeto Sankhya → JAR com timestamp |
| [scripts/detect-project.sh](scripts/detect-project.sh) | Valida se cwd é projeto Sankhya |
| [CONTRIBUTING.md](CONTRIBUTING.md) | Como contribuir |

## Dependências opcionais

- [snk-slack](https://github.com/lbigor/snk-slack) — log centralizado no `#logsankhya`.
- [snk-doctor](https://github.com/lbigor/snk-doctor) — diagnóstico se algo falhar depois
  do deploy.

## Licença

MIT — ver [LICENSE](LICENSE).
