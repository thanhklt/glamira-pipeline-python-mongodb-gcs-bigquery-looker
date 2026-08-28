from __future__ import annotations

import json
import logging
import os
import tempfile
import time
from collections.abc import Callable, Iterable, Iterator
from dataclasses import dataclass
from datetime import date, datetime
from pathlib import Path
from typing import Any
from urllib.parse import urlencode

from curl_cffi import requests
from pymongo import MongoClient
from pymongo.read_preferences import SecondaryPreferred

from config.config import Settings


logger = logging.getLogger(__name__)

PROJECT_ROOT = Path(__file__).resolve().parent.parent
API_URL = "https://api.frankfurter.dev/v2/rates"
BASE_CURRENCY = "USD"
OUTPUT_PATH = PROJECT_ROOT / "data" / "exchange_rate.jsonl"
CHECKOUT_COLLECTION = "checkout_success"
REQUEST_TIMEOUT_SECONDS = 30.0
CURL_IMPERSONATE = "chrome"
USER_AGENT = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
    "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/136.0.0.0 Safari/537.36"
)
MAX_RETRIES = 3
RETRY_BACKOFF_SECONDS = 1.0
RETRY_HTTP_STATUSES = frozenset({429, 500, 502, 503, 504})
MONGO_PROGRESS_EVERY = 10_000


@dataclass
class ExchangeRateStats:
    scanned: int = 0
    unique_dates: int = 0
    invalid_dates: int = 0
    duplicate_dates: int = 0
    written: int = 0


class DownloadError(RuntimeError):
    def __init__(self, message: str, status_code: int | None = None) -> None:
        super().__init__(message)
        self.status_code = status_code


def normalize_local_date(value: Any) -> str | None:
    if isinstance(value, datetime):
        return value.date().isoformat()
    if isinstance(value, date):
        return value.isoformat()
    if not isinstance(value, str):
        return None
    candidate = value.strip()[:10]
    try:
        return date.fromisoformat(candidate).isoformat()
    except ValueError:
        return None


def unique_local_dates(values: Iterable[Any], stats: ExchangeRateStats) -> list[str]:
    dates: set[str] = set()
    for value in values:
        stats.scanned += 1
        local_date = normalize_local_date(value)
        if local_date is None:
            stats.invalid_dates += 1
            logger.debug("Invalid local_time skipped | value=%r", value)
        elif local_date in dates:
            stats.duplicate_dates += 1
        else:
            dates.add(local_date)
        if stats.scanned % MONGO_PROGRESS_EVERY == 0:
            logger.info(
                "MongoDB scan progress | scanned=%s | unique_dates=%s | invalid=%s | duplicates=%s",
                f"{stats.scanned:,}",
                f"{len(dates):,}",
                f"{stats.invalid_dates:,}",
                f"{stats.duplicate_dates:,}",
            )
    result = sorted(dates)
    stats.unique_dates = len(result)
    return result


def _mongo_client_options(settings: Settings) -> dict[str, Any]:
    options: dict[str, Any] = {
        "read_preference": SecondaryPreferred(),
        "appname": "glamira-exchange-rate-exporter",
    }
    if settings.mongo_username:
        options["username"] = settings.mongo_username
    if settings.mongo_password:
        options["password"] = settings.mongo_password
    if settings.mongo_username or settings.mongo_password:
        options["authSource"] = settings.mongo_auth_source
    return options


def _mongo_local_time_values(settings: Settings) -> Iterator[Any]:
    query = {"collection": CHECKOUT_COLLECTION}
    projection = {"_id": 0, "local_time": 1}
    logger.info(
        "Starting MongoDB scan | database=%s | collection=%s | filter_collection=%s",
        settings.mongo_db,
        settings.mongo_collection,
        CHECKOUT_COLLECTION,
    )
    with MongoClient(settings.mongo_uri, **_mongo_client_options(settings)) as client:
        collection = client[settings.mongo_db][settings.mongo_collection]
        cursor = collection.find(query, projection=projection).batch_size(settings.mongo_batch_size)
        for document in cursor:
            yield document.get("local_time")


def _download_json(url: str, timeout: float) -> Any:
    try:
        response = requests.get(
            url,
            headers={"Accept": "application/json", "User-Agent": USER_AGENT},
            timeout=timeout,
            impersonate=CURL_IMPERSONATE,
        )
    except requests.RequestsError as exc:
        raise DownloadError(f"network error: {exc}") from exc

    if response.status_code >= 400:
        response_preview = response.text[:500].replace("\r", " ").replace("\n", " ")
        raise DownloadError(
            f"HTTP {response.status_code}; response={response_preview!r}",
            status_code=response.status_code,
        )
    try:
        return response.json()
    except (TypeError, ValueError) as exc:
        raise DownloadError(f"invalid JSON response: {exc}") from exc


