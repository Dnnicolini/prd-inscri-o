# Ficha PRD - Preenchimento Automático

Projeto rápido para digitar os dados da ficha e gerar o PDF já preenchido para impressão.

## Como rodar

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
python app.py
```

Abra `http://127.0.0.1:5000`.

## O que ele faz

- Interface web para preencher os campos da ficha.
- Gera um PDF preenchido nas duas vias do documento.
- Abre o arquivo em nova aba para imprimir.
- Consulta UF e município pelo IBGE.
- Consulta CEP (ViaCEP) para auto preencher endereço/bairro/cidade/UF.
- Campo de zona eleitoral em `select`.
- Sem preenchimento automático dos campos de assinatura.

## Observação

O PDF original não possui campos de formulário (`AcroForm`), então o projeto escreve os dados por sobreposição de texto em coordenadas calibradas do layout.

## Deploy rapido em VPS com Traefik (dominio prd.dnnicolini.com)

Arquivos:
- `scripts/bootstrap_vps_traefik.sh` (instala git, clona repo e faz setup completo)
- `scripts/setup_vps_traefik.sh` (setup inicial: venv + gunicorn + systemd + traefik)
- `scripts/deploy_vps.sh` (deploy diario: git pull + restart)

### 1) DNS

No painel DNS, crie:
- `A` para `prd.dnnicolini.com` apontando para o IP da VPS

### 2) Copiar projeto para VPS

Exemplo:
```bash
scp -r . usuario@IP_DA_VPS:/opt/ficha
```

### 3) Rodar setup inicial na VPS

```bash
ssh usuario@IP_DA_VPS
cd /opt/ficha
sudo DEPLOY_USER=usuario DOMAIN=prd.dnnicolini.com bash scripts/setup_vps_traefik.sh
```

### 3.1) Bootstrap 100% automatico (clona + instala + sobe)

Se quiser fazer tudo com 1 comando (sem clone manual), execute na VPS:
```bash
sudo DEPLOY_USER=usuario \
  REPO_URL=https://github.com/seu-user/seu-repo.git \
  BRANCH=main \
  DOMAIN=prd.dnnicolini.com \
  APP_DIR=/opt/ficha \
  bash /caminho/para/bootstrap_vps_traefik.sh
```

Se o Traefik estiver em container e nao conseguir acessar `127.0.0.1:8000`, rode com upstream do host:
```bash
sudo DEPLOY_USER=usuario DOMAIN=prd.dnnicolini.com APP_UPSTREAM=http://IP_DA_VPS:8000 bash scripts/setup_vps_traefik.sh
```

### 4) Deploy das proximas atualizacoes

Na VPS:
```bash
cd /opt/ficha
bash scripts/deploy_vps.sh
```

Se seu branch nao for `main`, rode:
```bash
BRANCH=nome-do-branch bash scripts/deploy_vps.sh
```
