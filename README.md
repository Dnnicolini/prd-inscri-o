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
