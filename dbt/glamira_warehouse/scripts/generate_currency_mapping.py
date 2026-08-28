"""Generate the dbt currency mapping seed with Gemini.

Run from the dbt project directory:
    python scripts/generate_currency_mapping.py
    dbt seed --select currency_mapping
    dbt build --select stg_currency
"""

from __future__ import annotations

import argparse
import csv
import json
import os
import re
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any

from dotenv import load_dotenv
from google.cloud import bigquery


DBT_PROJECT_DIR = Path(__file__).resolve().parents[1]
REPOSITORY_DIR = DBT_PROJECT_DIR.parents[1]
DEFAULT_OUTPUT = DBT_PROJECT_DIR / "seeds" / "currency_mapping.csv"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Generate an ISO 4217 currency mapping seed using Gemini."
    )
    parser.add_argument("--project", default="glamira-project-502214")
    parser.add_argument("--dataset", default="landing")
    parser.add_argument("--table", default="raw_mongo")
    parser.add_argument("--location", default="asia-southeast1")
    parser.add_argument(
        "--model", default=os.getenv("GEMINI_MODEL", "gemini-3.1-flash-lite")
    )
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    return parser.parse_args()


def fetch_currency_context(args: argparse.Namespace) -> list[dict[str, Any]]:
    table_id = f"{args.project}.{args.dataset}.{args.table}"
    query = f"""
        select
            trim(cart_product.currency) as raw_currency,
            count(*) as occurrences
        from `{table_id}` as raw
        cross join unnest(raw.cart_products) as cart_product
        where raw.collection = 'checkout_success'
          and nullif(trim(cart_product.currency), '') is not null
        group by raw_currency
        order by occurrences desc
    """
    client = bigquery.Client(project=args.project, location=args.location)
    return [dict(row) for row in client.query(query, location=args.location).result()]


def build_prompt(context: list[dict[str, Any]]) -> str:
    payload = json.dumps(context, ensure_ascii=False, separators=(",", ":"))
    return f"""
Map the aggregated Glamira checkout currency values below to ISO 4217 currencies.
Return JSON only: an array of objects with exactly these string fields:
raw_currency, currency_code, currency_name.

Rules:
- currency_code must be an uppercase ISO 4217 alpha-3 code.
- currency_name must be the official English currency name.
- Emit at most one mapping for each raw_currency value.
- Decide the most likely currency using raw_currency only. Do not use domains or
  emit multiple country-specific mappings for ambiguous symbols.
- Ignore local, dev, stage, empty, or insufficiently supported contexts.
- Never invent a raw_currency value that is absent from the input.
- Do not include markdown or explanations.

Input:
{payload}
""".strip()


def call_gemini(api_key: str, model: str, prompt: str) -> list[dict[str, str]]:
    endpoint = (
        "https://generativelanguage.googleapis.com/v1beta/models/"
        f"{model}:generateContent"
    )
    body = json.dumps(
        {
            "contents": [{"parts": [{"text": prompt}]}],
            "generationConfig": {"responseMimeType": "application/json"},
        }
    ).encode("utf-8")
    request = urllib.request.Request(
        endpoint,
        data=body,
        headers={
            "Content-Type": "application/json",
            "x-goog-api-key": api_key,
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=120) as response:
            result = json.load(response)
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"Gemini API returned HTTP {exc.code}: {detail}") from exc

    try:
        text = result["candidates"][0]["content"]["parts"][0]["text"]
        mappings = json.loads(text)
    except (KeyError, IndexError, TypeError, json.JSONDecodeError) as exc:
        raise RuntimeError("Gemini returned an invalid JSON response") from exc
    if not isinstance(mappings, list):
        raise RuntimeError("Gemini response must be a JSON array")
    return mappings


def validate_mappings(
    mappings: list[dict[str, str]], context: list[dict[str, Any]]
) -> list[dict[str, str]]:
    observed = {item["raw_currency"] for item in context}
    validated: dict[str, dict[str, str]] = {}
    required = {"raw_currency", "currency_code", "currency_name"}

    for row in mappings:
        if not isinstance(row, dict) or set(row) != required:
            raise ValueError(f"Invalid mapping shape: {row!r}")
        clean = {key: str(row[key]).strip() for key in required}
        raw_currency = clean["raw_currency"]
        code = clean["currency_code"].upper()
        if raw_currency not in observed:
            raise ValueError(f"Gemini invented raw currency: {raw_currency!r}")
        if not re.fullmatch(r"[A-Z]{3}", code):
            raise ValueError(f"Invalid ISO currency code: {code!r}")
        clean["currency_code"] = code
        if raw_currency in validated and validated[raw_currency] != clean:
            raise ValueError(
                f"Conflicting Gemini mappings for {raw_currency!r}"
            )
        validated[raw_currency] = clean

    return sorted(
        validated.values(),
        key=lambda row: (row["currency_code"], row["raw_currency"]),
    )


def write_seed(rows: list[dict[str, str]], output: Path) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = output.with_suffix(output.suffix + ".tmp")
    columns = ["raw_currency", "currency_code", "currency_name"]
    with temporary.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=columns)
        writer.writeheader()
        writer.writerows(rows)
    temporary.replace(output)


def main() -> None:
    load_dotenv(REPOSITORY_DIR / ".env")
    args = parse_args()
    api_key = os.getenv("GEMINI_API_KEY")
    if not api_key:
        raise RuntimeError(f"GEMINI_API_KEY is missing from {REPOSITORY_DIR / '.env'}")

    context = fetch_currency_context(args)
    mappings = call_gemini(api_key, args.model, build_prompt(context))
    validated = validate_mappings(mappings, context)
    if not validated:
        raise RuntimeError("Gemini returned no valid currency mappings")
    write_seed(validated, args.output)
    print(f"Wrote {len(validated)} mappings to {args.output}")


if __name__ == "__main__":
    main()
