# Glamira Analytics Pipeline V1.0

[Tiếng Việt](README.md) | [English](README.en.md) | [日本語](README.ja.md)

MongoDB、Python (Asyncio & curl-cffi)、Google Cloud Storage、Cloud Functions、BigQuery、dbt、Looker Studio を活用したエンドツーエンドの ELT データパイプラインとモダンデータウェアハウスの構築。

## Description

### Objective

**Glamira** は、世界数十カ国でローカライズされた多通貨対応のストアフロントを展開するグローバル高級ジュエリー Eコマース企業です。データが世界各国の拠点やサーバーに分散して保持されているため、全社的な統合分析レポートの作成が困難であるという課題を抱えていました。

本プロジェクトの目的は、**Glamira** の Web プラットフォームから発生するユーザーの行動イベント（クリックストリーム）および購買データを、Looker Studio による高度なビジネスインテリジェンス分析へ向けて、クラウド上のモダンデータウェアハウスへと自動連携する堅牢なデータパイプラインを構築することです。

本パイプラインでは、サーバー上の生データ（VM 上の MongoDB にリストアしてシミュレート）からデータを抽出し、GCP の Cloud Functions を利用したイベント駆動型サーバーレスアーキテクチャによって、Warehouse の Landing レイヤーへと自動ロードします。このプロセスにおいて、IP アドレスから位置情報（Location）を特定するジオコーディングによるデータ補完を行いました。さらに、商品に関連する閲覧・購入イベントを特定し、Web サイトからカタログ詳細メタデータを非同期スクレイピングで取得して紐付けを行いました。最終的な目標は、決済（Checkout）イベントから総売上高、国別の需要動向、および人気商品ランキングを正確に分析・可視化することです。

### Dataset

本プロジェクトでは、約 4,100 万件（非圧縮サイズ 31.2 GB）の大規模なプライベートデータセットを取り扱います。主なデータソースは以下の通りです：

1. **クリックスルーイベントログ (`countly.summary`)**:
   - Glamira の Web サーバーから収集されたリアルタイムのユーザー行動ログ。
   - 深くネストされたドキュメントと動的なスキーマ構造を持つ半構造化（BSON/JSON）データ。

2. **商品カタログメタデータ (Web Scraping)**:
   - クリックスルーデータ内の `product_id` をキーとして、Glamira 公式サイトからスクレイピングした商品属性（SKU、商品名、カテゴリ、貴金属の合金仕様、重量、価格帯など）。

