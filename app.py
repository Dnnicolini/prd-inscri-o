from __future__ import annotations

import io
import re
from functools import lru_cache
from datetime import datetime
from pathlib import Path

import requests
from flask import Flask, jsonify, render_template, request, send_file
from pypdf import PdfReader, PdfWriter
from reportlab.lib.pagesizes import A4
from reportlab.pdfgen import canvas

app = Flask(__name__)

BASE_DIR = Path(__file__).resolve().parent
TEMPLATE_PATH = BASE_DIR / "assets" / "ficha_template.pdf"

PAGE_WIDTH_PT, PAGE_HEIGHT_PT = A4
PX_PER_POINT = 150 / 72  # image preview generated with pdftoppm default DPI (150)
TEXT_BASELINE_SHIFT_PX = 16

COPY_OFFSETS_PX = [0, 878]
ZONE_OPTIONS = [f"{i:03d}" for i in range(1, 1000)]
ESTADO_CIVIL_OPTIONS = [
    "SOLTEIRO",
    "CASADO",
    "DIVORCIADO",
    "VIUVO",
    "UNIAO ESTAVEL",
    "SEPARADO",
    "OUTRO",
]
HTTP_TIMEOUT_SECONDS = 8
ZONE_OPTIONS_SET = set(ZONE_OPTIONS)
ESTADO_CIVIL_OPTIONS_SET = set(ESTADO_CIVIL_OPTIONS)

# (field_name, x_px, y_px, max_width_px, align)
FIELD_LAYOUT = [
    ("nome", 256, 76, 640, "left"),
    ("nome_social", 228, 139, 956, "left"),
    ("zona_eleitoral", 228, 202, 250, "left"),
    ("municipio_estado", 500, 202, 684, "left"),
    ("naturalidade", 228, 261, 250, "left"),
    ("titulo_eleitor", 503, 261, 246, "left"),
    ("secao", 757, 261, 129, "center"),
    ("estado_civil", 886, 261, 313, "center"),
    ("pai", 336, 318, 850, "left"),
    ("mae", 336, 380, 850, "left"),
    ("endereco", 228, 442, 572, "left"),
    ("bairro_setor", 820, 442, 371, "left"),
    ("cep", 228, 502, 236, "left"),
    ("email", 476, 502, 713, "left"),
    ("cpf", 228, 564, 481, "left"),
    ("rg", 738, 564, 453, "left"),
    ("profissao", 228, 628, 287, "left"),
    ("celular_whatsapp", 527, 628, 282, "left"),
    ("rede_social", 821, 628, 370, "left"),
]

FIELD_FONT_LIMITS = {
    "nome": {"max": 12, "min": 5},
    "nome_social": {"max": 12, "min": 6},
}

DATE_LAYOUT = {
    # coordinates calibrated to the pre-printed "__/__/____" guides
    "data_nasc": {
        "y_px": 67,
        "segments": [(940, 62), (1012, 68), (1112, 62)],
    },
    "data_inscricao": {
        "y_px": 778,
        "segments": [(236, 66), (316, 72), (402, 72)],
    },
}


def px_to_pt_x(x_px: float) -> float:
    return x_px / PX_PER_POINT


def px_to_pt_y(y_px: float) -> float:
    return PAGE_HEIGHT_PT - (y_px / PX_PER_POINT)


def normalize_date(raw_date: str) -> str:
    raw_date = (raw_date or "").strip()
    if not raw_date:
        return ""
    try:
        dt = datetime.strptime(raw_date, "%Y-%m-%d")
        return dt.strftime("%d/%m/%Y")
    except ValueError:
        return raw_date


def fit_text(
    pdf_canvas: canvas.Canvas,
    value: str,
    max_width_pt: float,
    font_name: str = "Helvetica",
    max_font_size: int = 12,
    min_font_size: int = 8,
) -> tuple[str, int]:
    text = (value or "").replace("\n", " ").strip()
    if not text:
        return "", max_font_size

    font_size = max_font_size
    while font_size > min_font_size:
        width = pdf_canvas.stringWidth(text, font_name, font_size)
        if width <= max_width_pt:
            return text, font_size
        font_size -= 1

    # hard truncate if still too wide
    safe = text
    while safe:
        candidate = f"{safe}..."
        width = pdf_canvas.stringWidth(candidate, font_name, min_font_size)
        if width <= max_width_pt:
            return candidate, min_font_size
        safe = safe[:-1]
    return "", min_font_size


