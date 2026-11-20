# 🛒 ShopeeDB — Hệ thống CSDL Sàn thương mại điện tử

> **Bài tập lớn 2** · Cơ sở dữ liệu · HK261  
> SQL Server 2022 / 2025 · T-SQL · HTML/CSS/JS Frontend

---

## Mục lục

- [Giới thiệu](#giới-thiệu)
- [Kiến trúc hệ thống](#kiến-trúc-hệ-thống)
- [Cấu trúc thư mục](#cấu-trúc-thư-mục)
- [Mô hình dữ liệu](#mô-hình-dữ-liệu)
- [Ràng buộc ngữ nghĩa](#ràng-buộc-ngữ-nghĩa)
- [Trigger nghiệp vụ](#trigger-nghiệp-vụ)
- [Stored Procedure](#stored-procedure)
- [Dữ liệu mẫu](#dữ-liệu-mẫu)
- [Kiểm thử & Audit](#kiểm-thử--audit)
- [Frontend Demo](#frontend-demo)
- [Yêu cầu môi trường](#yêu-cầu-môi-trường)
- [Hướng dẫn cài đặt & chạy](#hướng-dẫn-cài-đặt--chạy)
- [Mã lỗi tham chiếu](#mã-lỗi-tham-chiếu)

---

## Giới thiệu

**ShopeeDB** là hệ thống cơ sở dữ liệu mô phỏng sàn thương mại điện tử Shopee, được thiết kế và triển khai trên **SQL Server**. Dự án bao gồm:

- **Schema DDL** với 17 bảng, ràng buộc toàn vẹn (PK, FK, CHECK, UNIQUE), computed column và view.
- **Trigger** kiểm tra quyền đánh giá sản phẩm và tự động cập nhật điểm trung bình.
- **Stored Procedure** truy vấn danh sách sản phẩm theo tên / danh mục / người bán.
- **162 dòng dữ liệu mẫu** phủ đủ các kịch bản nghiệp vụ.
- **26 ca kiểm thử** tự động cho trigger và **11 nhóm audit** kiểm tra tính nhất quán dữ liệu.
- **Frontend SPA** (HTML/CSS/JS thuần) demo giao diện mua sắm và quản lý sản phẩm.

---

## Kiến trúc hệ thống

```
┌──────────────────────┐       REST API        ┌──────────────────────┐
│   Frontend (SPA)     │ ◄──── /api/* ────────► │   Backend Server     │
│   HTML · CSS · JS    │                        │   (cần triển khai)   │
└──────────────────────┘                        └──────────┬───────────┘
                                                           │
                                                     ADO.NET / ODBC
                                                           │
                                                ┌──────────▼───────────┐
                                                │    SQL Server        │
                                                │    ShopeeDB          │
                                                │  17 bảng · 2 trigger │
                                                │  3 view · 1 SP       │
                                                └──────────────────────┘
```

---

## Cấu trúc thư mục

```
assignment2/
├── V2-shopee_schema.sql        # DDL: tạo database, 17 bảng, views, constraints
├── shopee_schema.sql           # Schema phiên bản đầy đủ (Phase 2)
├── H1_triggers.sql             # 2 trigger kiểm tra & cập nhật đánh giá
├── H2_seed.sql                 # 162 dòng dữ liệu mẫu cho 17 bảng
├── H3_demo_tests.sql           # 26 ca kiểm thử tự động cho trigger
├── H4_audit.sql                # 11 nhóm kiểm tra tính nhất quán dữ liệu
├── T3_product_list.sql         # Stored procedure truy vấn danh sách sản phẩm
├── semantic_constraints_v2.txt # 21 ràng buộc ngữ nghĩa (đặc tả)
├── shopeeEERD.html             # Sơ đồ EERD tương tác
├── frontend/
│   ├── index.html              # Giao diện SPA chính
│   ├── app.js                  # Logic ứng dụng frontend
│   ├── styles.css              # Stylesheet chung
│   ├── marketplace.css         # Stylesheet cho marketplace
│   └── API_CONTRACT.md         # Hợp đồng API frontend ↔ backend
├── assignment1/                # Báo cáo BTL1 (tham chiếu)
│   ├── report.pdf
│   └── Mô tả BTL1_Updated.docx
└── README.md                   # ← Bạn đang ở đây
```

---

## Mô hình dữ liệu

### Danh sách 17 bảng

| # | Bảng | Mô tả |
|--:|------|-------|
| 1 | `Users` | Tài khoản người dùng (computed `Age`) |
| 2 | `User_Phone` | Số điện thoại (thuộc tính đa trị) |
| 3 | `Address` | Địa chỉ giao hàng (thực thể yếu) |
| 4 | `Buyer` | Vai trò người mua |
| 5 | `Seller` | Vai trò người bán (tên shop, mã thuế) |
| 6 | `Voucher` | Mã giảm giá (phần trăm, ngưỡng, số lượt) |
| 7 | `Buyer_Voucher` | Voucher đã cấp cho người mua (M:N) |
| 8 | `Category` | Danh mục sản phẩm (đệ quy) |
| 9 | `Product` | Sản phẩm (cache `Average_Rating`) |
| 10 | `Product_Variant` | Phân loại sản phẩm (giá, tồn kho) |
| 11 | `Product_Image` | Ảnh sản phẩm (URL) |
| 12 | `Shipping_Company` | Đơn vị vận chuyển |
| 13 | `Orders` | Đơn hàng (trạng thái, voucher, phí ship) |
| 14 | `Order_Detail` | Chi tiết đơn (biến thể, số lượng, đơn giá) |
| 15 | `Payment` | Thanh toán (COD, Bank Transfer, E-Wallet, Credit Card) |
| 16 | `Return_Request` | Yêu cầu trả hàng |
| 17 | `Review` | Đánh giá sản phẩm (1–5 sao) |

### Quy ước

- **Tiền tệ:** VND, kiểu `DECIMAL(15,0)` (số nguyên)
- **Thời gian:** `DATETIME2(0)`
- **Collation:** `Vietnamese_CI_AS`
- **Mật khẩu:** lưu dạng plaintext kèm CHECK constraint (chỉ dành cho bài tập)

---

## Ràng buộc ngữ nghĩa

Hệ thống triển khai **21 ràng buộc ngữ nghĩa** bao gồm:

| Nhóm | Nội dung chính |
|------|---------------|
| Tồn kho | Số lượng mua ≤ tồn kho tại thời điểm checkout; trừ/hoàn kho khi xác nhận/hủy đơn |
| Đánh giá | Chỉ được đánh giá sản phẩm đã mua & nhận thành công; ngày đánh giá ≥ ngày giao |
| Tổng tiền | `Total_Amount = Subtotal - Discount + Shipping_Fee` (thuộc tính dẫn xuất) |
| Voucher | Hiệu lực ngày, ngưỡng đơn tối thiểu, giới hạn số lượt, mỗi buyer dùng 1 lần/voucher |
| Trạng thái | Chu trình trạng thái cho đơn hàng, thanh toán và trả hàng |
| Người bán | Phải ≥ 18 tuổi mới được mở shop |
| Mật khẩu | 8–16 ký tự, ít nhất 1 chữ hoa, 1 chữ thường, 1 chữ số |

> Chi tiết đầy đủ: [`semantic_constraints_v2.txt`](semantic_constraints_v2.txt)

---

## Trigger nghiệp vụ

### 1. `trg_Review_Eligibility_Timing` — Kiểm tra quyền đánh giá

- **Sự kiện:** `AFTER INSERT, UPDATE` trên `Review`
- **Quy tắc:** Người đánh giá phải có ít nhất một đơn giao thành công (`Delivery Successful`) chứa biến thể của sản phẩm đó, và ngày đánh giá ≥ ngày giao (so theo `DATE`)
- **Vi phạm:** `ROLLBACK` toàn giao dịch + `THROW` mã lỗi `51101` hoặc `51102`

### 2. `trg_Review_AverageRating` — Duy trì điểm trung bình

- **Sự kiện:** `AFTER INSERT, UPDATE, DELETE` trên `Review`
- **Quy tắc:** Tự động tính `Product.Average_Rating = AVG(Rating_Score)` cho các sản phẩm bị ảnh hưởng; sản phẩm hết đánh giá → `NULL`
- **Tối ưu:** Bỏ qua UPDATE không liên quan đến `Rating_Score` hoặc `Product_ID`; sử dụng `UPDLOCK` để tránh xung đột

| DML trên Review | Kiểm tra quyền | Cập nhật điểm |
|-----------------|:-:|:-:|
| INSERT | ✅ | ✅ |
| UPDATE Rating_Score | ✅ | ✅ |
| UPDATE Product_ID | ✅ | ✅ (cả cũ & mới) |
| UPDATE Buyer_ID / Review_Date | ✅ | — |
| DELETE | — | ✅ |

---

## Stored Procedure

### `dbo.usp_Product_List` — Danh sách sản phẩm

```sql
EXEC dbo.usp_Product_List
    @SearchTerm  = N'tai nghe',   -- tìm theo tên sản phẩm hoặc shop
    @Category_ID = 2,             -- lọc theo danh mục
    @Seller_ID   = 1;             -- lọc theo người bán
```

Trả về: tên, mô tả, danh mục, shop, khoảng giá, tổng tồn kho, biến thể gần hết hàng, URL ảnh, điểm đánh giá trung bình.

---

## Dữ liệu mẫu

**162 bản ghi** phủ 17 bảng:

| Bảng | Số dòng | Bảng | Số dòng |
|------|--------:|------|--------:|
| Users | 8 | User_Phone | 10 |
| Address | 11 | Buyer | 8 |
| Seller | 5 | Voucher | 6 |
| Buyer_Voucher | 9 | Category | 8 |
| Product | 11 | Product_Variant | 17 |
| Product_Image | 7 | Shipping_Company | 5 |
| Orders | 12 | Order_Detail | 18 |
| Payment | 12 | Return_Request | 6 |
| Review | 9 | **Tổng** | **162** |

Dữ liệu bao gồm: người mua chưa có đơn, đơn ở nhiều trạng thái (Pending → Delivery Successful → Cancelled), sản phẩm có/chưa có đánh giá, voucher đã hết hạn, v.v.

---

## Kiểm thử & Audit

### H3 — 26 ca kiểm thử tự động

| Nhóm | Số ca | Nội dung |
|------|------:|---------|
| QT-01…QT-15 | 15 | Quyền & thời điểm đánh giá: hợp lệ, đơn chưa giao, đơn hủy, sai người/sản phẩm, biên ngày, cập nhật, lệnh nhiều dòng |
| DT-01…DT-11 | 11 | Điểm trung bình: thêm/sửa/xóa, xóa đánh giá cuối, chuyển sản phẩm, thao tác bị từ chối, thao tác nhiều dòng |

Mỗi ca tự rollback dữ liệu sau khi chạy. Kết quả mong đợi: **26/26 PASS**.

### H4 — 11 nhóm audit

| Mã | Kiểm tra |
|----|---------|
| A01 | Thanh toán khớp tổng tiền đơn |
| A02 | Ngày đặt đơn trong thời hạn voucher |
| A03 | Đơn đã xác nhận đạt ngưỡng tối thiểu voucher |
| A04 | Số đơn dùng voucher ≤ Quantity |
| A05 | Đơn giao thành công có Delivered_At |
| A06 | Người đánh giá đã nhận đúng sản phẩm |
| A07 | Ngày đánh giá ≥ ngày giao |
| A08 | Mọi tài khoản đều có vai trò Buyer |
| A09 | Mỗi sản phẩm có ít nhất 1 biến thể |
| A10 | Người bán ≥ 18 tuổi |
| A11 | Điểm lưu khớp điểm tính từ Review |

Kết quả mong đợi: **11/11 nhóm có 0 vi phạm**.

---

## Frontend Demo

Giao diện **Single Page Application** (HTML/CSS/JS thuần) với hai vai trò:

| Vai trò | Chức năng |
|---------|----------|
| **Người mua** | Xem sản phẩm, lọc/tìm kiếm, chọn biến thể, thêm giỏ hàng, đặt hàng, xem đơn mua |
| **Người bán** | Quản lý sản phẩm (CRUD), ảnh, biến thể, giá và tồn kho; xem thống kê bán hàng |

> ⚠️ Frontend cần **backend REST API** (chưa có trong repo) để kết nối với SQL Server. Xem [`frontend/API_CONTRACT.md`](frontend/API_CONTRACT.md) để biết đặc tả API đầy đủ.

---

## Yêu cầu môi trường

| Thành phần | Yêu cầu |
|-----------|---------|
| **DBMS** | SQL Server 2022 hoặc 2025 |
| **Công cụ** | SQL Server Management Studio (SSMS) hoặc `sqlcmd` |
| **Quyền** | Tạo database, tạo/sửa bảng, trigger, procedure; thêm/sửa/xóa dữ liệu |
| **Trình duyệt** | Trình duyệt hiện đại (cho frontend demo) |

---

## Hướng dẫn cài đặt & chạy

### Cách 1: Chạy bằng SSMS

1. Kết nối SQL Server.
2. Mở và chạy **`V2-shopee_schema.sql`** (⚠️ sẽ DROP toàn bộ bảng cũ nếu có).
3. Chạy lần lượt theo thứ tự:

| # | Script | Kiểm tra kết quả |
|--:|--------|-----------------|
| 1 | `H1_triggers.sql` | Hai trigger được tạo, không lỗi |
| 2 | `H2_seed.sql` | 17 bảng có dữ liệu, mỗi bảng ≥ 5 dòng |
| 3 | `H3_demo_tests.sql` | 26/26 ca PASS |
| 4 | `H4_audit.sql` | 11/11 nhóm Violation_Count = 0 |
| 5 | `T3_product_list.sql` | Procedure `usp_Product_List` được tạo |

### Cách 2: Chạy bằng sqlcmd (PowerShell)

```powershell
$serverName = 'localhost'

# Bước 1: Tạo schema
sqlcmd -S $serverName -E -C -I -b -f 65001 -i V2-shopee_schema.sql

# Bước 2: Chạy H1 → H4 + T3
$scripts = @('H1_triggers.sql', 'H2_seed.sql', 'H3_demo_tests.sql', 'H4_audit.sql', 'T3_product_list.sql')
foreach ($script in $scripts) {
    sqlcmd -S $serverName -E -C -I -b -f 65001 -i $script
    if ($LASTEXITCODE -ne 0) { throw "Lỗi khi chạy $script" }
}
```

> **Ghi chú:**  
> - `-E`: Windows Authentication (thay bằng `-U <username>` nếu dùng SQL Auth)  
> - `-I`: bật `QUOTED_IDENTIFIER`  
> - `-b`: dừng ngay khi gặp lỗi  
> - `-f 65001`: đọc UTF-8  
> - `-C`: tin cậy chứng chỉ (chỉ dùng trong môi trường thực hành)

### Chạy lại

| Script | Chạy lại? | Lưu ý |
|--------|:---------:|-------|
| H1 | ✅ | Cập nhật trigger, đồng bộ điểm hiện có |
| H2 | ❌ | Chỉ chạy trên DB sạch; muốn nạp lại → chạy lại schema trước |
| H3 | ✅ | Mỗi ca tự rollback dữ liệu |
| H4 | ✅ | Kiểm tra dữ liệu hiện tại |
| T3 | ✅ | `CREATE OR ALTER` procedure |

---

## Mã lỗi tham chiếu

| Mã | Ý nghĩa |
|---:|---------|
| 51100 | H2: dữ liệu đã tồn tại hoặc giao dịch đang mở |
| 51101 | Người đánh giá chưa có đơn giao thành công chứa đúng sản phẩm |
| 51102 | Ngày đánh giá sớm hơn ngày giao hợp lệ |
| 51110 | H3: đang có giao dịch mở |
| 51111 | H3: có ca kiểm thử thất bại |
| 51112 | H4: phát hiện dữ liệu vi phạm |

---

## Công nghệ sử dụng

![SQL Server](https://img.shields.io/badge/SQL_Server-2022%2F2025-CC2927?logo=microsoftsqlserver&logoColor=white)
![T-SQL](https://img.shields.io/badge/T--SQL-DDL%20·%20Trigger%20·%20SP-blue)
![HTML5](https://img.shields.io/badge/HTML5-E34F26?logo=html5&logoColor=white)
![CSS3](https://img.shields.io/badge/CSS3-1572B6?logo=css3&logoColor=white)
![JavaScript](https://img.shields.io/badge/JavaScript-ES2020-F7DF1E?logo=javascript&logoColor=black)

---

<div align="center">
  <sub>Bài tập lớn 2 · Cơ sở dữ liệu · HK261</sub>
</div>
