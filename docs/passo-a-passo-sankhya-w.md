# Deploy no Sankhya W — passo a passo

Este é o roteiro literal que a skill exibe depois de gerar o JAR. Copie-colei na UI
do Sankhya W na ordem exata.

## 1. Login no ambiente

Abra o navegador e acesse a URL do Sankhya do cliente. Use usuário com perfil de
administrador (permissão para "Implantação de Customizações").

**Produção**: confirme com o cliente antes. Sexta à tarde não é horário de deploy.

## 2. Abrir Implantação de Customizações

No menu principal:

- **Administração**
- → **Implantação de Customizações**

Abre a tela com a grade de customizações já ativas (coluna "Nome", "Data Ativação",
"Descrição").

## 3. Upload do JAR

Na tela:

1. Clique em **"Adicionar"** (botão verde no canto superior direito).
2. Campo "Arquivo" → escolha o JAR em `dist/` (ex.: `snk-fabmed-wms-20260420-143055.jar`).
3. Campo "Descrição" → cole o nome do projeto + data
   (ex.: `snk-fabmed-wms v2026-04-20`).
4. Clique **"Salvar"**.

A linha nova aparece na grade com status **"Pendente"**.

## 4. Ativar

1. Marque o **checkbox** da linha recém-criada.
2. Clique **"Ativar Selecionados"** (botão azul no topo da grade).
3. O Sankhya processa a importação (10–30 segundos — barra de progresso aparece).
4. Ao final, status muda para **"Ativo"** e a data de ativação é preenchida.

Se der erro no processamento:

- Uma modal exibe o log de erro (NoClassDefFoundError, classe duplicada, etc.).
- Copie o erro, cole no chat com o Claude: `"Claude, deu erro no deploy: ..."`.
- A skill snk-doctor pode diagnosticar a partir desse log.

## 5. Testar

1. Abra o botão/rotina customizada em **outra aba** (não recarregue a aba de
   Implantação — ela mantém estado).
2. Execute o fluxo feliz.
3. Confirme que o log chega no `#logsankhya` (se o projeto usa `snk-slack`):
   - Tag `[INI]` no início.
   - Tag `[FIM]` no final.
4. Se for produção, notifique o cliente no canal acordado
   ("subiu v2026-04-20, rodando ok").

## 6. Rollback (se der errado)

1. Volte para **Administração → Implantação de Customizações**.
2. Na grade, localize a **versão anterior** (coluna "Data Ativação" — a mais recente
   antes da que deu problema).
3. Marque o **checkbox** dessa linha.
4. Clique **"Ativar Selecionados"**.
5. Sankhya desativa a versão problemática e reativa a anterior.
6. Teste o botão de novo — deve voltar ao comportamento antigo.

Se a versão anterior sumiu do histórico:

1. Pegue o JAR da versão anterior em `dist/` (por isso mantemos timestamps).
2. Repita o fluxo da **seção 3** (Adicionar) e **seção 4** (Ativar).

## Dicas

- **Produção**: sempre teste em homologação primeiro. Regra sem exceção.
- **Versionamento**: JARs em `dist/` com timestamp `YYYYMMDD-HHMMSS` facilitam
  responder "o que estava rodando ontem às 14h?".
- **Incidente**: se algo quebrar, [snk-doctor](https://github.com/lbigor/snk-doctor)
  diagnostica pelo Slack (canal `#logsankhya`, team T0ARZ7A7TTN).
- **Cache do browser**: se o botão customizado sumir depois de ativar, o usuário
  pode precisar fazer Ctrl+Shift+R pra limpar cache do Sankhya W.
- **Classe duplicada**: erro comum — mesma classe em dois JARs ativos. Desative o
  antigo primeiro, depois ative o novo.
