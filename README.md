# Glamira Analytics Pipeline

[Tiếng Việt](README.md) | [English](README.en.md) | [日本語](README.ja.md)

Xây dựng luồng ELT data pipeline và Data Warehouse hoàn chỉnh với MongoDB, Python (Asyncio & curl-cffi), Google Cloud Storage, Cloud Functions, BigQuery, dbt và Looker Studio.

## Description

### Objective

**Glamira** là một công ty trang sức đa quốc gia. Sở hữu nền tảng e-commerce trải dài trên nhiều quốc gia với nhiều loại tiền tệ. Điều này khiến việc tổng hợp dữ liệu để xây dựng báo cáo trở nên khó khăn do bản chất dữ liệu bị lưu trữ phân tán tại nhiều nơi.

Mục tiêu của dự án này là xây dựng pipeline để vận chuyển dữ liệu sự kiện người dùng từ hệ thống web của **Glamira** vào data warehouse để chuẩn bị cho bước phân tích bằng Looker Studio.

Dự án sẽ lấy dữ liệu từ server (được giả lập bằng cách restore lên mongod của VM) và xây dựng pipeline tự động sử dụng cloud function trên GCP để đưa dữ liệu vào layer landing của warehouse. Trong quá trình này, tôi đã làm giàu thêm dữ liệu bằng cách sử dụng IP để lấy thêm thông tin về location. Đồng thời, tôi xác định các event có liên quan đến sản phẩm, trích xuất và lấy thông tin sản phẩm từ web. Mục tiêu của tôi là để xác định được doanh thu, top các sản phẩm bán được từ event thanh toán.

### Dataset

Dự án sử dụng bộ dữ liệu private xấp xỉ 41 triệu bản ghi có dung lượng 31,2GB. Dữ liệu nguồn bao gồm:

1. **Clickstream Event Logs (`countly.summary`)**:
   - Dữ liệu sự kiện người dùng được thu thập từ server web của Glamira.
   - Dữ liệu được lưu trữ dưới dạng bán cấu trúc với các trường dữ liệu lồng nhau.

2. **Catalog Metadata (Web Scraping)**:
   - Thông tin sản phẩm được lấy từ trang web Glamira từ product_id có trong dữ liệu clickstream.

