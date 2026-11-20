# Dữ liệu mẫu và trigger đánh giá sản phẩm — ShopeeDB

Bộ script SQL Server thực hiện phần **1.2 — dữ liệu mẫu** và **2.2 — trigger** của BTL2. Nội dung gồm dữ liệu cho 17 bảng, trigger kiểm tra quyền/ngày đánh giá, trigger duy trì điểm trung bình sản phẩm, kiểm thử và truy vấn kiểm tra dữ liệu.

## 1. Yêu cầu môi trường

- SQL Server 2022 hoặc 2025, phù hợp với schema V2.
- SQL Server Management Studio (SSMS) hoặc `sqlcmd` để chạy script có dấu phân cách batch `GO`.
- Tài khoản có quyền tạo/sửa bảng và trigger, thêm/sửa/xóa dữ liệu trong database `ShopeeDB`. Nếu tạo database mới, cần quyền tạo database.
- File schema đầu vào: `V2-shopee_schema.sql` trong thư mục cha của bộ script.

**Lưu ý:** `V2-shopee_schema.sql` xóa và tạo lại các bảng. Chỉ chạy file này trên database thực hành được phép dựng lại, không chạy trên database có dữ liệu cần giữ.

## 2. Cấu trúc và chức năng các file

| File | Chức năng |
|---|---|
| `../V2-shopee_schema.sql` | Tạo schema, gồm cột `Product.Average_Rating DECIMAL(3,2) NULL` và CHECK giới hạn điểm |
| `H1_triggers.sql` | Cài hai trigger trên `Review`, thiết lập thứ tự ưu tiên kiểm tra quyền và tính lại điểm cho dữ liệu đã có |
| `H2_seed.sql` | Nạp 162 dòng dữ liệu mẫu vào 17 bảng, cập nhật trạng thái mẫu, xuất số dòng và điểm trung bình |
| `H3_demo_tests.sql` | Chạy 26 ca kiểm thử đúng/sai, đối chiếu mã lỗi và dữ liệu trước/sau; hoàn tác dữ liệu sau mỗi ca |
| `H4_audit.sql` | Tính tổng tiền đơn hàng, thực hiện 11 nhóm kiểm tra và liệt kê bản ghi vi phạm |
| [Giai_thich_H1_H2_H3_H4.md](Giai_thich_H1_H2_H3_H4.md) | Giải thích chi tiết cú pháp và cách hoạt động của các script |

## 3. Chức năng và quy tắc nghiệp vụ

### 3.1. Trigger kiểm tra quyền và ngày đánh giá

**Tên:** `dbo.trg_Review_Eligibility_Timing`.

**Sự kiện:** `AFTER INSERT, UPDATE` trên `dbo.Review`.

Một đánh giá được chấp nhận khi tồn tại ít nhất một đơn:

1. Do chính người viết đánh giá đặt.
2. Có trạng thái `Delivery Successful`.
3. Có chi tiết chứa biến thể của sản phẩm được đánh giá.
4. Có ngày giao `Delivered_At` không sau ngày đánh giá `Review_Date`.

Đường liên kết để kiểm tra: `Orders → Order_Detail → Product_Variant → Product`.

So sánh ngày chỉ xét phần `DATE`. Đánh giá và giao hàng trong cùng ngày được chấp nhận, dù giờ đánh giá sớm hơn giờ giao. Nếu một câu lệnh có nhiều đánh giá và một dòng không hợp lệ, trigger từ chối toàn bộ giao dịch hiện tại bằng `ROLLBACK` và `THROW`.

### 3.2. Trigger duy trì điểm trung bình

**Tên:** `dbo.trg_Review_AverageRating`.

**Sự kiện:** `AFTER INSERT, UPDATE, DELETE` trên `dbo.Review`.

```text
Product.Average_Rating = AVG(Review.Rating_Score của sản phẩm)
```

Điểm nguồn được chuyển sang số thập phân trước khi tính trung bình. Kết quả lưu hai chữ số thập phân; sản phẩm chưa có đánh giá nhận `NULL`.

| DML trên Review | Kiểm tra quyền/ngày | Cập nhật điểm trung bình |
|---|---|---|
| INSERT | Kiểm tra toàn bộ dòng mới | Tính lại sản phẩm nhận đánh giá |
| UPDATE Rating_Score | Kiểm tra dòng sau sửa | Tính lại sản phẩm liên quan |
| UPDATE Product_ID | Kiểm tra quyền với sản phẩm mới | Tính lại cả sản phẩm cũ và mới |
| UPDATE Buyer_ID / Review_Date | Kiểm tra người mua/ngày mới | Không cần tính lại |
| UPDATE Comment | Kiểm tra dòng sau sửa | Không cần tính lại |
| DELETE | Không cần kiểm tra quyền | Tính lại sản phẩm cũ; hết đánh giá thì đặt NULL |

Cả hai trigger xử lý tập dòng, bao gồm thao tác nhiều dòng trong một câu lệnh. Điểm trung bình được tính từ dữ liệu gốc `Rating_Score`, không phụ thuộc thuộc tính dẫn xuất trung gian.

## 4. Cách chạy