def draw_field(
    pdf_canvas: canvas.Canvas,
    value: str,
    x_px: float,
    y_px: float,
    max_width_px: float,
    align: str,
    max_font_size: int = 12,
    min_font_size: int = 8,
) -> None:
    if not value:
        return

    max_width_pt = max_width_px / PX_PER_POINT
    x_pt = px_to_pt_x(x_px)
    y_pt = px_to_pt_y(y_px + TEXT_BASELINE_SHIFT_PX)
    text, font_size = fit_text(
        pdf_canvas,
        value,
        max_width_pt,
        max_font_size=max_font_size,
        min_font_size=min_font_size,
    )
    if not text:
        return

    font_name = "Helvetica"
    pdf_canvas.setFont(font_name, font_size)
    text_width = pdf_canvas.stringWidth(text, font_name, font_size)

    if align == "center":
        origin_x = x_pt + (max_width_pt - text_width) / 2
    elif align == "right":
        origin_x = x_pt + (max_width_pt - text_width)
    else:
        origin_x = x_pt

    pdf_canvas.drawString(origin_x, y_pt, text)


def split_date_parts(raw: str) -> tuple[str, str, str]:
    value = (raw or "").strip()
    if not value:
        return "", "", ""

    match = re.fullmatch(r"(\d{2})/(\d{2})/(\d{4})", value)
    if match:
        return match.group(1), match.group(2), match.group(3)

    digits = re.sub(r"\D", "", value)
    if len(digits) >= 8:
        return digits[:2], digits[2:4], digits[4:8]
    return "", "", ""


def draw_date_field(pdf_canvas: canvas.Canvas, value: str, y_px: float, segments: list[tuple[int, int]]) -> None:
    day, month, year = split_date_parts(value)
    if not any([day, month, year]):
        return

    parts = [day, month, year]
    for text, (x_px, max_width_px) in zip(parts, segments):
        if not text:
            continue
        draw_field(
            pdf_canvas=pdf_canvas,
            value=text,
            x_px=x_px,
            y_px=y_px,
            max_width_px=max_width_px,
            align="center",
        )


def normalize_cep(raw_cep: str) -> str:
    digits = re.sub(r"\D", "", raw_cep or "")
    if len(digits) != 8:
        return raw_cep.strip()
    return f"{digits[:5]}-{digits[5:]}"


def normalize_uf(raw_uf: str) -> str:
    value = (raw_uf or "").strip().upper()
    if re.fullmatch(r"[A-Z]{2}", value):
        return value
    return ""


@lru_cache(maxsize=1)
def cached_ibge_ufs() -> list[dict[str, str]]:
    response = requests.get(
        "https://servicodados.ibge.gov.br/api/v1/localidades/estados",
        timeout=HTTP_TIMEOUT_SECONDS,
    )
    response.raise_for_status()
    payload = response.json()
    return [
        {"sigla": item["sigla"], "nome": item["nome"]}
        for item in sorted(payload, key=lambda current: current["nome"])
    ]


@lru_cache(maxsize=30)
def cached_ibge_municipios(uf: str) -> list[str]:
    response = requests.get(
        f"https://servicodados.ibge.gov.br/api/v1/localidades/estados/{uf}/municipios",
        timeout=HTTP_TIMEOUT_SECONDS,
    )
    response.raise_for_status()
    payload = response.json()
    return [item["nome"] for item in payload]


def lookup_cep(cep: str) -> dict[str, str]:
    digits = re.sub(r"\D", "", cep or "")
    if len(digits) != 8:
        return {}

    response = requests.get(
        f"https://viacep.com.br/ws/{digits}/json/",
        timeout=HTTP_TIMEOUT_SECONDS,
    )
    response.raise_for_status()
    payload = response.json()
    if payload.get("erro"):
        return {}
    return {
        "cep": normalize_cep(payload.get("cep", "")),
        "logradouro": payload.get("logradouro", ""),
        "bairro": payload.get("bairro", ""),
        "municipio": payload.get("localidade", ""),
        "uf": payload.get("uf", ""),
    }


def create_overlay_pdf(data: dict[str, str]) -> bytes:
    packet = io.BytesIO()
    pdf_canvas = canvas.Canvas(packet, pagesize=A4)
    pdf_canvas.setFillColorRGB(0.08, 0.08, 0.08)

    for offset in COPY_OFFSETS_PX:
        for field_name, x_px, y_px, max_width_px, align in FIELD_LAYOUT:
            value = data.get(field_name, "").strip()
            font_limits = FIELD_FONT_LIMITS.get(field_name, {})
            draw_field(
                pdf_canvas=pdf_canvas,
                value=value,
                x_px=x_px,
                y_px=y_px + offset,
                max_width_px=max_width_px,
                align=align,
                max_font_size=font_limits.get("max", 12),
                min_font_size=font_limits.get("min", 8),
            )

        for field_name, cfg in DATE_LAYOUT.items():
            draw_date_field(
                pdf_canvas=pdf_canvas,
                value=data.get(field_name, "").strip(),
                y_px=cfg["y_px"] + offset,
                segments=cfg["segments"],
            )

    pdf_canvas.save()
    packet.seek(0)
    return packet.read()