def fetch_exchange_rates(
    local_date: str,
    *,
    download: Callable[[str, float], Any] = _download_json,
    sleep: Callable[[float], None] = time.sleep,
) -> dict[str, Any]:
    url = f"{API_URL}?{urlencode({'base': BASE_CURRENCY, 'date': local_date})}"
    logger.info("Requesting Frankfurter rates | date=%s | base=%s", local_date, BASE_CURRENCY)
    payload: Any = None
    for attempt in range(1, MAX_RETRIES + 1):
        try:
            payload = download(url, REQUEST_TIMEOUT_SECONDS)
            break
        except DownloadError as exc:
            is_retryable = exc.status_code is None or exc.status_code in RETRY_HTTP_STATUSES
            if not is_retryable or attempt == MAX_RETRIES:
                raise RuntimeError(
                    f"Frankfurter request failed for {local_date}: {exc}"
                ) from exc
        delay = RETRY_BACKOFF_SECONDS * (2 ** (attempt - 1))
        logger.warning(
            "Frankfurter request failed; retrying | date=%s | attempt=%s/%s | delay=%.1fs",
            local_date,
            attempt,
            MAX_RETRIES,
            delay,
        )
        sleep(delay)

    if not isinstance(payload, list):
        raise ValueError(f"Frankfurter response for {local_date} must be an array")

    rates: dict[str, int | float] = {}
    for row in payload:
        if not isinstance(row, dict):
            raise ValueError(f"Frankfurter response for {local_date} contains an invalid row")
        quote = row.get("quote")
        rate = row.get("rate")
        if (
            not isinstance(quote, str)
            or not quote
            or isinstance(rate, bool)
            or not isinstance(rate, (int, float))
        ):
            raise ValueError(f"Frankfurter response for {local_date} contains an invalid rate")
        rates[quote] = rate

    if not rates:
        raise ValueError(f"Frankfurter returned no rates for {local_date}")
    logger.info(
        "Frankfurter rates received | date=%s | base=%s | rates=%s",
        local_date,
        BASE_CURRENCY,
        f"{len(rates):,}",
    )
    return {"date": local_date, "base": BASE_CURRENCY, "rates": dict(sorted(rates.items()))}


def write_exchange_rates(
    dates: Iterable[str],
    *,
    output_path: Path = OUTPUT_PATH,
    fetch: Callable[[str], dict[str, Any]] = fetch_exchange_rates,
    stats: ExchangeRateStats | None = None,
) -> ExchangeRateStats:
    stats = stats or ExchangeRateStats()
    date_list = list(dates)
    total_dates = len(date_list)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    logger.info(
        "Starting exchange-rate export | dates=%s | output=%s",
        f"{total_dates:,}",
        output_path,
    )
    temporary_path: Path | None = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="w",
            encoding="utf-8",
            newline="\n",
            dir=output_path.parent,
            prefix=f".{output_path.name}.",
            suffix=".tmp",
            delete=False,
        ) as handle:
            temporary_path = Path(handle.name)
            for position, local_date in enumerate(date_list, start=1):
                record = fetch(local_date)
                handle.write(json.dumps(record, ensure_ascii=False, separators=(",", ":")))
                handle.write("\n")
                stats.written += 1
                logger.info(
                    "Exchange-rate progress | completed=%s/%s | date=%s",
                    f"{position:,}",
                    f"{total_dates:,}",
                    local_date,
                )
            handle.flush()
            os.fsync(handle.fileno())
        temporary_path.replace(output_path)
        logger.info(
            "Exchange-rate file replaced successfully | rows=%s | output=%s",
            f"{stats.written:,}",
            output_path,
        )
    except Exception:
        if temporary_path is not None:
            temporary_path.unlink(missing_ok=True)
        raise
    return stats


def export_exchange_rates(settings: Settings) -> ExchangeRateStats:
    stats = ExchangeRateStats()
    try:
        dates = unique_local_dates(_mongo_local_time_values(settings), stats)
        logger.info(
            "MongoDB scan completed | scanned=%s | unique_dates=%s | invalid=%s | duplicates=%s",
            f"{stats.scanned:,}",
            f"{stats.unique_dates:,}",
            f"{stats.invalid_dates:,}",
            f"{stats.duplicate_dates:,}",
        )
        result = write_exchange_rates(dates, stats=stats)
        logger.info("Exchange-rate export completed | rows=%s", f"{result.written:,}")
        return result
    except Exception:
        logger.exception(
            "Exchange-rate export failed | scanned=%s | unique_dates=%s | written=%s",
            f"{stats.scanned:,}",
            f"{stats.unique_dates:,}",
            f"{stats.written:,}",
        )
        raise
