import json
import tempfile
import unittest
from datetime import date, datetime
from pathlib import Path
from unittest.mock import patch

from glamira_crawl.exchange_rates import (
    BASE_CURRENCY,
    CHECKOUT_COLLECTION,
    DownloadError,
    ExchangeRateStats,
    _mongo_local_time_values,
    fetch_exchange_rates,
    normalize_local_date,
    unique_local_dates,
    write_exchange_rates,
)


class ExchangeRateTests(unittest.TestCase):
    def test_mongo_query_filters_checkout_success_and_only_reads_local_time(self):
        calls = {}

        class Cursor:
            def batch_size(self, value):
                calls["batch_size"] = value
                return iter([{"local_time": "2020-06-04 11:21:24"}])

        class Collection:
            def find(self, query, projection):
                calls["query"] = query
                calls["projection"] = projection
                return Cursor()

        class Database:
            def __getitem__(self, name):
                calls["collection_name"] = name
                return Collection()

        class Client:
            def __init__(self, uri, **options):
                calls["uri"] = uri
                calls["options"] = options

            def __enter__(self):
                return self

            def __exit__(self, *_args):
                return None

            def __getitem__(self, name):
                calls["database_name"] = name
                return Database()

        settings = type(
            "SettingsStub",
            (),
            {
                "mongo_uri": "mongodb://example",
                "mongo_username": None,
                "mongo_password": None,
                "mongo_auth_source": "admin",
                "mongo_db": "countly",
                "mongo_collection": "summary",
                "mongo_batch_size": 2000,
            },
        )()

        with patch("glamira_crawl.exchange_rates.MongoClient", Client):
            values = list(_mongo_local_time_values(settings))

        self.assertEqual(values, ["2020-06-04 11:21:24"])
        self.assertEqual(calls["query"], {"collection": CHECKOUT_COLLECTION})
        self.assertEqual(calls["projection"], {"_id": 0, "local_time": 1})
        self.assertEqual(calls["database_name"], "countly")
        self.assertEqual(calls["collection_name"], "summary")
        self.assertEqual(calls["batch_size"], 2000)

    def test_normalizes_supported_local_time_values(self):
        self.assertEqual(normalize_local_date("2020-06-04 11:21:24"), "2020-06-04")
        self.assertEqual(normalize_local_date("2020-06-04T11:21:24"), "2020-06-04")
        self.assertEqual(normalize_local_date(datetime(2020, 6, 4, 11, 21)), "2020-06-04")
        self.assertEqual(normalize_local_date(date(2020, 6, 4)), "2020-06-04")

    def test_rejects_invalid_local_time_values(self):
        for value in (None, "", "2020-99-04 11:21:24", 1591266086):
            with self.subTest(value=value):
                self.assertIsNone(normalize_local_date(value))

    def test_deduplicates_and_sorts_dates(self):
        stats = ExchangeRateStats()
        result = unique_local_dates(
            ["2020-06-05 01:00:00", "bad", "2020-06-04 11:21:24", "2020-06-04 20:00:00"],
            stats,
        )
        self.assertEqual(result, ["2020-06-04", "2020-06-05"])
        self.assertEqual(stats.scanned, 4)
        self.assertEqual(stats.unique_dates, 2)
        self.assertEqual(stats.invalid_dates, 1)
        self.assertEqual(stats.duplicate_dates, 1)

    def test_fetches_all_quotes_and_groups_them_by_date(self):
        requested_urls = []

        def download(url, timeout):
            requested_urls.append((url, timeout))
            return [
                {"date": "2020-06-04", "base": "USD", "quote": "EUR", "rate": 0.89},
                {"date": "2020-06-04", "base": "USD", "quote": "AUD", "rate": 1.44},
            ]

        result = fetch_exchange_rates("2020-06-04", download=download)

        self.assertEqual(
            result,
            {"date": "2020-06-04", "base": BASE_CURRENCY, "rates": {"AUD": 1.44, "EUR": 0.89}},
        )
        self.assertIn("base=USD", requested_urls[0][0])
        self.assertIn("date=2020-06-04", requested_urls[0][0])

    def test_retries_transient_http_errors(self):
        attempts = 0
        delays = []

        def download(_url, _timeout):
            nonlocal attempts
            attempts += 1
            if attempts < 3:
                raise DownloadError("HTTP 503", status_code=503)
            return [{"date": "2020-06-04", "base": "USD", "quote": "EUR", "rate": 0.89}]

        fetch_exchange_rates("2020-06-04", download=download, sleep=delays.append)

        self.assertEqual(attempts, 3)
        self.assertEqual(delays, [1.0, 2.0])

    def test_does_not_retry_forbidden_response(self):
        attempts = 0

        def download(_url, _timeout):
            nonlocal attempts
            attempts += 1
            raise DownloadError("HTTP 403; response='blocked by Cloudflare'", status_code=403)

        with self.assertRaisesRegex(RuntimeError, "blocked by Cloudflare"):
            fetch_exchange_rates("2020-06-04", download=download, sleep=lambda _delay: None)

        self.assertEqual(attempts, 1)

    def test_writes_one_line_per_date_and_overwrites_existing_file(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "exchange_rate.jsonl"
            output.write_text("old data\n", encoding="utf-8")

            stats = write_exchange_rates(
                ["2020-06-04", "2020-06-05"],
                output_path=output,
                fetch=lambda value: {"date": value, "base": "USD", "rates": {"EUR": 0.89}},
            )

            rows = [json.loads(line) for line in output.read_text(encoding="utf-8").splitlines()]
            self.assertEqual([row["date"] for row in rows], ["2020-06-04", "2020-06-05"])
            self.assertEqual(stats.written, 2)

    def test_preserves_existing_file_when_fetch_fails(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "exchange_rate.jsonl"
            output.write_text("old data\n", encoding="utf-8")

            def fail(_value):
                raise RuntimeError("API failed")

            with self.assertRaises(RuntimeError):
                write_exchange_rates(["2020-06-04"], output_path=output, fetch=fail)

            self.assertEqual(output.read_text(encoding="utf-8"), "old data\n")
            self.assertEqual(list(Path(directory).glob("*.tmp")), [])


if __name__ == "__main__":
    unittest.main()
