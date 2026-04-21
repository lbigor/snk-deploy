---
name: snk-deploy
description: Empacota projeto Sankhya Java em JAR e guia o deploy via Administração → Implantação de Customizações do Sankhya W. Acionar quando usuário disser "faz o deploy", "sobe esse projeto", "gera o JAR", "empacota pra produção".
type: skill
---

# snk-deploy — fluxo

## Gatilhos

A skill deve disparar quando o usuário disser coisas como:

- "Claude, faz o deploy desse projeto"
- "sobe esse projeto pro Sankhya"
- "gera o JAR pra homologação"
- "empacota pra produção"
- "preciso subir essa customização"

## Fluxo

1. **Detectar projeto.** Rodar `scripts/detect-project.sh` no cwd. Deve ter:
   - `.classpath` com entries `kind="lib"` apontando pros JARs da Sankhya.
   - `src/` com arquivos `.java` sob pacote `br.com.lbi`.
   - Se falhar, avisar e não prosseguir — a skill não inventa projeto.
2. **Perguntar ambiente.** "Homologação ou produção?"
   - Homologação: segue direto.
   - Produção: pede confirmação extra ("Confirma deploy em PRODUÇÃO do cliente X?")
     antes de gerar o JAR.
3. **Compilar e empacotar.** Rodar `scripts/build.sh` no diretório do projeto.
   - Gera `dist/<nome>-<timestamp>-<hash8>.jar`.
   - Se `javac` falhar, parar e mostrar erros. Nunca subir JAR incompleto.
3.5. **Release tracking.** Ao compilar, a skill embute `META-INF/snk-deploy/manifest.json`
     dentro do JAR com: branch, commit, PR associado (via `gh`), autor, timestamp, hash curto.
     Este manifest é lido automaticamente por `snk-slack` em runtime e anexado aos logs,
     permitindo que `snk-doctor` rastreie qualquer erro de volta ao PR que o causou.
     Se o repo tiver permissão `gh release create`, um release é criado automaticamente
     com o JAR como asset (opcional — controle via env `SNK_DEPLOY_CREATE_RELEASE=1` ou
     flag `--release` no build.sh). Detalhes em
     [docs/release-tracking.md](docs/release-tracking.md).
4. **Exibir passo-a-passo.** Mostrar o conteúdo de
   [docs/passo-a-passo-sankhya-w.md](docs/passo-a-passo-sankhya-w.md) adaptado ao
   ambiente escolhido.
5. **Opcional: atualizar CHANGELOG.md** do projeto com a nova versão + timestamp +
   ambiente. Pedir OK antes de editar.
6. **Reportar.** Caminho absoluto do JAR gerado, tamanho, próximo passo na UI Sankhya.

## Invariantes

- **Nunca** rodar `javac` sem ler o `.classpath` primeiro. O classpath tem JARs em path
  absoluto do iCloud — não dá pra chutar.
- **Nunca** compilar com flags além de `-encoding UTF-8` e `-cp`. Sem `-source/-target`
  customizado — deixar o `javac` do ambiente decidir (padrão do JDK do dev).
- **Nunca** subir JAR pro cliente sem o dev confirmar o ambiente.
- JARs em `dist/` sempre com timestamp `YYYYMMDD-HHMMSS-<hash8>` pra rastreio.
- Se `aplicacao: produção`, pedir confirmação verbal explícita antes do build.

## Dependências

- `javac` e `jar` (JDK 8+) no PATH.
- Projeto com `.classpath` (Eclipse) listando JARs da IBL.
- Opcional: [snk-slack](https://github.com/lbigor/snk-slack) já instrumentado no projeto
  para validar que o deploy funcionou via canal `#logsankhya`.

## O que a skill NÃO faz

- Não abre o Sankhya W automaticamente (não há API pública de Implantação).
- Não executa `javac` em projeto que não seja Sankhya (detect falha).
- Não faz rollback automático — só mostra como reverter pela UI.
- Não gerencia JARs de terceiros (Gson etc.); assume que já estão no classpath
  do ambiente Sankhya.
