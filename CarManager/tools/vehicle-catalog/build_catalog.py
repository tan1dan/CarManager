#!/usr/bin/env python3
"""Builds the on-device brand/model catalog used by the vehicle editor.

Source: https://github.com/gor3a/vehicle-makes-models (data under ODbL 1.0), compiled by
that project from publicly available information on autoevolution.com.

The output is an adapted database, so it is itself offered under ODbL 1.0 — see
THIRD_PARTY_NOTICES.md at the repository root. The pinned commit keeps rebuilds
reproducible; bump it deliberately and review the diff of the generated JSON.

Usage: python3 tools/vehicle-catalog/build_catalog.py
"""

import csv
import io
import json
import re
import subprocess
import unicodedata
from pathlib import Path

SOURCE_REPO = "https://github.com/gor3a/vehicle-makes-models"
SOURCE_COMMIT = "b4965631140fa82404359167621274601da69a5b"
SOURCE_URL = (
    "https://raw.githubusercontent.com/gor3a/vehicle-makes-models/"
    f"{SOURCE_COMMIT}/data/csv/makes-models.csv"
)

OUTPUT = Path(__file__).resolve().parents[2] / "CarManager" / "Resources" / "VehicleCatalog.json"

# Shown above the alphabetical list, the way classifieds sites pin their most-listed brands.
# App curation, not data from the source.
POPULAR = [
    "Audi", "BMW", "Ford", "Hyundai", "Kia", "Mercedes-Benz", "Opel",
    "Peugeot", "Renault", "Škoda", "Toyota", "Volkswagen",
]

# Other names people search by: common abbreviations and Cyrillic spellings (OLX/AUTO.RIA
# users type "Шкода", "БМВ", "VW"). App curation, not data from the source.
ALIASES = {
    "Audi": ["Ауди"], "BMW": ["БМВ"], "Chery": ["Чери"], "Chevrolet": ["Шевроле", "Chevy"],
    "Citroën": ["Ситроен"], "Dacia": ["Дачия"], "Fiat": ["Фиат"], "Ford": ["Форд"],
    "Geely": ["Джили"], "Haval": ["Хавал"], "Honda": ["Хонда"],
    "Hyundai": ["Хендай", "Хюндай", "Хундай"], "Jeep": ["Джип"], "Kia": ["Киа"],
    "Lada": ["Лада", "ВАЗ", "VAZ"], "Land Rover": ["Ленд Ровер", "Лэнд Ровер"],
    "Lexus": ["Лексус"], "Mazda": ["Мазда"],
    "Mercedes-Benz": ["Мерседес", "Mercedes", "Merc", "MB"],
    "Mitsubishi": ["Мицубиси", "Митсубиши"], "Nissan": ["Ниссан"], "Opel": ["Опель"],
    "Peugeot": ["Пежо"], "Porsche": ["Порше"], "Renault": ["Рено"], "SEAT": ["Сеат"],
    "Subaru": ["Субару"], "Suzuki": ["Сузуки"], "Tesla": ["Тесла"], "Toyota": ["Тойота"],
    "Volkswagen": ["Фольксваген", "VW"], "Volvo": ["Вольво"], "Škoda": ["Шкода", "Skoda"],
}

# Words that are acronyms and must stay upper-case when a shouted name is re-cased.
KEEP_UPPER = {"GT", "GTI", "GTS", "RS", "SUV", "EV", "AMG", "CS", "CSL", "MCV", "DTM", "LWB", "SWB"}


def fold(text: str) -> str:
    """Case- and diacritic-insensitive key: 'Škoda' and 'skoda' collide."""
    decomposed = unicodedata.normalize("NFKD", text)
    return "".join(c for c in decomposed if not unicodedata.combining(c)).casefold()


def loose(text: str) -> str:
    return fold(text).replace("-", " ")


def clean_model(name: str, brand: str) -> str:
    name = re.sub(r"\s+", " ", name).strip()
    # Some brands repeat themselves: "Skoda Octavia" under Škoda -> "Octavia",
    # "Mercedes Benz EQA" under Mercedes-Benz -> "EQA". Hyphens and spaces compare equal.
    prefix = loose(brand) + " "
    if loose(name).startswith(prefix) and len(name) > len(prefix):
        name = name[len(prefix):].strip()
    # The source mixes German and English class names and appends lineage notes:
    # "E-Klasse and predecessors", "GLC Class", "A-Class" -> "E-Class", "GLC-Class", "A-Class".
    name = re.sub(r"\s+and predecessors$", "", name)
    name = re.sub(r"[- ](Klasse|Class|KLASSE|CLASS)\b", "-Class", name)
    name = re.sub(r"-{2,}", "-", name).strip(" /")  # "GLS--Class", "Astra Twin Top/"
    name = re.sub(r"\s*/\s*", "/", name)  # "80/ 90" -> "80/90"
    # "JOGGER" -> "Jogger", but leave "SQ8", "GTI", "iX3" alone.
    words = []
    for word in name.split(" "):
        if word.isalpha() and word.isupper() and len(word) > 3 and word not in KEEP_UPPER:
            word = word.capitalize()
        words.append(word)
    return " ".join(words)


def year(value: str):
    value = value.strip()
    return int(value) if value.isdigit() else None


def main() -> None:
    # curl rather than urllib: python.org builds on macOS ship without a CA bundle.
    text = subprocess.run(
        ["curl", "-fsSL", "--max-time", "60", SOURCE_URL],
        check=True, capture_output=True, text=True,
    ).stdout

    brands: dict[str, dict] = {}
    for row in csv.DictReader(io.StringIO(text)):
        brand_name = row["make"].strip()
        model_name = clean_model(row["model"], brand_name)
        if not brand_name or not model_name:
            continue

        brand = brands.setdefault(fold(brand_name), {"name": brand_name, "models": {}})
        key = fold(model_name)
        start, end = year(row["year_start"]), year(row["year_end"])
        existing = brand["models"].get(key)
        if existing:
            # Duplicate after cleaning: widen the production range instead of listing twice.
            if start and (existing["from"] is None or start < existing["from"]):
                existing["from"] = start
            if existing["to"] is not None and (end is None or end > existing["to"]):
                existing["to"] = end
        else:
            brand["models"][key] = {"name": model_name, "from": start, "to": end}

    popular = {fold(name) for name in POPULAR}
    missing = (popular | {fold(name) for name in ALIASES}) - brands.keys()
    if missing:
        raise SystemExit(f"Curated brands missing from source: {sorted(missing)}")
    aliases = {fold(name): names for name, names in ALIASES.items()}

    catalog = {
        "source": {
            "name": "vehicle-makes-models",
            "url": SOURCE_REPO,
            "commit": SOURCE_COMMIT,
            "upstream": "autoevolution.com",
            "license": "ODbL-1.0",
        },
        "brands": [
            {
                "name": brand["name"],
                "popular": key in popular,
                "aliases": aliases.get(key, []),
                "models": sorted(brand["models"].values(), key=lambda m: fold(m["name"])),
            }
            for key, brand in sorted(brands.items())
        ],
    }

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(json.dumps(catalog, ensure_ascii=False, separators=(",", ":")) + "\n")
    model_count = sum(len(b["models"]) for b in catalog["brands"])
    print(f"{len(catalog['brands'])} brands, {model_count} models -> {OUTPUT}")


if __name__ == "__main__":
    main()