3. **Geographic & Exchange Rate Datasets (API Calling)**:
   - **IP Geolocation**: Offline database [IP2Location LITE-DB5](https://lite.ip2location.com/) cung cấp thông tin về địa lý của khách hàng dựa trên địa chỉ IP.
   - **Historical FX Rates**: Dữ liệu tỷ giá hối đoái hàng ngày sang USD được lấy từ [Frankfurter API](https://www.frankfurter.app/) được ánh xạ với các tiêu chuẩn ISO 4217 bằng Google Gemini AI.

<p align="center">
  <img height="600" src="images/sample_document.png" alt="Sample Documents">
</p>

### Tools & Technologies

- Source Database - [**MongoDB**](https://www.mongodb.com)
- Cloud Platform - [**Google Cloud Platform (GCP)**](https://cloud.google.com)
- Data Lake - [**Google Cloud Storage (GCS)**](https://cloud.google.com/storage)
- Data Warehouse - [**BigQuery**](https://cloud.google.com/bigquery)
- Serverless Compute - [**Google Cloud Functions (2nd Gen)**](https://cloud.google.com/functions)
- Data Transformation - [**dbt (Data Build Tool)**](https://www.getdbt.com)
- Web Crawling & Scraping - [**curl-cffi**](https://github.com/yifeikong/curl_cffi) & [**Asyncio**](https://docs.python.org/3/library/asyncio.html)
- IP Geolocation - [**IP2Location**](https://www.ip2location.com)
- Foreign Exchange Rates - [**Frankfurter API**](https://www.frankfurter.app) & [**Google Gemini AI**](https://deepmind.google/technologies/gemini/)
- BI Tool - [**Google Looker Studio**](https://lookerstudio.google.com)
- Dependency & Package Management - [**Poetry**](https://python-poetry.org) & [**Python 3.11**](https://www.python.org)

### Architecture

Kiến trúc luồng dữ liệu end-to-end kết nối từ nguồn dữ liệu giao dịch, hệ thống serverless ingestion trên cloud, tầng biến đổi dữ liệu dbt đến báo cáo phân tích:

<p align="center">
  <img height="600" src="images/architecture.svg" alt="Glamira Pipeline Architecture">
</p>

### Data Modeling (Star Schema)

Mô hình Data Warehouse cốt lõi được thiết kế theo phương pháp **Ralph Kimball's Dimensional Modeling** với mô hình Star Schema kết hợp chiều dữ liệu SCD Type 2 để theo dõi thông tin khách hàng:

<p align="center">
  <img width="860" src="images/glamira_data_model.svg" alt="Glamira Star Schema Dimensional Model">
</p>

### Final Result

Các Data Mart phân tích trong BigQuery cung cấp dữ liệu cho dashboard theo dõi doanh thu và hiệu quả bán hàng trên **Google Looker Studio**:

<p align="center">
  <img width="900" src="images/looker_dashboard.png" alt="Glamira Looker Studio Dashboard">
</p>

### Key Takeaways

- **Xử lý dữ liệu lớn bán cấu trúc (31.2GB / 41M records):** Đọc cursor batch từ MongoDB để chống tràn RAM, ép kiểu dữ liệu lá BSON không đồng nhất và nén Snappy Parquet tối ưu chi phí lưu trữ trên Data Lake (GCS).
- **Thu thập dữ liệu catalog quy mô lớn:** Áp dụng `curl-cffi` giả lập Chrome TLS/JA3 fingerprint kết hợp `asyncio` bất đồng bộ để cào dữ liệu ổn định và hạn chế nguy cơ bị chặn bởi cơ chế Anti-Bot.
- **Mô hình hóa dữ liệu chuẩn Ralph Kimball:** Xây dựng Star Schema với kỹ thuật **SCD Type 2** (`dim_customer`) nhằm theo dõi lịch sử thay đổi thông tin khách hàng qua từng mốc thời gian.
- **Null-handle:**: Xử lý null cho bảng fact và bảng dim.
- **Tư duy thiết kế tầng Intermediate trong dbt:** Tách riêng tầng `intermediate` để tiền xử lý join IP - Location và chuẩn hóa dữ liệu trước khi ánh xạ Surrogate Key vào bảng `fact_sales_order_detail`.
- **Kiến thức chuyên sâu tích lũy qua dự án:**
  - Nắm vững các khái niệm cốt lõi về Data Warehouse: **Data Model**, **OLAP**, **Star Schema**, **SCD (Slowly Changing Dimension)** và kiến trúc phân tầng **Warehouse Layers**.
  - Hiểu sâu cấu trúc lưu trữ dạng cột (columnar storage) của file **Parquet** và cách thức Parquet biểu diễn, mã hóa dữ liệu.
  - Áp dụng các quy chuẩn viết code **dbt** clean để code dễ đọc, bảo trì.

---

## Setup

> **Warning**: Việc triển khai các dịch vụ trên Google Cloud Platform có thể phát sinh chi phí. Bạn có thể tận dụng gói credit dùng thử 300$ miễn phí cho tài khoản GCP mới.

### Pre-requisites

Trước khi bắt đầu, hãy đảm bảo bạn đã chuẩn bị sẵn các yêu cầu sau:

- Đã cài đặt **Python 3.11+** và **Poetry**.
- Một project trên **Google Cloud Platform (GCP)** đã kích hoạt billing.
- Một **GCP Service Account** được cấp các quyền IAM sau:
  - `Storage Admin`
  - `BigQuery Admin`
- Tải file JSON Service Account key và lưu tại: `config/service-account-key.json`.
- Quyền truy cập vào **MongoDB** chứa collection `countly.summary`.
- Tải file binary `IP2LOCATION-LITE-DB5.BIN` đặt vào thư mục: `data/ip2location/`.
- (Tùy chọn) **Google Gemini API Key** dùng cho việc map mã tiền tệ.

### Project Structure

```
glamira-crawl-product/
├── cloud_function/          # Serverless Eventarc trigger cho BigQuery ingestion
│   ├── main.py
│   └── requirements.txt
├── config/                  # Service account keys và cấu hình local
├── data/                    # IP2Location DB và file dữ liệu tạm
├── dbt/
│   └── glamira_warehouse/   # Dự án dbt (staging, intermediate, warehouse, looker)
│       ├── dbt_project.yml
│       ├── models/
│       ├── seeds/
│       └── packages.yml
├── glamira_crawl/           # Package CLI crawler và làm giàu dữ liệu
│   ├── crawler/             # Async catalog scraper với TLS fingerprinting
│   ├── enricher/            # Module geocoding và tỷ giá ngoại tệ
│   └── exporter/            # Chuẩn hóa schema và xuất Parquet
├── images/                  # Sơ đồ kiến trúc và ảnh dashboard
├── pyproject.toml           # Cấu hình thư viện Poetry và CLI entrypoints
└── README.md
```

### Get Going!

#### 1. Environment & Credentials Configuration

Clone repository và cài đặt các thư viện cần thiết bằng Poetry:

```bash
# 1. Cài đặt các thư viện cho crawler và pipeline
poetry install

# 2. Cài đặt các thư viện cho dbt
cd dbt
poetry install
cd glamira_warehouse && poetry run dbt deps && cd ../..
```

Tạo file `.env` ở thư mục gốc của dự án:

```env
# MongoDB Source
MONGODB_URI=mongodb://<HOST>:27017/?authSource=admin
MONGODB_USERNAME=your_username
MONGODB_PASSWORD=your_password
MONGODB_AUTH_SOURCE=admin

# Google Cloud Platform
GOOGLE_APPLICATION_CREDENTIALS=config/service-account-key.json
GCP_PROJECT_ID=your-gcp-project-id

# Gemini API (dùng cho việc map mã tiền tệ)
GEMINI_API_KEY=your_gemini_api_key
```

Cấu hình file `~/.dbt/profiles.yml` để dbt kết nối tới BigQuery:

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

Chạy CLI pipeline `glamira-crawl` để quét sự kiện, cào thông tin catalog sản phẩm còn thiếu, lấy tọa độ địa lý IP và chuẩn hóa tỷ giá tiền tệ:

```bash
# Quét và tìm các product_id và URL duy nhất từ MongoDB
poetry run glamira-crawl discover

# Cào metadata sản phẩm bất đồng bộ bằng curl-cffi với Chrome TLS fingerprint
poetry run glamira-crawl crawl

# Làm giàu thông tin vị trí từ IP và lấy tỷ giá ngoại tệ hàng ngày
poetry run glamira-crawl locations --workers 16
poetry run glamira-crawl exchange-rates

# Chuyển đổi định dạng sang Snappy Parquet và đẩy lên GCS Data Lake
poetry run glamira-crawl load
```

<p align="center">
  <img width="800" src="images/gcs_bucket.png" alt="Upload to Google Cloud Storage">
</p>

#### 3. Serverless Ingestion via Google Cloud Functions

Khi có file mới được tải lên Google Cloud Storage bucket (`gs://raw_glamira/`), Eventarc trigger sẽ kích hoạt Cloud Function thế hệ 2 (`trigger_bigquery_load`).

Hàm sẽ tự động sinh một Job ID mang tính idempotent (chống trùng lặp dữ liệu khi gửi lại event), khởi tạo BigQuery Load Job và nạp dữ liệu thô vào dataset `landing`:

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

Dự án áp dụng kiến trúc biến đổi dữ liệu phân tầng theo best practice của **dbt** (`staging` ➔ `intermediate` ➔ `warehouse` ➔ `looker`):

```bash
cd dbt/glamira_warehouse

# Nạp các bảng seed ánh xạ tiền tệ
poetry run dbt seed

# Chạy toàn bộ model từ staging views, warehouse tables đến looker marts
poetry run dbt run
```

Các đặc điểm chính của mô hình dữ liệu Dimensional:
- **Tối ưu hóa tầng Intermediate (`int_fact_sales_order_detail_normalize`)**:
  - **Vấn đề**: Để tạo khóa ngoại (Surrogate Keys) chính xác trong `fact_sales_order_detail`, mỗi bản ghi giao dịch cần có đầy đủ Business Keys tương ứng từ các dimension.
  - **Giải pháp**: Tách riêng tầng trung gian để chuẩn hóa dữ liệu và tiền join địa chỉ IP với `stg_dim_location` nhằm lấy thông tin vị trí địa lý, tuân theo best practice của dbt.

- **`fact_sales_order_detail`**: Bảng Fact ở mức chi tiết từng dòng đơn hàng (Line-item granularity), lưu số lượng mua, đơn giá tiền tệ gốc, tỷ giá hối đoái và doanh thu chuẩn hóa sang USD (`price_usd`, `subtotal_usd`).
- **`dim_customer` (SCD Type 2)**: Theo dõi lịch sử thay đổi thông tin định danh thiết bị, tài khoản người dùng và email liên hệ của khách hàng theo thời gian (`start_time`, `end_time`, `is_current`).
- **Surrogate Keys**: Sử dụng Surrogate Key dạng số nguyên được chuẩn hóa, tự động gán giá trị `-1` cho các bản ghi chưa xác định hoặc đến muộn (late-arriving records).

<p align="center">
  <img width="860" src="images/linage_graph.png" alt="dbt Lineage Graph">
</p>

#### 5. Data Quality Assurance & Governance

Chạy kiểm thử chất lượng dữ liệu tự động với `dbt test` và package `dbt_expectations`:

```bash
poetry run dbt test
```

- **Not-Null & Uniqueness**: Kiểm tra khóa chính Surrogate Key trên các bảng Fact và Dimension không bị null hoặc trùng lặp.
- **Compound Column Uniqueness**: Đảm bảo mỗi phiên bản khách hàng SCD Type 2 có cặp giá trị `(customer_device_id, start_time)` là duy nhất.
- **Referential Integrity**: Kiểm tra tính toàn vẹn tham chiếu, đảm bảo tất cả khóa ngoại trong Fact table đều tồn tại bên các bảng Dimension.
- **PII Governance**: Bảo vệ trường email nhạy cảm của khách hàng (`customer_email_address`) bằng BigQuery Data Catalog **Policy Tags** (`cus_email`) để kiểm soát quyền truy cập ở cấp độ cột (column-level security).

<p align="center">
  <img width="800" src="images/dbt_test_results.png" alt="dbt Test Results">
</p>

#### 6. BI & Analytics with Looker Studio

Kết nối **Google Looker Studio** với dataset phân tích `looker` trong BigQuery:
- `revenue_by_country`: Tổng hợp số lượng đơn hàng, tổng doanh thu và giá trị đơn hàng trung bình (AOV) theo từng quốc gia.
- `revenue_mom_analysis`: Phân tích doanh thu hàng tháng và tốc độ tăng trưởng so với tháng trước (Month-over-Month - MoM).
- `order_by_product`: Xác định các bộ sưu tập, chất liệu kim loại (vàng, bạc, bạch kim) và loại đá quý bán chạy nhất.
- `revenue_aov_customer_analysis`: Đánh giá tần suất mua hàng và giá trị vòng đời của khách hàng.

---

### How can I make this better?!

Một số hướng phát triển và tối ưu thêm trong tương lai :)
- [ ] **Giả lập việc dữ liệu tăng dần theo thời gian**. Từ đây, sử dụng tool như **Apache Airflow** hoặc **Prefect** để lập lịch chạy.  
- [ ] **Infrastructure as Code (IaC)**: Khởi tạo và quản lý toàn bộ hạ tầng GCP (GCS buckets, Eventarc triggers, Cloud Functions, BigQuery datasets) bằng **Terraform**.
- [ ] **CI/CD Automation**: Triển khai **GitHub Actions** để tự động linting, kiểm tra format SQL bằng `sqlfluff`, và chạy dbt CI test khi có Pull Request (PR).

---

### Special Mentions

- Em xin cám ơn anh Duy, anh Huy trong team [Unigap](google.com/search?q=unigap&oq=unigap+&gs_lcrp=EgZjaHJvbWUyBggAEEUYOTIHCAEQABiABDIHCAIQABiABDIGCAMQRRg8MgYIBBBFGDwyBggFEEUYPTIGCAYQRRg8MgYIBxBFGDzSAQgxNTk0ajBqN6gCALACAA&sourceid=chrome&source=chrome.ob&ie=UTF-8) đã support em trong quá trình làm dự án này.

- Đồng thời tôi cũng xin cám ơn các thành viên trong nhóm DEC-K25 đã không ngừng góp ý để dự án này được hoàn thiện hơn nữa.