def fill_pdf(data: dict[str, str]) -> bytes:
    overlay_pdf_bytes = create_overlay_pdf(data)
    template_reader = PdfReader(str(TEMPLATE_PATH))
    overlay_reader = PdfReader(io.BytesIO(overlay_pdf_bytes))

    writer = PdfWriter()
    base_page = template_reader.pages[0]
    base_page.merge_page(overlay_reader.pages[0])
    writer.add_page(base_page)

    output_stream = io.BytesIO()
    writer.write(output_stream)
    output_stream.seek(0)
    return output_stream.read()


@app.get("/")
def index() -> str:
    return render_template(
        "index.html",
        zona_options=ZONE_OPTIONS,
        estado_civil_options=ESTADO_CIVIL_OPTIONS,
    )


@app.get("/api/ibge/ufs")
def api_ibge_ufs():
    try:
        return jsonify({"items": cached_ibge_ufs()})
    except requests.RequestException:
        return jsonify({"items": [], "error": "Falha ao consultar IBGE"}), 503


@app.get("/api/ibge/municipios/<uf>")
def api_ibge_municipios(uf: str):
    normalized_uf = (uf or "").strip().upper()
    if not re.fullmatch(r"[A-Z]{2}", normalized_uf):
        return jsonify({"items": [], "error": "UF inválida"}), 400

    try:
        municipios = cached_ibge_municipios(normalized_uf)
        return jsonify({"items": municipios})
    except requests.RequestException:
        return jsonify({"items": [], "error": "Falha ao consultar IBGE"}), 503


@app.get("/api/cep/<cep>")
def api_cep(cep: str):
    try:
        payload = lookup_cep(cep)
    except requests.RequestException:
        return jsonify({"item": None, "error": "Falha na consulta de CEP"}), 503

    if not payload:
        return jsonify({"item": None, "error": "CEP inválido ou não encontrado"}), 404
    return jsonify({"item": payload})


@app.post("/gerar-pdf")
def gerar_pdf():
    zona_eleitoral = request.form.get("zona_eleitoral", "").strip()
    if zona_eleitoral and zona_eleitoral not in ZONE_OPTIONS_SET:
        return "Zona eleitoral inválida.", 400

    estado_civil = request.form.get("estado_civil", "").strip().upper()
    if estado_civil and estado_civil not in ESTADO_CIVIL_OPTIONS_SET:
        return "Estado civil inválido.", 400

    municipio_estado = request.form.get("municipio_estado", "").strip()
    municipio = request.form.get("municipio", "").strip()
    uf = normalize_uf(request.form.get("uf", ""))

    if uf and municipio:
        try:
            if municipio not in cached_ibge_municipios(uf):
                return "Município não corresponde à UF selecionada.", 400
        except requests.RequestException:
            return "Não foi possível validar município/UF no IBGE.", 503

    cep = request.form.get("cep", "")
    normalized_cep = normalize_cep(cep)
    cep_payload: dict[str, str] = {}
    if re.fullmatch(r"\d{5}-\d{3}", normalized_cep):
        try:
            cep_payload = lookup_cep(normalized_cep)
        except requests.RequestException:
            cep_payload = {}

        cep_uf = normalize_uf(cep_payload.get("uf", ""))
        cep_municipio = (cep_payload.get("municipio") or "").strip()
        if not uf and cep_uf:
            uf = cep_uf
        if not municipio and cep_municipio:
            municipio = cep_municipio

    if not municipio_estado and municipio and uf:
        municipio_estado = f"{municipio} / {uf}"

    data = {
        "nome": request.form.get("nome", ""),
        "data_nasc": normalize_date(request.form.get("data_nasc", "")),
        "nome_social": request.form.get("nome_social", ""),
        "zona_eleitoral": zona_eleitoral,
        "municipio_estado": municipio_estado,
        "naturalidade": request.form.get("naturalidade", ""),
        "titulo_eleitor": request.form.get("titulo_eleitor", ""),
        "secao": request.form.get("secao", ""),
        "estado_civil": estado_civil,
        "pai": request.form.get("pai", ""),
        "mae": request.form.get("mae", ""),
        "endereco": request.form.get("endereco", ""),
        "bairro_setor": request.form.get("bairro_setor", ""),
        "cep": normalized_cep,
        "email": request.form.get("email", ""),
        "cpf": request.form.get("cpf", ""),
        "rg": request.form.get("rg", ""),
        "profissao": request.form.get("profissao", ""),
        "celular_whatsapp": request.form.get("celular_whatsapp", ""),
        "rede_social": request.form.get("rede_social", ""),
        "data_inscricao": normalize_date(request.form.get("data_inscricao", "")),
    }

    pdf_bytes = fill_pdf(data)
    return send_file(
        io.BytesIO(pdf_bytes),
        mimetype="application/pdf",
        as_attachment=False,
        download_name="ficha_preenchida_prd.pdf",
    )


if __name__ == "__main__":
    app.run(debug=True)
