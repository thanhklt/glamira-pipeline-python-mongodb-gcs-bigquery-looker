# Glamira Product Collector

Công cụ thu thập dữ liệu sản phẩm Glamira từ MongoDB, crawl thông tin chi tiết và
xuất kết quả ra JSONL. Tiến trình được lưu trong SQLite nên có thể tiếp tục sau khi
chương trình bị dừng.

## Yêu cầu

- Python 3.11 trở lên
- Poetry
- Quyền truy cập MongoDB nguồn
- File IP2Location DB5 nếu dùng lệnh `locations`

Crawler sử dụng `curl-cffi`, không cần cài Chrome, Edge hoặc Playwright.

## To do:
- relationships test: fact_sales_order_detail vs dim_customer: 1 bản ghi bị lỗi
- not null test: fact_sales_order_detail bị lỗi vì tồn tại price null: 175 bản ghi bị lỗi