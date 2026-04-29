# Modo de log Slack por ambiente (prod/homol) — REGRA OBRIGATÓRIA

## TL;DR

snk-deploy embute `env: "prod" | "homol"` em `META-INF/snk-deploy/manifest.json`.
A lib `br.com.lbi.slack.SlackLogger` lê esse campo via `DeployManifest.getEnv()` e
ajusta `flush()` conforme:

| `env` | Comportamento `flush()` |
|---|---|
| `homol` | envia tudo (INICIO, INFO, DEBUG, SUCCESS, FIM, FATAL) |
| `prod` (default) | só envia se buffer contém ao menos 1 entry de severity ERROR |
| ausente | mesmo que `prod` (conservador) |

## Por que assim e não via preferência Sankhya

- **Build-time imutável.** O destino (prod/homol) é decidido pelo operador no
  momento do `snk-deploy --env <X>`. Mesmo JAR não pode rodar em ambos.
- **Sem risco de pref errada flooding produção.** Se a pref `LOGSLACK_MODE`
  estivesse em runtime e alguém esquecesse de mudar, prod recebia spam.
- **Auditável.** Manifest viaja com o JAR — `DeployManifest.toFooter()` já anexa
  `v: <hash>` em todos os logs. Adicionar `env` é trivial.

## Padrão obrigatório no caller

```java
boolean logSlackAtivo = "S".equals(MGECoreParameter.getParameterAsString("LOGSLACK"));
SlackLogger slack = logSlackAtivo
    ? SlackLogger.create(null)
        .modulo("Nome Modulo")
        .header("NomeAcao")
        .build()
    : SlackLogger.NOOP;

try {
    slack.info("INICIO", "===");
    // ... trabalho ...
    slack.success("FIM", "===");
    slack.flush();   // prod: descarta sem ERROR; homol: envia
} catch (Exception e) {
    slack.error("FATAL", "...", e);
    slack.flush();   // sempre envia (buffer tem ERROR)
    throw e;
}
```

**Nunca** checar pref `LOGSLACK_MODE` no caller — quem decide é o build.

## Status da implementação

| Componente | Status |
|---|---|
| `snk-deploy/scripts/build.sh` aceita `--env prod\|homol` | ✅ pronto |
| `manifest.json` tem campo `env` | ✅ pronto |
| `SKILL.md` documenta passo de pergunta + flag | ✅ pronto |
| `DeployManifest.getEnv()` (lib snk-slack) | 🔧 TODO |
| `SlackLogger.flush()` checa env e suprime non-error em prod | 🔧 TODO |

A parte Java (DeployManifest + SlackLogger) é PR separado no projeto-gabarito
`snk-fabmed-empenho-automatico` e propaga pros demais via copy da lib.
