# Lições aprendidas — snk-deploy

Aprendizados consolidados do teste piloto de 2026-04-21 com o primeiro
cliente real (projeto `snk-fabmed-empenho-automatico`).

## 1. Security gate antes de qualquer auto-commit

**Incidente 2026-04-21:** `build.sh` fez `git init + git add -A + git commit`
automaticamente num projeto Sankhya legado. O projeto tinha
`SlackConfig.java` com webhook Slack hardcoded (código antigo). O webhook
foi parar no primeiro commit, que foi pushado pro repo privado.

**Mitigação:** antes de `git add -A` no bloco de auto-init, `build.sh`
escaneia o working tree por padrões conhecidos de secret:

```
hooks\.slack\.com/services/T[A-Z0-9]+/B[A-Z0-9]+/[A-Za-z0-9]+
ghp_[A-Za-z0-9]{30,}
gho_[A-Za-z0-9]{30,}
ghs_[A-Za-z0-9]{30,}
sk-[A-Za-z0-9]{30,}
xoxb-[0-9]+-[0-9]+-[A-Za-z0-9]+
xoxp-[0-9]+-[0-9]+-[0-9]+-[A-Za-z0-9]+
AKIA[0-9A-Z]{16}
-----BEGIN (RSA |EC |DSA |OPENSSH )?PRIVATE KEY-----
```

Se achar qualquer match, aborta com mensagem listando os locais e
orientando a correção. Não faz init/commit parcial.

**Regra:** auto-init NUNCA pode começar com repo sujo. Check defensivo é
obrigatório.

## 2. `.classpath` absoluto iCloud não é portável

**Sintoma:** projetos Sankhya legados têm `.classpath` do Eclipse com
paths absolutos tipo `/Users/igorlima/Library/Mobile Documents/com~apple~CloudDocs/...`.
Isso quebra em qualquer outra máquina (colega, cliente, CI).

**Fix:** `build.sh` faz **auto-resolve por basename**:
1. Tenta o path literal do `.classpath`
2. Se não existir, busca o mesmo `basename` em dirs de fallback
3. Placeholder `.icloud` dispara `brctl download` automático

**Fontes de fallback (sem hardcoded):**
1. Env var `$SANKHYA_LIBS` (múltiplos dirs separados por `:`)
2. Arquivo `.snk-deploy.paths` na raiz do projeto (1 dir por linha, suporta `~` e `$HOME`)

Zero paths hardcoded no `build.sh` — cada projeto traz seu próprio
arquivo de configuração committed.

## 3. Git é pré-requisito mas não todo mundo tem

**Sintoma:** projetos Sankhya legados não eram repos git. Release tracking
(manifest com hash+branch+commit+PR) depende de git.

**Fix:** `build.sh` detecta, faz `git init -b main` + `.gitignore` mínimo +
commit inicial. Opt-out via `SNK_DEPLOY_NO_AUTO_INIT=1`.

**`.gitignore` gerado blinda:**
- `dist/`, `target/`, `*.class`, `*.log`, `.DS_Store`
- `.idea/`, `*.iml` (IDE)
- `*.token`, `*.secret`, `.env`, `.env.local`, `.sankhya-slack-webhook`

## 4. GitHub Releases como registry = zero infra

**Decisão:** release tracking publica o JAR + manifest como **GitHub Release**
no repo do cliente. Quando `snk-doctor` vê um hash no log, consulta
`gh release view <tag>` e retorna branch+PR+commit+autor.

Resultado: **zero servidor próprio**. Toda infra de "tracking" fica no
GitHub. Usuário não precisa manter backend nosso.

**Limitação conhecida:** depende de projeto ter remote GitHub (privado ou
público) + token com scope `repo`. Se projeto não tem, release é pulado
silenciosamente (só embute manifest no JAR).

## 5. IntelliJ puro (sem `.classpath`) ainda não suportado

**Descoberta:** de 12 projetos fabmed, 6 têm apenas `.iml` (IntelliJ puro,
sem `.classpath` Eclipse). Nesses, `build.sh` aborta.

**Planejado:** parser de `.iml` que extrai `<orderEntry type="module-library">`
+ `<url>file://$USER_HOME$/...</url>`. Não implementado ainda.

**Workaround manual:** IntelliJ → Project Structure → Export → `.classpath`
(gera um Eclipse equivalente).

---

## Incidentes conhecidos durante o piloto

| Data | Incidente | PR |
|---|---|---|
| 2026-04-21 | Webhook Slack vazou via auto-init git | [#7 security gate](https://github.com/lbigor/snk-deploy/pull/7) |
| 2026-04-21 | JARs do `.classpath` apontavam pra dir iCloud diferente do atual | [#5 auto-resolve](https://github.com/lbigor/snk-deploy/pull/5) |
| 2026-04-21 | Paths absolutos de dir iCloud estavam hardcoded no build.sh | [#6 .snk-deploy.paths](https://github.com/lbigor/snk-deploy/pull/6) |

---

## Próximas melhorias planejadas

- [ ] Parser `.iml` IntelliJ (cobre os 6 projetos fabmed restantes).
- [ ] Suporte Maven (`pom.xml`) + Gradle (`build.gradle`) além do Eclipse.
- [ ] Workflow GitHub Actions com `gitleaks` pra secret scan redundante no PR.
- [ ] Opção `--dry-run` pra ver o que seria feito sem commitar nada.
- [ ] Integração com `snk-doctor`: ao abrir hotfix via PR, criar release
      como "patch" do release original.
