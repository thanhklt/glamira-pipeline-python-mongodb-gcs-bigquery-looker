# Glamira E-Commerce End-to-End Data Pipeline & Modern Data Warehouse

<!-- > **Hệ thống ELT & Modern Data Warehouse toàn diện cho nền tảng thương mại điện tử trang sức quốc tế Glamira:** Thu thập clickstream events từ MongoDB, làm giàu dữ liệu sản phẩm qua web crawler (bypass anti-bot), tra cứu vị trí địa lý từ IP và tỷ giá hối đoái lịch sử, tự động ingest lên Google Cloud Storage & BigQuery qua Serverless Cloud Functions, mô hình hóa dữ liệu chuẩn Kimball (Star Schema, SCD Type 2) bằng dbt và trực quan hóa các chỉ số kinh doanh trên Looker Studio. -->

---

## 📑 Table of Contents

- [📌 Project Overview](#-project-overview)
  - [Pipeline giải quyết bài toán gì?](#pipeline-giải-quyết-bài-toán-gì)
- [🏛️ Architecture](#️-architecture)
  - [Sơ đồ kiến trúc (Architecture Diagram)](#sơ-đồ-kiến-trúc-architecture-diagram)
  - [Chi tiết các giai đoạn](#chi-tiết-các-giai-đoạn)
- [🛠️ Tech Stack](#️-tech-stack)
- [📂 Project Structure](#-project-structure)
- [⚙️ Setup & Installation](#️-setup--installation)
  - [Yêu cầu hệ thống](#yêu-cầu-hệ-thống)
  - [Cài đặt môi trường](#cài-đặt-môi-trường)
  - [Chuẩn bị file nhị phân IP2Location](#chuẩn-bị-file-nhị-phân-ip2location)
  - [Thiết lập biến môi trường (.env)](#thiết-lập-biến-môi-trường-env)
  - [Cấu hình dbt Profile](#cấu-hình-dbt-profile)
- [🚀 How to Run](#-how-to-run)
- [🧩 Data Model](#-data-model)
  - [Bảng Fact (Fact Tables)](#bảng-fact-fact-tables)
  - [Bảng Dimension (Dimension Tables)](#bảng-dimension-dimension-tables)
  - [Tầng Looker Data Mart](#tầng-looker-data-mart)
- [🧪 Data Quality & Tests](#-data-quality--tests)
  - [Ràng buộc toàn vẹn & Schema Tests](#ràng-buộc-toàn-vẹn--schema-tests)
  - [Kiểm soát PII & Data Governance](#kiểm-soát-pii--data-governance)
  - [Xử lý các trường hợp ngoại lệ](#xử-lý-các-trường-hợp-ngoại-lệ-known-edge-cases)
- [🤝 Contribution](#-contribution)

---

## 📌 Project Overview

### Pipeline giải quyết bài toán gì?
Glamira là thương hiệu trang sức và phụ kiện cao cấp quy mô toàn cầu với mạng lưới storefront trực tuyến hoạt động đa quốc gia, đa ngôn ngữ và thanh toán qua nhiều loại tiền tệ. Toàn bộ hành vi người dùng (clickstream tracking: xem sản phẩm, chọn tùy chọn chất liệu/đá quý, thêm giỏ hàng, đặt hàng thành công...) được ghi nhận dưới dạng JSON/BSON document không cấu trúc trong cơ sở dữ liệu MongoDB (`countly.summary`).

Hệ thống pipeline này được thiết kế để giải quyết các bài toán cốt lõi sau:

1. **Làm giàu dữ liệu danh mục sản phẩm (Product Catalog Enrichment):**
   - Sự kiện clickstream trong MongoDB chỉ lưu các mã định danh `product_id`, thiếu các thuộc tính quan trọng của sản phẩm như `product_name`, `sku`, `base price`, `min price`, `max price`,... 
   - **Giải pháp:** Xây dựng Crawler bất đồng bộ với khả năng giả lập TLS fingerprint trình duyệt Chrome (`curl-cffi`) để tự động bóc tách thông tin cấu hình sản phẩm từ URL sản phẩm. Ví dụ: `https://www.glamira.co.uk/catalog/product/view/id/85796`

2. **Chuẩn hóa địa lý & tỷ giá hối đoái đa quốc gia:**
   - Các giao dịch checkout diễn ra trên hàng chục loại tiền tệ bản địa khác nhau (EUR, USD, GBP, SGD, AUD, CHF...).
   - **Giải pháp:** Sử dụng cơ sở dữ liệu offline `IP2Location` để chuyển đổi IP thành quốc gia, thành phố, tọa độ địa lý; đồng thời tích hợp API `Frankfurter` để tự động truy xuất lịch sử tỷ giá hối đoái USD theo đúng ngày phát sinh giao dịch, kết hợp cùng mô hình Gemini AI để ánh xạ các chuỗi tiền tệ thô sang mã chuẩn.

3. **Khắc phục giới hạn phân tích của MongoDB (NoSQL) sang Cloud OLAP:**
   - Dữ liệu MongoDB có cấu trúc nested nhiều tầng, kiểu dữ liệu lá (leaf nodes) không đồng nhất (heterogeneous data types), không tối ưu cho truy vấn phân tích tổng hợp phức tạp (OLAP).
   - **Giải pháp:** Xây dựng pipeline chuẩn hóa schema, chuyển đổi BSON sang Apache Parquet nạp lên Google Cloud Storage (GCS), kích hoạt Google Cloud Function tự động load vào BigQuery, và dùng dbt để chuyển đổi thành mô hình Star Schema hoàn chỉnh.
---

## 🏛️ Architecture

![Architecture Diagram](images/architecture.svg)

### Chi tiết các giai đoạn
1. **Source $\to$ Ingestion:**
   - **MongoDB:** Extract các document sự kiện theo batching cursor có checkpoint tránh trùng lặp.
   - **Crawler:** Cào dữ liệu sản phẩm trên website. Mỗi product_id sẽ được lưu trong file `.jsonl` riêng biệt và được cập nhật mỗi khi có thay đổi trên website.
   - **Enrichment:** Tra cứu IP offline qua file BIN `IP2Location`, lấy tỷ giá ngoại tệ từ Frankfurter API.
2. **Ingestion $\to$ Storage:**
   - Dữ liệu MongoDB được chuẩn hóa kiểu dữ liệu lá (BSON leaves $\to$ String) để tránh xung đột schema, lưu dạng Parquet nén Snappy và upload lên GCS.
   - Các file bổ trợ (`products.jsonl`, `locations.jsonl`, `exchange_rate.jsonl`) được đẩy lên GCS tương ứng.
3. **Storage $\to$ Warehouse:**
   - Google Cloud Function bắt sự kiện `google.cloud.storage.object.v1.finalized` (Eventarc / CloudEvent) để khởi chạy BigQuery Load Job idempotent (dựa trên hash ID) vào Landing dataset.
4. **Transform $\to$ Marts:**
   - **dbt (Data Build Tool):** Thực hiện chuyển đổi từ `landing` $\to$ `staging` (views làm sạch) $\to$ `warehouse` (tables dimensional) $\to$ `looker` (data marts).
5. **Warehouse $\to$ BI:**
   - Kết nối BigQuery tables trong dataset `looker` lên Google Looker Studio để theo dõi KPI, doanh thu theo quốc gia, phân tích tăng trưởng MoM và hành vi khách hàng.

---

## 🛠️ Tech Stack

| Thành phần / Phân tầng | Công nghệ sử dụng | Vai trò & Mục đích |
| :--- | :--- | :--- |
| **Ngôn ngữ & Môi trường** | **Python 3.11**, **Poetry** | Quản lý mã nguồn, dependencies và đóng gói CLI tool |
| **Cơ sở dữ liệu nguồn** | **MongoDB (Countly)**, **PyMongo** | Cơ sở dữ liệu NoSQL lưu trữ toàn bộ event logs thô |
| **Crawl & Scraping Engine** | **curl-cffi**, **Asyncio** | Crawl storefront Glamira với TLS/HTTP2 fingerprint Chrome |
| **Làm giàu dữ liệu (Enrichment)** | **IP2Location (LITE DB5)**, **Frankfurter API**, **Gemini API** | Tra cứu vị trí IP, tỷ giá tiền tệ và chuẩn hóa mã ISO 4217 |
| **Data Lake Storage** | **Google Cloud Storage (GCS)**, **PyArrow (Parquet)** | Lưu trữ trung gian dữ liệu dạng Parquet và JSONL |
| **Serverless Orchestration** | **Google Cloud Functions**, **Functions Framework** | Event-driven loader tự động đưa dữ liệu GCS vào BigQuery |
| **Cloud Data Warehouse** | **Google BigQuery** | Kho dữ liệu quy mô lớn (Landing, Staging, Warehouse, Marts) |
| **Data Transformation** | **dbt-core**, **dbt-bigquery** | Quản lý vòng đời dữ liệu, mô hình hóa Star Schema & SCD Type 2 |
| **Data Quality & Testing** | **dbt tests**, **dbt_expectations**, **Pytest** | Kiểm thử chất lượng dữ liệu, ràng buộc toàn vẹn và kiểm tra schema |
| **Bảo mật & Governance** | **BigQuery Policy Tags (Data Catalog)** | Masking và phân quyền cột dữ liệu cá nhân nhạy cảm (PII) |
| **BI & Analytics** | **Google Looker Studio** | Xây dựng Dashboard báo cáo quản trị và trực quan hóa KPI |

---

## 📂 Project Structure

```text
glamira-crawl-product/
├── .env                                  # Biến môi trường kết nối (MongoDB, GCP, Gemini)
├── pyproject.toml                        # Quản lý thư viện Python cho pipeline chính (Poetry)
├── poetry.lock                           # Lockfile các dependencies chính
├── main.py                               # Entrypoint chạy CLI
│
├── config/                               # Quản lý cấu hình tập trung
│   ├── config.py                         # Module load settings và validate cấu hình
│   └── config.yml                        # Cấu hình crawler, mongo, GCS, concurrency, delay
│
├── data/                                 # Lưu trữ dữ liệu cục bộ, SQLite state và file nhị phân
│   ├── IP2LOCATION-LITE-DB5.BIN          # Database nhị phân IP2Location offline
│   ├── crawl-state.sqlite3               # SQLite lưu trữ hàng đợi crawl và checkpoint
│   ├── products.jsonl                    # Dữ liệu sản phẩm sau khi crawl
│   ├── locations.jsonl                   # Dữ liệu IP đã được giải mã địa lý
│   └── exchange_rate.jsonl               # Dữ liệu tỷ giá hối đoái lịch sử
│
├── glamira_crawl/                        # Module khai phá, crawl và làm giàu dữ liệu
│   ├── __init__.py
│   ├── cli.py                            # Giao diện dòng lệnh (CLI subcommands)
│   ├── crawler.py                        # Engine crawler bất đồng bộ (curl-cffi, session pool)
│   ├── discovery.py                      # Quét MongoDB để bóc tách product_id và URL
│   ├── parsing.py                        # Bóc tách react_data_url và payload sản phẩm
│   ├── state.py                          # Quản trị trạng thái qua SQLite (Pending, Done, Failed)
│   ├── locations.py                      # Module xử lý đa luồng tra cứu IP sang địa lý
│   └── exchange_rates.py                 # Tự động tải tỷ giá theo các ngày checkout
│
├── load/                                 # Module xuất dữ liệu và nạp lên Cloud
│   ├── __init__.py
│   ├── export_to_gcs.py                  # Chuẩn hóa BSON sang Parquet và tải lên GCS
│   ├── load_to_bigquery.py               # Script hỗ trợ gửi job nạp Parquet vào BigQuery
│   ├── trigger_bigquery.py               # Logic xử lý CloudEvent trigger nạp BigQuery
│   └── migrate_parquet_to_string.py      # Utility chuẩn hóa dữ liệu cũ
│
├── cloud_function/                       # Mã nguồn triển khai Google Cloud Function
│   ├── main.py                           # Hàm xử lý CloudEvent từ GCS sang BigQuery
│   └── requirements.txt                  # Dependencies riêng cho Cloud Function runtime
│
├── dbt/                                  # Toàn bộ dự án dbt Data Warehouse
│   ├── pyproject.toml                    # Môi trường Poetry riêng cho dbt-bigquery
│   └── glamira_warehouse/
│       ├── dbt_project.yml               # Cấu hình dbt project, materialization & schemas
│       ├── packages.yml                  # Khai báo dbt package (dbt_expectations)
│       ├── seeds/
│       │   └── currency_mapping.csv      # Bảng mapping tiền tệ thô sang chuẩn ISO 4217
│       ├── scripts/
│       │   └── generate_currency_mapping.py  # Script dùng Gemini AI tạo file seed tiền tệ
│       └── models/
│           ├── staging/                  # Tầng Staging (Views làm sạch & deduplication)
│           │   ├── _sources.yml          # Định nghĩa nguồn BigQuery Landing tables
│           │   ├── stg_dim_customer.sql  # Xử lý sự kiện customer, chuẩn bị SCD2
│           │   ├── stg_dim_product.sql   # Chuẩn hóa dữ liệu sản phẩm từ raw_product
│           │   ├── stg_dim_store.sql     # Chuẩn hóa store domain & code
│           │   ├── stg_dim_location.sql  # Chuẩn hóa thông tin IP, tọa độ
│           │   ├── stg_dim_currency.sql  # Chuẩn hóa tiền tệ qua seed
│           │   ├── stg_dim_date.sql      # Tạo chuỗi thời gian phân tích
│           │   └── stg_fact_exchange_rate.sql
│           ├── warehouse/                # Tầng Warehouse (Star Schema Tables)
│           │   ├── _models.yml           # Documentation, Schema tests, Expectations, PII Tags
│           │   ├── dim_customer.sql      # SCD Type 2 Customer dimension
│           │   ├── dim_product.sql       # Product dimension
│           │   ├── dim_store.sql         # Store dimension
│           │   ├── dim_location.sql      # Location dimension
│           │   ├── dim_currency.sql      # Currency dimension
│           │   ├── dim_date.sql          # Date dimension
│           │   ├── fact_sales_order_detail.sql # Bảng Fact chi tiết đơn hàng & doanh thu USD
│           │   └── fact_exchange_rate.sql
│           └── looker/                   # Tầng Marts tối ưu cho Looker Studio Dashboards
│               ├── order_by_product.sql
│               ├── revenue_by_country.sql
│               ├── revenue_mom_analysis.sql
│               ├── revenue_order_by_week.sql
│               └── revenue_aov_customer_analysis.sql
│
├── images/                               # Hình ảnh tài liệu và sơ đồ kiến trúc
│   └── architecture.svg                  # Sơ đồ kiến trúc luồng dữ liệu End-to-End
│
└── tests/                                # Bộ kiểm thử tự động Unit Test & Pipeline
    ├── test_crawler.py
    ├── test_discovery.py
    ├── test_exchange_rates.py
    ├── test_load.py
    ├── test_locations.py
    ├── test_parsing.py
    └── test_state.py
```

---

## ⚙️ Setup & Installation

### Yêu cầu hệ thống
- **Hệ điều hành:** Linux, macOS, hoặc Windows.
- **Python:** Phiên bản $\ge$ 3.11.
- **Poetry:** Công cụ quản lý package (`pip install poetry`).
- **Google Cloud SDK (`gcloud`):** Đã cấu hình xác thực với GCP project.
- **Tài nguyên cần có:** Quyền truy cập cụm MongoDB và file cơ sở dữ liệu `IP2LOCATION-LITE-DB5.BIN`.

### Cài đặt môi trường

```bash
# 1. Clone repository
git clone https://github.com/thanhklt/glamira-crawl-product.git
cd glamira-crawl-product

# 2. Cài đặt dependencies cho Pipeline chính
poetry install

# 3. Cài đặt dependencies cho dbt
cd dbt
poetry install
cd ..

# 4. Tải các gói phụ thuộc dbt packages
cd dbt/glamira_warehouse
poetry run dbt deps
cd ../..
```

### Chuẩn bị file nhị phân IP2Location
Tải file `IP2LOCATION-LITE-DB5.BIN` và đặt vào thư mục `data/`:
```bash
# Kiểm tra file đã sẵn sàng trong data/
ls -lh data/IP2LOCATION-LITE-DB5.BIN
```

### Thiết lập biến môi trường (.env)
Tạo file `.env` tại thư mục gốc của project:
```env
# MongoDB Connection
MONGODB_URI=mongodb://<HOST>:27017/?authSource=admin
MONGODB_USERNAME=your_username
MONGODB_PASSWORD=your_password
MONGODB_AUTH_SOURCE=admin

# Google Cloud Platform
GOOGLE_APPLICATION_CREDENTIALS=path/to/service-account-key.json
GCP_PROJECT_ID=glamira-project-502214

# Gemini API Key (dùng sinh mapping chuẩn hóa mã tiền tệ)
GEMINI_API_KEY=your_gemini_api_key
```

### Cấu hình dbt Profile
Tạo hoặc cập nhật file `~/.dbt/profiles.yml`:
```yaml
glamira_warehouse:
  target: dev
  outputs:
    dev:
      type: bigquery
      method: oauth # hoặc service-account
      project: glamira-project-502214
      dataset: warehouse
      threads: 8
      location: asia-southeast1
      priority: interactive
```

---

## 🚀 How to Run

Quy trình thực thi dữ liệu từ đầu đến cuối (End-to-End Execution):

### Bước 1: Khám phá sản phẩm từ MongoDB (Discovery)
Quét toàn bộ collection `summary` của MongoDB để tìm các sự kiện có chứa `product_id` và URL tương ứng, đưa vào hàng đợi SQLite:
```bash
poetry run glamira-crawl discover
```

### Bước 2: Thu thập thông tin chi tiết sản phẩm (Crawl)
Crawl thông tin metadata sản phẩm (chất liệu, đá, trọng lượng, phân loại, giá) từ web Glamira:
```bash
poetry run glamira-crawl crawl

# Nếu muốn thử lại các URL bị lỗi tạm thời:
poetry run glamira-crawl crawl --retry-failed
```

### Bước 3: Tra cứu vị trí địa lý của IP (Locations)
Trích xuất danh sách địa chỉ IP duy nhất từ MongoDB và tra cứu qua cơ sở dữ liệu `IP2Location`:
```bash
poetry run glamira-crawl locations --workers 16
```
*Kết quả xuất ra tại `data/locations.jsonl`.*

### Bước 4: Lấy tỷ giá hối đoái lịch sử (Exchange Rates)
Thu thập tỷ giá USD theo các ngày phát sinh giao dịch thành công (`checkout_success`):
```bash
poetry run glamira-crawl exchange-rates
```
*Kết quả xuất ra tại `data/exchange_rate.jsonl`.*

### Bước 5: Chuyển đổi và nạp dữ liệu lên GCS (Load)
Trích xuất dữ liệu sự kiện từ MongoDB, chuẩn hóa cấu trúc BSON, xuất thành các file Parquet và tải tự động lên Google Cloud Storage:
```bash
poetry run glamira-crawl load
```

### Bước 6: Ingestion vào BigQuery (Event-Driven Cloud Function)
- Cloud Function tự động lắng nghe sự kiện upload trên GCS bucket `raw_glamira` và nạp vào các bảng Landing của BigQuery (`raw_mongo`, `raw_location`, `raw_product`, `raw_exchange_rate`).
- *(Tùy chọn thủ công)*: Chạy lệnh nạp thủ công nếu không triển khai Cloud Function:
  ```bash
  poetry run python load/load_to_bigquery.py
  ```

### Bước 7: Thực thi dbt Transformation Models
Chuyển đổi dữ liệu thô thành Data Warehouse và Data Mart:
```bash
cd dbt/glamira_warehouse

# 1. Nạp file seed mapping tiền tệ
poetry run dbt seed

# 2. Xây dựng toàn bộ các tầng Staging, Warehouse, Marts
poetry run dbt run

# 3. Chạy toàn bộ kiểm thử dữ liệu
poetry run dbt test
```

---

## 🧩 Data Model

Dự án áp dụng phương pháp thiết kế Dimensional Modeling của Ralph Kimball theo mô hình hình sao (Star Schema), xử lý lịch sử khách hàng bằng SCD Type 2 và chuẩn hóa surrogate key mặc định `-1` cho các bản ghi khuyết thiếu (Unknown / Late Arriving Dimensions).

```
                      ┌───────────────┐
                      │   dim_date    │
                      └───────┬───────┘
                              │
  ┌───────────────┐           │           ┌───────────────┐
  │ dim_customer  │           │           │  dim_product  │
  │   (SCD T2)    │           │           └───────┬───────┘
  └───────┬───────┘           │                   │
          │                   │                   │
          │        ┌──────────┴──────────┐        │
          └───────►│fact_sales_order_det.│◄───────┘
                   └──────────┬──────────┘
          ┌───────────────────┼───────────────────┐
          │                   │                   │
  ┌───────▼───────┐   ┌───────▼───────┐   ┌───────▼───────┐
  │   dim_store   │   │ dim_location  │   │ dim_currency  │
  └───────────────┘   └───────────────┘   └───────┬───────┘
                                                  │
                                          ┌───────▼──────────┐
                                          │fact_exchange_rate│
                                          └──────────────────┘
```

### Bảng Fact (Fact Tables)

#### `fact_sales_order_detail`
- **Mức độ chi tiết (Grain):** Từng dòng sản phẩm trong đơn hàng thanh toán thành công (`checkout_success`).
- **Surrogate Keys:** `customer_key`, `product_key`, `store_key`, `location_key`, `currency_key`, `order_date_key`.
- **Business Key:** `detail_key` (tạo từ mã hash duy nhất của đơn hàng và sản phẩm).
- **Chỉ số đo lường (Metrics):**
  - `item_quantity`: Số lượng sản phẩm mua.
  - `price_original`: Đơn giá bằng đồng tiền bản địa lúc thanh toán.
  - `exchange_rate`: Tỷ giá hối đoái quy đổi sang USD tại ngày mua.
  - `price_usd`: Đơn giá quy đổi sang USD.
  - `subtotal_usd`: Tổng tiền dòng sản phẩm bằng USD ($= \text{price\_usd} \times \text{item\_quantity}$).

#### `fact_exchange_rate`
- **Grain:** Tỷ giá của từng mã tiền tệ quy đổi theo ngày so với đồng tiền cơ sở (USD).
- **Keys:** `date_key`, `currency_key`.
- **Metrics:** `exchange_rate` (tỷ giá chính thức hoặc tỷ giá điền khuyết từ ngày làm việc gần nhất).

### Bảng Dimension (Dimension Tables)

#### `dim_customer` (Slowly Changing Dimension Type 2)
- **Business Key:** `customer_device_id`.
- **Surrogate Key:** `customer_key` (quản lý từng phiên bản thay đổi của khách hàng, giá trị `-1` đại diện cho Unknown).
- **Thuộc tính theo dõi:** `customer_user_agent`, `customer_user_id_db`, `customer_email_address` *(gắn policy tag bảo mật PII)*.
- **SCD2 Tracking:** `customer_version_number`, `start_time`, `end_time`, `is_current` (cờ `true` cho bản ghi hiện hành).

#### `dim_product`
- **Business Key:** `product_id`.
- **Surrogate Key:** `product_key`.
- **Thuộc tính:** `sku`, `product_name`, `gold_weight`, `fixed_silver_weight`, `material_design`, `collection`, `category_name`, `price`, `min_price`, `max_price`.

#### `dim_store` & `dim_currency`
- **`dim_store`:** Quản lý `store_id`, `store_code`, `store_domain`.
- **`dim_currency`:** Quản lý `currency_code` (chuẩn ISO 4217), `currency_name`.

#### `dim_location`
- **Business Key:** `ip`.
- **Surrogate Key:** `location_key`.
- **Thuộc tính:** `city_name`, `region_name`, `country_code`, `country_name`, `latitude`, `longitude`.

#### `dim_date`
- **Key:** `date_key` (định dạng `YYYYMMDD`).
- **Thuộc tính:** `full_date`, `year`, `quarter`, `month`, `month_name`, `week_of_year`, `day_of_week`, `is_weekend`.

### Tầng Looker Data Mart
- **`revenue_by_country`:** Tổng hợp doanh thu, giá trị trung bình đơn hàng theo quốc gia.
- **`revenue_mom_analysis`:** Phân tích tốc độ tăng trưởng doanh thu theo từng tháng (Month-over-Month Growth Rate).
- **`order_by_product`:** Xếp hạng các sản phẩm, bộ sưu tập bán chạy nhất.
- **`revenue_order_by_week`:** Xu hướng biến động đơn hàng theo các tuần trong năm.
- **`revenue_aov_customer_analysis`:** Phân tích giá trị đơn hàng trung bình (AOV) và tần suất mua sắm của khách hàng.

---

## 🧪 Data Quality & Tests

Hệ thống triển khai kiểm thử chất lượng dữ liệu đa tầng bằng **dbt test**, **dbt_expectations** và **BigQuery Data Policy**:

### Ràng buộc toàn vẹn & Schema Tests
- **Not Null & Uniqueness:** Đảm bảo tất cả các surrogate key (`*_key`) và business key không bị null và duy nhất trên các bảng Dimension và Fact.
- **Compound Key Uniqueness (`dbt_expectations`):**
  - Kiểm tra tính duy nhất của cặp `(customer_device_id, start_time)` trên `dim_customer` để đảm bảo tính toàn vẹn của SCD Type 2:
    ```yaml
    - dbt_expectations.expect_compound_columns_to_be_unique:
        column_list: ["customer_device_id", "start_time"]
        row_condition: "customer_key != -1"
    ```
- **Referential Integrity (Foreign Keys):** Mọi surrogate key trong bảng `fact_sales_order_detail` đều được liên kết hợp lệ với các bảng Dimension tương ứng (hoặc trỏ về khóa `-1` nếu dữ liệu đến muộn).

### Kiểm soát PII & Data Governance
- Trường `customer_email_address` trong bảng `dim_customer` được gắn chính sách **Policy Tag** của Google Cloud Data Catalog (`cus_email`).
- Chỉ các tài khoản có quyền `Data Catalog Fine-Grained Reader` mới có thể đọc giá trị nguyên bản, đảm bảo tuân thủ tiêu chuẩn an toàn thông tin cá nhân.

### Xử lý các trường hợp ngoại lệ (Known Edge Cases)
- **Domain Store trùng lặp:** Dùng thuật toán ranking phân định theo độ đầy đủ thông tin để gán một Store duy nhất tại `stg_dim_store.sql`.
- **Khuyết tỷ giá ngày nghỉ/cuối tuần:** Tự động fallback lấy tỷ giá của ngày làm việc gần nhất liền kề trước đó trong `stg_fact_exchange_rate.sql`.
- **Anti-Bot & Rate Limit:** Cơ chế retry backoff, xoay vòng User-Agent và TLS fingerprinting giúp quá trình crawl dữ liệu không bị gián đoạn.

---

## 🤝 Contribution

Mọi sự đóng góp cho dự án đều được hoan nghênh. Xin vui lòng tuân thủ quy trình sau:

1. **Fork** repository về tài khoản cá nhân.
2. Tạo một branch mới cho tính năng hoặc bản sửa lỗi:
   ```bash
   git checkout -b feature/amazing-feature
   ```
3. Commit các thay đổi với thông điệp rõ ràng tuân thủ conventional commits:
   ```bash
   git commit -m "feat: add incremental merge logic for fact_sales_order_detail"
   ```
4. Đảm bảo toàn bộ các bài test đều vượt qua:
   ```bash
   cd dbt/glamira_warehouse && poetry run dbt test
   ```
5. Push branch lên GitHub:
   ```bash
   git push origin feature/amazing-feature
   ```
6. Tạo một **Pull Request** giải thích chi tiết mục đích và nội dung thay đổi.
