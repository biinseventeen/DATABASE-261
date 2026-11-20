# Hợp đồng tích hợp frontend với ShopeeDB

Frontend có hai vai trò trên cùng ứng dụng: **người mua** xem sản phẩm, chọn biến thể, thêm giỏ và đặt hàng; **người bán** quản lý sản phẩm, ảnh, biến thể, giá và tồn kho. Trình duyệt gọi REST API cùng origin tại `/api`, không kết nối SQL Server trực tiếp.

## Ánh xạ giao diện vào schema

| Giao diện | Bảng / dữ liệu |
|---|---|
| Tài khoản mua, tên và địa chỉ giao | `Buyer` → `Users`, `Address` |
| Shop đăng bán sản phẩm | `Seller` → `Users` |
| Tên, mô tả, danh mục và đánh giá trung bình | `Product`, `Category`, `Review` / `Product.Average_Rating` |
| Phân loại, giá bán, tồn kho | `Product_Variant.Variant_Name`, `Current_Price`, `Stock_Quantity` |
| Nhiều ảnh sản phẩm | `Product_Image.Image_URL` |
| Giỏ / dòng sản phẩm đã đặt | `Orders`, `Order_Detail` |
| Mã vận chuyển, voucher và thanh toán | `Shipping_Company`, `Voucher` + `Buyer_Voucher`, `Payment` |

Giá bắt buộc là số nguyên VND trong khoảng `1..1,000,000,000`; tồn kho là số nguyên không âm. Mỗi sản phẩm cần ít nhất một biến thể. Mỗi biến thể phải có tên riêng trong cùng sản phẩm. Ảnh là URL `http/https` tối đa 400 ký tự. Phí giao hàng theo schema là `0..5,000,000`.

## API đọc dữ liệu

| Method | Path | Mục đích |
|---|---|---|
| GET | `/api/products?searchTerm=&categoryId=&sellerId=` | Danh sách sản phẩm cho cửa hàng và kênh người bán; backend gọi `dbo.usp_Product_List` |
| GET | `/api/products/{productId}` | Chi tiết sản phẩm, các biến thể (`Product_Variant`) và danh sách ảnh (`Product_Image`) |
| GET | `/api/lookups/categories` | Danh mục sản phẩm |
| GET | `/api/lookups/sellers` | Shop, trả `sellerId` và `shopName` |
| GET | `/api/lookups/buyers` | Tài khoản Buyer cho demo đặt hàng |
| GET | `/api/lookups/shipping-companies` | Đơn vị vận chuyển; API có thể trả `estimatedShippingFee` từ cấu hình vì bảng `Shipping_Company` không lưu phí |
| GET | `/api/buyers/{buyerId}/addresses` | Địa chỉ của Buyer đó |
| GET | `/api/buyers/{buyerId}/vouchers` | Voucher đã cấp cho Buyer; backend chỉ trả voucher còn hợp lệ |
| GET | `/api/buyers/{buyerId}/orders` | Lịch sử mua hàng, tổng tiền dẫn xuất và trạng thái thanh toán |
| GET | `/api/reports/top-products?minOrders=1` | Procedure thống kê 2.3 do a Hải bàn giao |

Sản phẩm từ `GET /api/products` có thể trả PascalCase theo kết quả SQL hoặc camelCase. Frontend đọc được cả hai. Mỗi dòng cần các trường tương ứng với `Product_ID`, `Product_Name`, `Description`, `Average_Rating`, `Category_ID`, `Category_Name`, `Seller_ID`, `Seller_Username`, `Shop_Name`, `Variant_Count`, `Low_Stock_Variant_Count`, `Min_Price`, `Max_Price`, `Total_Stock`, `Image_Urls`.

Chi tiết sản phẩm trả `productId`, `productName`, `description`, `categoryId`, `categoryName`, `sellerId`, `shopName`, `averageRating`, `imageUrls[]` và `variants[]`. Mỗi biến thể gồm `variantId`, `variantName`, `currentPrice`, `stockQuantity`.

## API người bán

| Method | Path | Mục đích |
|---|---|---|
| POST | `/api/products` | Thêm `Product` cùng ít nhất một `Product_Variant` và các dòng `Product_Image` |
| PUT | `/api/products/{productId}` | Sửa thông tin sản phẩm, đồng bộ ảnh và biến thể |
| DELETE | `/api/products/{productId}` | Gọi procedure xóa; trả thông báo cụ thể nếu có dữ liệu đơn/đánh giá chặn xóa |

Ví dụ body thêm/sửa (cập nhật cha và các bảng con trong transaction):

```json
{
  "name": "Tai nghe Bluetooth",
  "description": "Chống ồn chủ động",
  "categoryId": 1,
  "sellerId": 1,
  "imageUrls": [
    "https://img.example.com/headphones-front.jpg",
    "https://img.example.com/headphones-side.jpg"
  ],
  "variants": [
    { "variantName": "Đen", "currentPrice": 790000, "stockQuantity": 100 },
    { "variantName": "Trắng", "currentPrice": 820000, "stockQuantity": 50 }
  ]
}
```

Khi sửa, backend cần giữ `variantId` cho biến thể hiện có. Các biến thể/URL bị bỏ phải được xử lý đúng khóa ngoại; không được đổi `Variant_ID` đang được tham chiếu trong `Order_Detail`. Procedure 2.1 của Kiệt hiện chưa có trong workspace, nên cần thống nhất cách CRUD Product và các bảng con với backend trước khi chạy thật.

## API người mua

| Method | Path | Mục đích |
|---|---|---|
| POST | `/api/orders` | Tạo đơn mua từ giỏ, chi tiết đơn và Payment đang chờ |

Ví dụ body đặt hàng:

```json
{
  "buyerId": 8,
  "address": {
    "street": "12 Nguyễn Huệ",
    "ward": "Bến Nghé",
    "district": "Quận 1",
    "city": "TP. Hồ Chí Minh"
  },
  "companyId": 1,
  "voucherCode": null,
  "paymentMethod": "COD",
  "shippingFee": 30000,
  "items": [
    { "variantId": 2, "quantity": 1 }
  ]
}
```

Backend phải xác nhận địa chỉ thuộc Buyer, giá hiện tại và tồn kho của từng biến thể, điều kiện voucher và phí giao hàng. Đơn, các dòng `Order_Detail` và `Payment` cần được tạo nhất quán trong transaction. Lưu giá tại thời điểm mua vào `Unit_Price_At_Order_Time`; không tin giá/tổng tiền gửi từ trình duyệt. Tính `Total_Amount` theo công thức trong `semantic_constraints_v2.txt`. Trigger phía CSDL kiểm tra các chuyển trạng thái và tồn kho liên quan.

`POST /api/orders` trả `orderId` và `totalAmount`. Lỗi validation/nghiệp vụ trả HTTP status phù hợp cùng JSON như `{ "message": "Địa chỉ giao hàng không thuộc tài khoản Buyer đã chọn." }`; frontend hiển thị thông báo đó.

## Procedure truy vấn của Thịnh

`T3_product_list.sql` tạo `dbo.usp_Product_List`. Tham số tìm kiếm, danh mục và người bán dùng trong `WHERE`; procedure chỉ truy vấn hiển thị, JOIN thông tin sản phẩm/shop/danh mục, tổng hợp giá/tồn kho biến thể và trả URL ảnh. Backend gọi procedure này cho API danh sách. Chạy sau schema V2 và dữ liệu mẫu H2.
