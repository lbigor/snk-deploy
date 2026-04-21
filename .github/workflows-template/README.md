# workflows-template

O arquivo `ci.yml` aqui dentro é o workflow de CI pronto para uso, mas **não foi
instalado automaticamente** porque o token GitHub usado na criação do repo (GH_TOKEN)
não tinha o escopo `workflow`.

## Como ativar o CI (uma vez)

1. Abra `ci.yml` nesta pasta.
2. Copie o conteúdo.
3. No GitHub web, em <https://github.com/lbigor/snk-deploy>, crie o arquivo
   `.github/workflows/ci.yml` com esse conteúdo e commite em `main`.

Ou via CLI com token que tenha escopo `workflow`:

```bash
mkdir -p .github/workflows
cp .github/workflows-template/ci.yml .github/workflows/ci.yml
git rm -r .github/workflows-template
git add .github/workflows/ci.yml
git commit -m "ci: install workflow"
git push
```

Depois que o workflow estiver ativo e passando, apague esta pasta-template.
