const form = document.getElementById("ficha-form");
const ufSelect = document.getElementById("uf");
const municipioSelect = document.getElementById("municipio");
const cepInput = document.getElementById("cep");
const enderecoInput = document.querySelector('input[name="endereco"]');
const bairroInput = document.querySelector('input[name="bairro_setor"]');
const naturalidadeInput = document.querySelector('input[name="naturalidade"]');
const municipioEstadoInput = document.getElementById("municipio_estado");
const statusMsg = document.getElementById("status-msg");

function setStatus(message, type = "") {
  statusMsg.textContent = message;
  statusMsg.classList.remove("ok", "error");
  if (type) {
    statusMsg.classList.add(type);
  }
}

async function fetchJson(url) {
  const response = await fetch(url);
  const payload = await response.json();
  if (!response.ok) {
    throw new Error(payload.error || "Falha na consulta");
  }
  return payload;
}

function clearSelect(selectElement, placeholder) {
  selectElement.innerHTML = "";
  const option = document.createElement("option");
  option.value = "";
  option.textContent = placeholder;
  selectElement.appendChild(option);
}

function fillUfSelect(items) {
  clearSelect(ufSelect, "Selecione...");
  items.forEach((item) => {
    const option = document.createElement("option");
    option.value = item.sigla;
    option.textContent = `${item.sigla} - ${item.nome}`;
    ufSelect.appendChild(option);
  });
}

function fillMunicipioSelect(items) {
  clearSelect(municipioSelect, "Selecione...");
  items.forEach((name) => {
    const option = document.createElement("option");
    option.value = name;
    option.textContent = name;
    municipioSelect.appendChild(option);
  });
}

async function loadUfs() {
  try {
    const payload = await fetchJson("/api/ibge/ufs");
    fillUfSelect(payload.items || []);
    setStatus("UFs carregadas do IBGE.", "ok");
  } catch (error) {
    clearSelect(ufSelect, "Falha ao carregar UFs");
    setStatus(error.message, "error");
  }
}

async function loadMunicipiosFromUf(uf) {
  if (!uf) {
    municipioSelect.disabled = true;
    clearSelect(municipioSelect, "Selecione uma UF primeiro");
    return;
  }

  municipioSelect.disabled = true;
  clearSelect(municipioSelect, "Carregando municípios...");

  try {
    const payload = await fetchJson(`/api/ibge/municipios/${uf}`);
    fillMunicipioSelect(payload.items || []);
    municipioSelect.disabled = false;
    setStatus("Municípios carregados do IBGE.", "ok");
  } catch (error) {
    clearSelect(municipioSelect, "Falha ao carregar municípios");
    setStatus(error.message, "error");
  }
}

function onlyDigits(value) {
  return (value || "").replace(/\D/g, "");
}

function formatCep(raw) {
  const digits = onlyDigits(raw).slice(0, 8);
  if (digits.length <= 5) return digits;
  return `${digits.slice(0, 5)}-${digits.slice(5)}`;
}

function formatCpf(raw) {
  const digits = onlyDigits(raw).slice(0, 11);
  if (digits.length <= 3) return digits;
  if (digits.length <= 6) return `${digits.slice(0, 3)}.${digits.slice(3)}`;
  if (digits.length <= 9) {
    return `${digits.slice(0, 3)}.${digits.slice(3, 6)}.${digits.slice(6)}`;
  }
  return `${digits.slice(0, 3)}.${digits.slice(3, 6)}.${digits.slice(6, 9)}-${digits.slice(9)}`;
}

async function lookupCep() {
  const digits = onlyDigits(cepInput.value);
  if (digits.length !== 8) {
    return;
  }

  try {
    const payload = await fetchJson(`/api/cep/${digits}`);
    const item = payload.item || {};
    cepInput.value = item.cep || formatCep(digits);
    if (item.logradouro && !enderecoInput.value.trim()) {
      enderecoInput.value = item.logradouro;
    }
    if (item.bairro && !bairroInput.value.trim()) {
      bairroInput.value = item.bairro;
    }
    if (item.uf) {
      ufSelect.value = item.uf;
      await loadMunicipiosFromUf(item.uf);
    }
    if (item.municipio) {
      municipioSelect.value = item.municipio;
      if (!naturalidadeInput.value.trim()) {
        naturalidadeInput.value = item.municipio;
      }
    }
    setStatus("CEP consultado com sucesso.", "ok");
  } catch (error) {
    setStatus("");
  }
}

function validateFormBeforeSubmit(event) {
  const uf = ufSelect.value;
  const municipio = municipioSelect.value;
  if (!uf || !municipio) {
    event.preventDefault();
    setStatus("Selecione UF e Município válidos pelo IBGE.", "error");
    return;
  }
  municipioEstadoInput.value = `${municipio} / ${uf}`;
}

ufSelect.addEventListener("change", (event) => {
  loadMunicipiosFromUf(event.target.value);
});

cepInput.addEventListener("input", () => {
  cepInput.value = formatCep(cepInput.value);
});

cepInput.addEventListener("blur", () => {
  if (onlyDigits(cepInput.value).length === 8) {
    lookupCep();
  }
});

const cpfInput = document.querySelector('input[name="cpf"]');
cpfInput.addEventListener("input", () => {
  cpfInput.value = formatCpf(cpfInput.value);
});

form.addEventListener("submit", validateFormBeforeSubmit);

loadUfs();