3. **地理情報および為替レートデータ (API Calling)**:
   - **IP ジオロケーション**: オフラインデータベース [IP2Location LITE-DB5](https://lite.ip2location.com/) を利用し、訪問者の IP アドレスから国名、地域、都市、地理座標を高速解決。
   - **為替レート**: [Frankfurter API](https://www.frankfurter.app/) から取得した USD 換算の日次為替レートを、Google Gemini AI を用いて ISO 4217 通貨規格に高精度にマッピング。

<p align="center">
  <img height="600" src="images/sample_document.png" alt="Sample Documents">
</p>

### Tools & Technologies

- ソースデータベース - [**MongoDB**](https://www.mongodb.com)
- クラウドプラットフォーム - [**Google Cloud Platform (GCP)**](https://cloud.google.com)
- データレイク - [**Google Cloud Storage (GCS)**](https://cloud.google.com/storage)
- データウェアハウス - [**BigQuery**](https://cloud.google.com/bigquery)
- サーバーレスコンピューティング - [**Google Cloud Functions (2nd Gen)**](https://cloud.google.com/functions)
- データ変換 - [**dbt (Data Build Tool)**](https://www.getdbt.com)
- Web スクレイピング - [**curl-cffi**](https://github.com/yifeikong/curl_cffi) & [**Asyncio**](https://docs.python.org/3/library/asyncio.html)
- IP ジオロケーション - [**IP2Location**](https://www.ip2location.com)
- 為替レート連携 - [**Frankfurter API**](https://www.frankfurter.app) & [**Google Gemini AI**](https://deepmind.google/technologies/gemini/)
- BI ツール - [**Google Looker Studio**](https://lookerstudio.google.com)
- 依存関係・パッケージ管理 - [**Poetry**](https://python-poetry.org) & [**Python 3.11**](https://www.python.org)

### Architecture

エンドツーエンドのデータフローアーキテクチャは、トランザクションソース、サーバーレスクラウド取り込み、dbt によるデータ変換層、そして Looker Studio による分析ダッシュボードをシームレスに統合します：

<p align="center">
  <img height="600" src="images/architecture.svg" alt="Glamira Pipeline Architecture">
</p>

### Data Modeling (Star Schema)

データウェアハウスのコア層は、**Ralph Kimball のディメンショナルモデリング手法**に準拠し、顧客プロファイルの変更履歴を追跡する SCD タイプ 2 を備えたスタースキーマ（Star Schema）として設計されています：

<p align="center">
  <img width="860" src="images/glamira_data_model.svg" alt="Glamira Star Schema Dimensional Model">
</p>

### Final Result

BigQuery 上で構築された分析用データマート（Data Mart）は、**Google Looker Studio** で構築された経営意思決定用ダッシュボードにリアルタイムでデータを提供します：

<p align="center">
  <img width="900" src="images/looker_dashboard.png" alt="Glamira Looker Studio Dashboard">
</p>

### Key Takeaways

- **大規模な半構造化データ処理（31.2GB / 4,100 万件）:** MongoDB からのカーソルバッチ（Cursor Batch）読み込みによってメモリ溢れ（OOM）を防止し、不均一な BSON 葉ノードのデータ型を統一文字列に正規化。Snappy 圧縮 Parquet フォーマットへの変換により、データレイク（GCS）のストレージ費用を大幅に削減。
- **高スループットなカタログスクレイピング:** 正規の Chrome TLS/JA3 フィンガープリントをシミュレートする `curl-cffi` と `asyncio` による非同期並列ワーカーを活用し、Anti-Bot による遮断や Rate Limit（HTTP 429）を回避しながら安定してデータを抽出。
- **Ralph Kimball 準拠のディメンショナルモデリング:** 顧客プロファイルの属性変更履歴を正確に保持するため、**SCD タイプ 2**（`dim_customer`）を実装。
- **Null値の厳密なハンドリング:** ファクトテーブルおよびディメンションテーブルにおける欠損値・未確定値を体系的に処理し、未知のレコードにはサロゲートキー `-1` を割り当てて参照整合性を担保。
- **dbt における Intermediate 層の設計思考:** ビジネスロジックを分離し、`intermediate` 層で IP と位置情報の事前結合およびデータ整形を行うことで、最終ファクトテーブル（`fact_sales_order_detail`）へのサロゲートキー割り当てを最適化。
- **プロジェクトを通じて得られた専門的知見:**
  - データウェアハウスの基礎・応用概念の習得: **データモデル**、**OLAP**、**スタースキーマ**、**SCD（緩やかに変化するディメンション）**、**Warehouse Layers（多層アーキテクチャ）**。
  - **Parquet** ファイルの列指向（Columnar）内部構造、エンコーディング方式、および効率的な物理データ表現メカニズムの深い理解。
  - 保守性と可読性を最大化するための、モジュール化されたクリーンな **dbt** コード規約の実践。

---

## Setup

> **Warning**: Google Cloud Platform 上でリソースをプロビジョニングすると料金が発生する場合があります。新規 GCP アカウントの 300 ドル無料試用クレジットを活用できます。

### Pre-requisites

実行前に、以下の前提環境が整っていることを確認してください：

- **Python 3.11+** および **Poetry** のインストール。
- 課金が有効化された **Google Cloud Platform (GCP)** プロジェクト。
- 以下の IAM ロールが付与された **GCP Service Account**:
  - `Storage Admin` (ストレージ管理者)
  - `BigQuery Admin` (BigQuery 管理者)
- サービスアカウントキー（JSON）を `config/service-account-key.json` に配置。
- `countly.summary` コレクションが稼働している **MongoDB** インスタンスへの接続。
- `IP2LOCATION-LITE-DB5.BIN` をダウンロードし、`data/ip2location/` 配下に配置。
- (任意) 通貨コード正規化用の **Google Gemini API Key**。

### Project Structure

```
glamira-crawl-product/
├── cloud_function/          # BigQuery 取り込み用のサーバーレス Eventarc トリガー
│   ├── main.py
│   └── requirements.txt
├── config/                  # サービスアカウントキーおよびローカル設定ファイル
├── data/                    # IP2Location DB および一時データファイル
├── dbt/
│   └── glamira_warehouse/   # dbt プロジェクト (staging, intermediate, warehouse, looker)
│       ├── dbt_project.yml
│       ├── models/
│       ├── seeds/
│       └── packages.yml
├── glamira_crawl/           # クローラーおよびデータ補完用 CLI パッケージ
│   ├── crawler/             # TLS フィンガープリント対応の非同期カタログスクレイパー
│   ├── enricher/            # ジオコーディングおよび為替レート取得モジュール
│   └── exporter/            # スキーマ統一および Parquet エクスポート
├── images/                  # アーキテクチャ構成図およびダッシュボード画像
├── pyproject.toml           # Poetry 依存関係定義および CLI エントリポイント
└── README.md
```

### Get Going!

#### 1. Environment & Credentials Configuration

リポジトリをクローンし、Poetry を使用して依存関係をインストールします：

```bash
# 1. クローラーおよびパイプラインコアの依存関係をインストール
poetry install

# 2. dbt の依存関係をインストール
cd dbt
poetry install
cd glamira_warehouse && poetry run dbt deps && cd ../..
```

ルートディレクトリに `.env` ファイルを作成します：

```env
# MongoDB Source
MONGODB_URI=mongodb://<HOST>:27017/?authSource=admin
MONGODB_USERNAME=your_username
MONGODB_PASSWORD=your_password
MONGODB_AUTH_SOURCE=admin

# Google Cloud Platform
GOOGLE_APPLICATION_CREDENTIALS=config/service-account-key.json
GCP_PROJECT_ID=your-gcp-project-id

# Gemini API (通貨シードマッピング用)
GEMINI_API_KEY=your_gemini_api_key
```

dbt から BigQuery への接続設定のため、`~/.dbt/profiles.yml` を構成します：

```yaml
glamira_warehouse:
  target: dev
  outputs:
    dev:
      type: bigquery
      method: service-account
      keyfile: config/service-account-key.json
      project: your-gcp-project-id
      dataset: warehouse
      threads: 8
      location: asia-southeast1
      priority: interactive
```

<p align="center">
  <img width="800" src="images/gcp_setup.svg" alt="GCP IAM and Service Account Setup">
</p>

#### 2. Data Discovery, Web Crawling & Enrichment

`glamira-crawl` CLI パイプラインを実行して、イベントの検知、カタログデータのスクレイピング、IP ジオコーディング、為替レートの正規化を行います：

```bash
# MongoDB からユニークな product_id および URL を抽出
poetry run glamira-crawl discover

# Chrome TLS フィンガープリントを用いた curl-cffi による非同期メタデータスクレイピング
poetry run glamira-crawl crawl

# IP から位置情報を補完し、日次の為替レートを取得
poetry run glamira-crawl locations --workers 16
poetry run glamira-crawl exchange-rates

# Snappy 圧縮 Parquet に変換し、GCS データレイクへアップロード
poetry run glamira-crawl load
```

<p align="center">
  <img width="800" src="images/gcs_bucket.png" alt="Upload to Google Cloud Storage">
</p>

#### 3. Serverless Ingestion via Google Cloud Functions

Google Cloud Storage バケット（`gs://raw_glamira/`）にファイルがアップロードされると、Eventarc トリガーが第2世代の Cloud Function（`trigger_bigquery_load`）を自動起動します。

関数はイベント再送時の重複登録を防ぐために冪等（Idempotent）な Job ID を生成し、BigQuery ロードジョブを開始して生データを `landing` データセットに格納します：

```python
import functions_framework
from google.cloud import bigquery

client = bigquery.Client()

@functions_framework.cloud_event
def trigger_bigquery(cloud_event):
    data = cloud_event.data
    bucket = data["bucket"]
    file_name = data["name"]

    if not (file_name.endswith(".parquet") or file_name.endswith(".jsonl")):
        return

    job_config = bigquery.LoadJobConfig(
        source_format=bigquery.SourceFormat.PARQUET if file_name.endswith(".parquet") 
                      else bigquery.SourceFormat.NEWLINE_DELIMITED_JSON,
        write_disposition=bigquery.WriteDisposition.WRITE_APPEND,
    )
    uri = f"gs://{bucket}/{file_name}"
    table_id = f"{client.project}.landing.raw_mongo"
    load_job = client.load_table_from_uri(uri, table_id, job_config=job_config)
    load_job.result()
    print(f"Loaded {load_job.output_rows} rows from {uri}")
```

<p align="center">
  <img width="800" src="images/cloud_function_bigquery.svg" alt="Cloud Functions Ingestion to BigQuery">
</p>

#### 4. Transformations & Modeling with dbt

dbt のベストプラクティスに従い、レイヤー構造（`staging` ➔ `intermediate` ➔ `warehouse` ➔ `looker`）に沿って変換パイプラインを実行します：

```bash
cd dbt/glamira_warehouse

# 通貨マッピングのシードテーブルをロード
poetry run dbt seed

# ステージングビュー、ウェアハウスモデル、分析用マートを一括実行
poetry run dbt run
```

ディメンショナルモデルの主な特徴：
- **Intermediate 層の最適化 (`int_fact_sales_order_detail_normalize`)**:
  - **課題**: `fact_sales_order_detail` で代理キー（Surrogate Key）を正確に生成するには、各注文行にディメンションテーブルと結合可能なビジネスキーが揃っている必要があります。
  - **解決策**: 中間層（Intermediate）を独立させ、事前に IP アドレスと `stg_dim_location` を結合して位置情報を解決・正規化することで、データ品質と結合パフォーマンスを向上。

- **`fact_sales_order_detail`**: 注文明細単位の粒度（Line-item granularity）を保持し、購入数量、元通貨価格、適用為替レート、および USD 換算正規化売上高（`price_usd`, `subtotal_usd`）を格納。
- **`dim_customer` (SCD タイプ 2)**: 顧客のデバイス識別子、アカウント ID、連絡先メールアドレスの変更履歴を時系列で追跡（`start_time`, `end_time`, `is_current`）。
- **サロゲートキー (Surrogate Keys)**: 整数型の代理キーを採用し、未確定または遅延到着レコードにはデフォルト値 `-1` を自動割り当て。

<p align="center">
  <img width="860" src="images/linage_graph.png" alt="dbt Lineage Graph">
</p>

#### 5. Data Quality Assurance & Governance

`dbt test` および `dbt_expectations` パッケージを用いて、自動化されたデータ品質検証を実行します：

```bash
poetry run dbt test
```

- **Not-Null & Uniqueness**: ファクトテーブルおよびディメンションテーブルの主代理キーに null や重複が存在しないことを検証。
- **Compound Column Uniqueness**: SCD タイプ 2 の各顧客バージョンにおいて、`(customer_device_id, start_time)` の組み合わせが一意であることを保証。
- **Referential Integrity (参照整合性)**: ファクトテーブルのすべての外部キーがディメンションテーブルに存在する有効なキーであることを検証。
- **PII データガバナンス**: 顧客の個人情報（`customer_email_address`）を BigQuery Data Catalog の**ポリシー タグ（Policy Tags: `cus_email`）**で保護し、列レベルのアクセス制御・暗号化を実施。

<p align="center">
  <img width="800" src="images/dbt_test_results.png" alt="dbt Test Results">
</p>

#### 6. BI & Analytics with Looker Studio

**Google Looker Studio** を BigQuery の `looker` データセットに接続し、インタラクティブなダッシュボードを可視化します：
- `revenue_by_country`: 国別の注文数、総売上高、および平均客単価（AOV）の集計。
- `revenue_mom_analysis`: 月次売上推移および前月比成長率（Month-over-Month - MoM）の分析。
- `order_by_product`: 人気ジュエリーコレクション、貴金属種別（ゴールド、シルバー、プラチナ）、宝石バリエーション別の売上分析。
- `revenue_aov_customer_analysis`: 顧客ごとの購買頻度および顧客生涯価値（LTV）の評価。

---

### How can I make this better?!

今後のさらなる拡張・改善アイデア :)
- [ ] **データの時系列増分シミュレーション**: データの時間経過に伴う増加をシミュレートし、**Apache Airflow** や **Prefect** を導入して定期的なバッチ実行スケジュールを自動化。
- [ ] **Infrastructure as Code (IaC)**: **Terraform** を活用し、GCP 上の全インフラストラクチャ（GCS バケット、Eventarc トリガー、Cloud Functions、BigQuery データセット）をコードでプロビジョニング。
- [ ] **CI/CD 自動化**: **GitHub Actions** を組み込み、自動リンティング、`sqlfluff` による SQL フォーマット検証、プルリクエスト時の dbt CI テスト実行を自動化。

---

### Special Mentions

- 本プロジェクトの遂行にあたり、温かいご指導とサポートをいただきました [Unigap](https://unigap.edu.vn/) チームの Duy 氏および Huy 氏に心より感謝申し上げます。
- また、パイプラインのブラッシュアップに向けて貴重なフィードバックをいただいた DEC-K25 チームの仲間の皆様に深く御礼申し上げます。