### 4.1. Khởi tạo database thực hành bằng SSMS

1. Kết nối tới SQL Server bằng SSMS.
2. Mở và chạy toàn bộ `V2-shopee_schema.sql` trên môi trường được phép dựng lại dữ liệu.
3. Mở lần lượt các file trong bảng dưới và chạy toàn bộ nội dung bằng **Execute/F5**.
4. Kiểm tra cả **Results** và **Messages**. Nếu file báo lỗi, xử lý lỗi trước khi chuyển sang file tiếp theo.

| Thứ tự | Script | Kết quả cần kiểm tra |
|---:|---|---|
| 1 | `H1_triggers.sql` | Hai trigger đánh giá được tạo/cập nhật, không có lỗi thực thi |
| 2 | `H2_seed.sql` | Bảng thống kê có 17 dòng, mỗi Row_Count ≥5; bảng điểm trung bình khớp mục 5 |
| 3 | `H3_demo_tests.sql` | 26 ca PASS; Total_Cases=26 và Passed_Cases=26 |
| 4 | `H4_audit.sql` | 11 nhóm có Violation_Count=0; bảng chi tiết vi phạm không có dòng |

Thứ tự đầy đủ: **schema V2 → H1 → H2 → H3 → H4**. Cột Average_Rating và CHECK được tạo ngay trong schema.

Sửa file schema không tự cập nhật database đã tồn tại. Nếu database có dữ liệu cần giữ, cần cập nhật cấu trúc bằng ALTER TABLE phù hợp trước khi chạy H1; không chạy lại schema dựng mới vì file có DROP TABLE.

Mỗi script tự chọn database `ShopeeDB`. H2 và H3 phải chạy trong kết nối không có giao dịch đang mở. H2 yêu cầu database sạch; không nạp H2 lần hai lên bộ dữ liệu đã tồn tại.

### 4.2. Chạy H1–H4 bằng sqlcmd

Sau khi đã khởi tạo schema, mở PowerShell tại thư mục chứa README này. Ví dụ sử dụng Windows Authentication và SQL Server tại `localhost`:

```powershell
$serverName = 'localhost'
$scriptFiles = @(
    'H1_triggers.sql'
    'H2_seed.sql'
    'H3_demo_tests.sql'
    'H4_audit.sql'
)

foreach ($scriptFile in $scriptFiles) {
    sqlcmd -S $serverName -E -C -I -b -f 65001 -i $scriptFile
    if ($LASTEXITCODE -ne 0) {
        throw "Dừng thực thi do lỗi trong $scriptFile"
    }
}
```

Thay `$serverName` theo máy chủ/instance thực tế. `-E` dùng Windows Authentication; nếu kết nối bằng SQL Server Authentication, thay `-E` bằng `-U ten_dang_nhap` và nhập mật khẩu khi được yêu cầu.

`-I` bật QUOTED_IDENTIFIER, `-b` trả mã lỗi để dừng khi script thất bại, `-f 65001` đọc UTF-8 và `-C` tin cậy chứng chỉ máy chủ cho kết nối thực hành. Khi máy chủ có chứng chỉ hợp lệ và được máy khách tin cậy, có thể bỏ `-C`.

### 4.3. Chạy lại và đọc lỗi

- **H1:** có thể chạy lại để cập nhật định nghĩa trigger và đồng bộ điểm hiện có.
- **H2:** chỉ chạy trên dữ liệu sạch. Muốn nạp lại toàn bộ mẫu, dựng lại schema trên DB thực hành rồi chạy lại từ H1.
- **H3:** có thể chạy lại trên dữ liệu mẫu chuẩn. Mỗi ca rollback dữ liệu nghiệp vụ; bộ đếm IDENTITY vẫn có thể tăng.
- **H4:** có thể chạy lại để kiểm tra dữ liệu hiện tại.

| Mã lỗi | Ý nghĩa |
|---:|---|
| 51100 | H2 phát hiện dữ liệu đã có hoặc giao dịch đang mở |
| 51101 | Người đánh giá chưa có đơn giao thành công chứa đúng sản phẩm |
| 51102 | Không có ngày giao hợp lệ phù hợp với ngày đánh giá |
| 51110 | H3 được chạy khi đã có giao dịch đang mở |
| 51111 | Có ca kiểm thử H3 thất bại; xem Result, Actual_Error và Detail |
| 51112 | H4 tìm thấy dữ liệu vi phạm; xem bảng chi tiết |

## 5. Dữ liệu mẫu và kết quả mong đợi

### 5.1. Số dòng từng bảng

| Bảng | Số dòng | Bảng | Số dòng |
|---|---:|---|---:|
| Users | 8 | User_Phone | 10 |
| Address | 11 | Buyer | 8 |
| Seller | 5 | Voucher | 6 |
| Buyer_Voucher | 9 | Category | 8 |
| Product | 11 | Product_Variant | 17 |
| Product_Image | 7 | Shipping_Company | 5 |
| Orders | 12 | Order_Detail | 18 |
| Payment | 12 | Return_Request | 6 |
| Review | 9 | **Tổng** | **162** |

