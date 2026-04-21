# Boas práticas — deploy Sankhya

## Homologação vs produção

| Aspecto | Homologação | Produção |
|---|---|---|
| Confirmação verbal | não | **sim, obrigatória** |
| Horário | qualquer | fora do pico do cliente |
| Smoke test | 1 fluxo feliz | 1 feliz + 1 borda |
| Log Slack | `#logsankhya` ok | `#logsankhya` **+ aviso no canal do cliente** |
| Rollback preparado | opcional | **JAR anterior salvo e testado** |

**Regra de ouro:** nunca suba em produção sem ter rodado a mesma versão em homologação
por pelo menos uma rodada completa.

## Versionamento e timestamps

- JARs em `dist/<nome>-YYYYMMDD-HHMMSS.jar`.
- Manter **pelo menos as 3 últimas versões** em `dist/` pra rollback rápido.
- `dist/` **não** é commitado (está no `.gitignore` do projeto Sankhya).
- Descrição na UI Sankhya sempre: `<projeto> v<data>` (ex.: `snk-fabmed-wms v2026-04-20`).

## Rollback

Na UI Sankhya W (resumo — detalhe em
[docs/passo-a-passo-sankhya-w.md](docs/passo-a-passo-sankhya-w.md)):

1. Administração → Implantação de Customizações.
2. Localize a versão anterior no histórico (coluna "Data").
3. Marque o checkbox dessa linha.
4. Clique **Ativar Selecionados**.
5. Confirme: rotina volta ao comportamento antigo em segundos.

Se a versão anterior não estiver no histórico:

- Pegue o JAR em `dist/` (por isso guardamos timestamps).
- Repita o fluxo Adicionar → Ativar com esse JAR.

## Quando NÃO fazer deploy

- Sexta-feira depois de 16h em produção.
- Sem ter o log do `#logsankhya` configurado (perde visibilidade se quebrar).
- Com alterações não commitadas no git (perde rastreio do que subiu).
- Sem ter rodado `./test.sh` do projeto (se existir).
- Com `javac` jogando warning de `unchecked`/`deprecated` — investigue antes.

## Smoke test mínimo

Depois de ativar o JAR no Sankhya W:

1. Abra a rotina/botão customizado em **outra aba** (não recarregue a aba atual).
2. Execute o fluxo feliz (1 clique que disparaa classe Java).
3. Observe o `#logsankhya`: deve aparecer `[INI]`, depois `[FIM]`.
4. Se for produção, execute também um caso de borda (ex.: item sem saldo,
   parceiro bloqueado) e confirme mensagem de erro amigável.

## Se algo der errado

1. **Não entre em pânico.** Rollback leva 10 segundos na UI.
2. Rollback imediato pela UI (acima).
3. Abra o `#logsankhya`, procure `[FATAL]` ou `[ERRO]` da rodada que falhou.
4. Use [snk-doctor](https://github.com/lbigor/snk-doctor) pra diagnosticar:
   `"Claude, deu erro no deploy que acabei de subir, ver no Slack"`.
5. Corrija no código, rode `build.sh` de novo, suba novo JAR.

## Checklist antes de apertar "Ativar" em produção

- [ ] Versão rodou em homologação com sucesso.
- [ ] Git commit do código que virou o JAR.
- [ ] JAR gerado com timestamp (não é um `snapshot.jar` genérico).
- [ ] Descrição preenchida no Sankhya W com projeto + data.
- [ ] Versão anterior identificada no histórico pra rollback rápido.
- [ ] Aviso enviado no canal do cliente ("subindo v2026-04-20, 5 min").
- [ ] `#logsankhya` aberto em outra aba pra acompanhar.