Mọi tài khoản mẫu đều có vai trò Buyer; tài khoản đã mở shop có thêm Seller. Dữ liệu có người mua chưa có đơn, đơn ở nhiều trạng thái, sản phẩm chưa có đánh giá và sản phẩm có nhiều đánh giá.

### 5.2. Điểm trung bình sau khi nạp H2

| Product_ID | Average_Rating |
|---|---:|
| 1 | 5.00 |
| 2 | 4.00 |
| 4 | 3.00 |
| 6 | 4.50 |
| 7 | 4.50 |
| 9 | 2.00 |
| 3, 5, 8, 10, 11 | NULL |

### 5.3. Kiểm thử H3

| Nhóm | Số ca | Nội dung |
|---|---:|---|
| QT-01…QT-15 | 15 | Đánh giá hợp lệ; đơn chưa giao/đã hủy; sai người/sản phẩm; ngày không hợp lệ; cập nhật; lệnh nhiều dòng |
| DT-01…DT-11 | 11 | Điểm ban đầu; thêm/sửa/xóa; xóa đánh giá cuối; chuyển sản phẩm; thao tác bị từ chối; thao tác nhiều dòng |

Một ca PASS phải đồng thời có mã lỗi/thành công đúng kỳ vọng, dữ liệu sau thao tác đúng và mọi điểm trung bình lưu khớp kết quả tính trực tiếp từ Review.

`Ratings_Before` và `Product_Ratings` là điểm trước/sau thao tác, được lấy trước rollback. Các ca độc lập và sử dụng lại dữ liệu chuẩn. Kết quả được sắp theo mã nên DT xuất hiện trước QT.

### 5.4. Kiểm tra dữ liệu H4

H4 xuất ba bảng kết quả:

1. Tạm tính, tiền giảm, phí giao và tổng tiền từng đơn.
2. Số vi phạm của 11 nhóm A01–A11.
3. Khóa bản ghi và chi tiết từng vi phạm.

Các nhóm kiểm tra gồm: số tiền thanh toán, hiệu lực/ngưỡng/số lượt voucher, ngày giao, căn cứ và ngày đánh giá, vai trò Buyer, biến thể sản phẩm, tuổi Seller và điểm trung bình. Kết quả hợp lệ là cả 11 nhóm có số vi phạm bằng 0 và bảng chi tiết trống.

Các số liệu trong mục này là **kết quả mong đợi để đối chiếu sau khi chạy script**, không phải biên bản nghiệm thu SQL Server.

## 6. Điều kiện tích hợp

- **Cột điểm trung bình:** schema V2 định nghĩa `Product.Average_Rating DECIMAL(3,2) NULL` cùng CHECK `CK_Product_AvgRating`. H1 duy trì cột này từ Review; ứng dụng không tự cập nhật điểm.
- **Phạm vi nghiệp vụ:** hai trigger chỉ xử lý Review. Các chức năng vòng đời đơn, trừ/hoàn kho, thanh toán và trả hàng cần được triển khai trong phần tương ứng của hệ thống.
- **Dữ liệu lịch sử:** việc sửa/xóa Orders, Order_Detail hoặc đổi quan hệ Product_Variant–Product có thể làm mất căn cứ đánh giá. Hệ thống tích hợp cần bảo vệ dữ liệu nguồn; H4 chỉ phát hiện sai ở thời điểm kiểm tra.
- **Cài đặt trigger:** H1 tạo/cập nhật hai trigger đánh giá và giữ nguyên các trigger khác trong database. Nếu đã cài hai trigger đơn hàng/tồn kho từ một bộ script khác, xử lý theo mục 7 khi cần gỡ chúng.
- **Giao dịch:** trigger nghiệp vụ dùng ROLLBACK toàn giao dịch hiện tại. Ứng dụng cần bắt lỗi phù hợp; giao dịch ghi đồng thời có thể cần retry khi gặp deadlock.
- **Kiểm tra sau ghép:** chạy lại H3 và H4 với bộ schema/trigger tích hợp. Audit không có vi phạm không thay thế việc kiểm thử thao tác bị chặn và giao dịch đồng thời.

## 7. Gỡ trigger đơn hàng/tồn kho khi thay thế bộ cài đặt

Trên database vừa tạo từ schema V2, chỉ cần chạy theo mục 4. Nếu database đã có `trg_Order_Detail_Checkout` và `trg_Orders_StatusFlow`, hai trigger đó vẫn hoạt động sau khi chạy H1.

Chỉ sử dụng đoạn dưới khi đã xác định hai trigger này không còn cần thiết hoặc đã được thay thế bởi chức năng tương ứng trong bộ SQL tích hợp. Việc gỡ sẽ loại bỏ các kiểm tra/cập nhật mà chúng thực hiện.

```sql
USE ShopeeDB;
GO
DROP TRIGGER IF EXISTS dbo.trg_Order_Detail_Checkout;
DROP TRIGGER IF EXISTS dbo.trg_Orders_StatusFlow;
GO
```

Sau khi thay đổi bộ trigger, chạy lại H3/H4 và bộ kiểm thử đơn hàng/tồn kho của hệ thống tích hợp.
