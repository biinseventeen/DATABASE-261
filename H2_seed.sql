/* H2 - Nạp dữ liệu mẫu có ý nghĩa cho 17 bảng, mỗi bảng ít nhất 5 dòng.
   Tạo tài khoản, sản phẩm, đơn hàng, thanh toán, trả hàng và đánh giá;
   cập nhật trạng thái mẫu, thống kê số dòng và hiển thị điểm trung bình. */
USE ShopeeDB;
GO
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET XACT_ABORT ON;
GO

IF @@TRANCOUNT <> 0
    THROW 51100, N'Hãy chạy H2 trong cửa sổ không có giao dịch đang mở.', 1;

IF EXISTS (SELECT 1 FROM dbo.Users)
    THROW 51100, N'H2_seed.sql chỉ chạy trên CSDL sạch: dbo.Users đã có dữ liệu. Chạy lại V2-shopee_schema.sql trước.', 1;
BEGIN TRY
    BEGIN TRANSACTION;

    -- 1. Tài khoản, số điện thoại, địa chỉ, vai trò Buyer / Seller
    SET IDENTITY_INSERT dbo.Users ON;
    INSERT INTO dbo.Users (User_ID, Username, Fullname, [Password], Email, Gender, Date_of_Birth) VALUES
        (1, N'an.nguyen', N'Nguyễn Văn An', N'Pw@An2026x', N'an.nguyen@example.com', N'Male', '1995-03-12'),
        (2, N'binh.tran', N'Trần Thị Bình', N'Pw@Binh2026x', N'binh.tran@example.com', N'Female', '1998-07-25'),
        (3, N'chi.le', N'Lê Minh Chi', N'Pw@Chi2026x', N'chi.le@example.com', N'Female', '2000-11-02'),
        (4, N'dung.pham', N'Phạm Quốc Dũng', N'Pw@Dung2026x', N'dung.pham@example.com', N'Male', '1992-01-30'),
        (5, N'ha.hoang', N'Hoàng Thu Hà', N'Pw@Ha2026xyz', N'ha.hoang@example.com', N'Female', '1997-09-18'),
        (6, N'khoa.vu', N'Vũ Đăng Khoa', N'Pw@Khoa2026x', N'khoa.vu@example.com', N'Male', '2001-05-09'),
        (7, N'lan.do', N'Đỗ Ngọc Lan', N'Pw@Lan2026xy', N'lan.do@example.com', N'Female', '1999-12-21'),
        (8, N'minh.bui', N'Bùi Quang Minh', N'Pw@Minh2026x', N'minh.bui@example.com', N'Other', '2003-08-14');
    SET IDENTITY_INSERT dbo.Users OFF;
    INSERT INTO dbo.User_Phone (User_ID, Phone_Number) VALUES
        (1, N'0901234567'),
        (1, N'0281234567'),
        (2, N'0912345678'),
        (3, N'0933456789'),
        (4, N'0944567890'),
        (5, N'0955678901'),
        (6, N'0966789012'),
        (6, N'0286789012'),
        (7, N'0977890123'),
        (8, N'+84988901234');
    INSERT INTO dbo.Address (User_ID, Street, Ward, District, City, Address_Type) VALUES
        (1, N'12 Nguyễn Huệ', N'Bến Nghé', N'Quận 1', N'TP. Hồ Chí Minh', N'Office'),
        (1, N'45 Lê Lợi', N'Bến Thành', N'Quận 1', N'TP. Hồ Chí Minh', N'Home'),
        (2, N'88 Trần Hưng Đạo', N'Phường 7', N'Quận 5', N'TP. Hồ Chí Minh', N'Home'),
        (3, N'25 Hai Bà Trưng', N'Tân Định', N'Quận 1', N'TP. Hồ Chí Minh', N'Home'),
        (4, N'102 Cầu Giấy', N'Dịch Vọng', N'Cầu Giấy', N'Hà Nội', N'Office'),
        (5, N'7 Nguyễn Văn Linh', N'Hải Châu 1', N'Hải Châu', N'Đà Nẵng', N'Home'),
        (6, N'56 Lý Thường Kiệt', N'Phường 14', N'Quận 10', N'TP. Hồ Chí Minh', N'Home'),
        (6, N'200 Điện Biên Phủ', N'Phường 7', N'Quận 3', N'TP. Hồ Chí Minh', N'Office'),
        (7, N'31 Hoàng Diệu', N'Phường 12', N'Quận 4', N'TP. Hồ Chí Minh', N'Home'),
        (7, N'15 Pasteur', N'Bến Nghé', N'Quận 1', N'TP. Hồ Chí Minh', N'Office'),
        (8, N'9 Phan Chu Trinh', N'Phường 2', N'Bình Thạnh', N'TP. Hồ Chí Minh', N'Home');
    INSERT INTO dbo.Buyer (User_ID) VALUES
        (1),
        (2),
        (3),
        (4),
        (5),
        (6),
        (7),
        (8);
    INSERT INTO dbo.Seller (User_ID, Shop_Name, Shop_Description, Tax_ID) VALUES
        (1, N'An Tech Store', N'Điện thoại, laptop và phụ kiện chính hãng', N'0312345678'),
        (2, N'Bình Fashion', N'Thời trang nữ công sở và dạo phố', NULL),
        (3, N'Chi Beauty House', N'Mỹ phẩm chăm sóc da chính hãng', N'0398765432-001'),
        (4, N'Dũng Books & Stationery', N'Sách giáo trình và văn phòng phẩm', N'0301234567'),
        (5, N'Hà Home Decor', N'Đồ gia dụng và trang trí nhà cửa', NULL);

    -- 2. Voucher và voucher người mua đã nhận
    INSERT INTO dbo.Voucher (Voucher_Code, Discount_Percent, Min_Order_Value, Max_Discount_Amount, Quantity, Start_Date, End_Date) VALUES
        (N'SALE10', 10, 200000, 50000, 100, '2026-10-01', '2026-12-31'),
        (N'NEWUSER20', 20, 100000, 80000, 50, '2026-10-01', '2026-11-30'),
        (N'MEGA30', 30, 1000000, 300000, 5, '2026-11-01', '2026-11-30'),
        (N'BOOK15', 15, 150000, 40000, 20, '2026-10-15', '2026-12-15'),
        (N'VIP50', 50, 2000000, 500000, 2, '2026-11-10', '2026-11-20'),
        (N'FLASH25', 25, 300000, 100000, 10, '2026-09-01', '2026-09-30');
    INSERT INTO dbo.Buyer_Voucher (Buyer_ID, Voucher_Code) VALUES
        (6, N'SALE10'),
        (6, N'NEWUSER20'),
        (7, N'SALE10'),
        (7, N'MEGA30'),
        (1, N'BOOK15'),
        (2, N'SALE10'),
        (3, N'NEWUSER20'),
        (5, N'VIP50'),
        (4, N'FLASH25');

    -- 3. Danh mục (cha trước, con sau), sản phẩm, biến thể, ảnh, đơn vị vận chuyển
    SET IDENTITY_INSERT dbo.Category ON;
    INSERT INTO dbo.Category (Category_ID, Category_Name, Parent_Category_ID) VALUES
        (1, N'Điện tử', NULL),
        (4, N'Thời trang', NULL),
        (6, N'Sách và văn phòng phẩm', NULL),
        (7, N'Nhà cửa và đời sống', NULL),
        (8, N'Sắc đẹp', NULL),
        (2, N'Điện thoại', 1),
        (3, N'Laptop', 1),
        (5, N'Thời trang nữ', 4);
    SET IDENTITY_INSERT dbo.Category OFF;
    SET IDENTITY_INSERT dbo.Product ON;
    INSERT INTO dbo.Product (Product_ID, Name, Description, Category_ID, Seller_ID) VALUES
        (1, N'Điện thoại Galaxy A55 5G', N'Màn hình 6.6 inch, pin 5000 mAh', 2, 1),
        (2, N'Tai nghe Bluetooth Soundcore', N'Chống ồn chủ động, pin 40 giờ', 1, 1),
        (3, N'Laptop Asus Vivobook 15', N'Ryzen 5, RAM 16GB, màn 15.6 inch', 3, 1),
        (4, N'Áo sơ mi nữ công sở', N'Vải lụa mềm, ít nhăn', 5, 2),
        (5, N'Váy hoa dáng xòe', N'Chất voan, dài qua gối', 5, 2),
        (6, N'Kem chống nắng SPF50+', N'Không gây bết dính, phù hợp da dầu', 8, 3),
        (7, N'Giáo trình Hệ cơ sở dữ liệu', N'Bản in mới, bìa mềm', 6, 4),
        (8, N'Sổ tay bìa da A5', N'200 trang, giấy kem', 6, 4),
        (9, N'Đèn ngủ gỗ để bàn', N'Ánh sáng vàng ấm, có cổng USB', 7, 5),
        (10, N'Bình giữ nhiệt 500ml', N'Giữ nóng 12 giờ, inox 304', 7, 5),
        (11, N'Ốp lưng điện thoại trong suốt', N'Chống sốc, viền silicone', 2, 1);
    SET IDENTITY_INSERT dbo.Product OFF;
    SET IDENTITY_INSERT dbo.Product_Variant ON;
    INSERT INTO dbo.Product_Variant (Variant_ID, Product_ID, Variant_Name, Current_Price, Stock_Quantity) VALUES
        (1, 1, N'128GB - Đen', 6990000, 40),
        (2, 1, N'256GB - Xanh', 8490000, 25),
        (3, 2, N'Đen', 790000, 100),
        (4, 2, N'Trắng', 790000, 80),
        (5, 3, N'Ryzen 5 / 16GB / 512GB', 14990000, 15),
        (6, 4, N'Size M', 189000, 60),
        (7, 4, N'Size L', 189000, 45),
        (8, 5, N'Size M', 259000, 30),
        (9, 6, N'50ml', 165000, 120),
        (10, 7, N'Bản tiêu chuẩn', 95000, 200),
        (11, 8, N'Nâu', 120000, 70),
        (12, 8, N'Đen', 120000, 70),
        (13, 9, N'Mặc định', 350000, 25),
        (14, 10, N'Xanh', 220000, 50),
        (15, 10, N'Hồng', 220000, 50),
        (16, 6, N'30ml', 99000, 90),
        (17, 11, N'Trong suốt', 49000, 150);
    SET IDENTITY_INSERT dbo.Product_Variant OFF;
    INSERT INTO dbo.Product_Image (Product_ID, Image_URL) VALUES
        (1, N'https://img.example.com/p1/front.jpg'),
        (1, N'https://img.example.com/p1/back.jpg'),
        (2, N'https://img.example.com/p2/main.jpg'),
        (4, N'https://img.example.com/p4/main.jpg'),
        (6, N'https://img.example.com/p6/main.jpg'),
        (7, N'https://img.example.com/p7/cover.jpg'),
        (9, N'https://img.example.com/p9/main.jpg');
    SET IDENTITY_INSERT dbo.Shipping_Company ON;
    INSERT INTO dbo.Shipping_Company (Company_ID, Company_Name) VALUES
        (1, N'Giao Hàng Nhanh'),
        (2, N'Giao Hàng Tiết Kiệm'),
        (3, N'Viettel Post'),
        (4, N'J&T Express'),
        (5, N'Shopee Express');
    SET IDENTITY_INSERT dbo.Shipping_Company OFF;

    -- 4. Đơn hàng: chèn ở 'Pending Confirmation', thêm dòng chi tiết, rồi đi qua vòng đời
    SET IDENTITY_INSERT dbo.Orders ON;
    INSERT INTO dbo.Orders (Order_ID, Order_Date, Shipping_Fee, Company_ID, Voucher_Code, Buyer_ID, Street, Ward, District, City) VALUES
        (1, '2026-10-05T09:15:00', 25000, 1, NULL, 6, N'56 Lý Thường Kiệt', N'Phường 14', N'Quận 10', N'TP. Hồ Chí Minh'),
        (2, '2026-10-12T14:20:00', 30000, 2, N'SALE10', 7, N'31 Hoàng Diệu', N'Phường 12', N'Quận 4', N'TP. Hồ Chí Minh'),
        (3, '2026-10-20T10:05:00', 35000, 3, N'NEWUSER20', 6, N'200 Điện Biên Phủ', N'Phường 7', N'Quận 3', N'TP. Hồ Chí Minh'),
        (4, '2026-11-02T19:40:00', 22000, 4, NULL, 7, N'15 Pasteur', N'Bến Nghé', N'Quận 1', N'TP. Hồ Chí Minh'),
        (5, '2026-10-18T08:30:00', 20000, 1, N'BOOK15', 1, N'12 Nguyễn Huệ', N'Bến Nghé', N'Quận 1', N'TP. Hồ Chí Minh'),
        (6, '2026-10-28T21:00:00', 25000, 5, N'SALE10', 2, N'88 Trần Hưng Đạo', N'Phường 7', N'Quận 5', N'TP. Hồ Chí Minh'),
        (7, '2026-11-10T11:10:00', 18000, 4, N'NEWUSER20', 3, N'25 Hai Bà Trưng', N'Tân Định', N'Quận 1', N'TP. Hồ Chí Minh'),
        (8, '2026-11-12T15:50:00', 50000, 1, NULL, 6, N'56 Lý Thường Kiệt', N'Phường 14', N'Quận 10', N'TP. Hồ Chí Minh'),
        (9, '2026-11-15T09:00:00', 22000, 2, NULL, 7, N'31 Hoàng Diệu', N'Phường 12', N'Quận 4', N'TP. Hồ Chí Minh'),
        (10, '2026-11-03T20:15:00', 20000, 3, NULL, 4, N'102 Cầu Giấy', N'Dịch Vọng', N'Cầu Giấy', N'Hà Nội'),
        (11, '2026-11-01T10:00:00', 20000, 5, NULL, 5, N'7 Nguyễn Văn Linh', N'Hải Châu 1', N'Hải Châu', N'Đà Nẵng'),
        (12, '2026-11-14T13:30:00', 35000, 1, N'MEGA30', 7, N'15 Pasteur', N'Bến Nghé', N'Quận 1', N'TP. Hồ Chí Minh');
    SET IDENTITY_INSERT dbo.Orders OFF;
    INSERT INTO dbo.Order_Detail (Order_ID, Variant_ID, Purchased_Quantity, Unit_Price_At_Order_Time) VALUES
        (1, 3, 2, 790000),
        (1, 10, 1, 95000),
        (2, 6, 2, 189000),
        (2, 9, 1, 165000),
        (3, 1, 1, 6990000),
        (4, 13, 1, 350000),
        (4, 11, 2, 120000),
        (5, 10, 2, 95000),
        (6, 4, 1, 790000),
        (7, 14, 2, 220000),
        (8, 5, 1, 14990000),
        (9, 8, 1, 259000),
        (9, 16, 1, 99000),
        (10, 7, 1, 189000),
        (11, 9, 2, 165000),
        (11, 16, 1, 99000),
        (12, 2, 1, 8490000),
        (12, 3, 1, 790000);

    -- 4b. Vòng đời đơn: Pending Confirmation -> Confirmed -> Shipping -> Delivery Successful (hoặc Cancelled)
    UPDATE dbo.Orders SET Status = 'Confirmed' WHERE Order_ID IN (1, 2, 3, 4, 5, 6, 7, 8, 11, 12);
    UPDATE dbo.Orders SET Status = 'Shipping'  WHERE Order_ID IN (1, 2, 3, 4, 5, 6, 7, 11);
    UPDATE dbo.Orders SET Status = 'Delivery Successful', Delivered_At = '2026-10-09T10:30:00' WHERE Order_ID = 1;
    UPDATE dbo.Orders SET Status = 'Delivery Successful', Delivered_At = '2026-10-16T16:00:00' WHERE Order_ID = 2;
    UPDATE dbo.Orders SET Status = 'Delivery Successful', Delivered_At = '2026-10-25T11:45:00' WHERE Order_ID = 3;
    UPDATE dbo.Orders SET Status = 'Delivery Successful', Delivered_At = '2026-11-07T14:00:00' WHERE Order_ID = 4;
    UPDATE dbo.Orders SET Status = 'Delivery Successful', Delivered_At = '2026-10-22T09:10:00' WHERE Order_ID = 5;
    UPDATE dbo.Orders SET Status = 'Delivery Successful', Delivered_At = '2026-11-03T13:25:00' WHERE Order_ID = 6;
    UPDATE dbo.Orders SET Status = 'Delivery Successful', Delivered_At = '2026-11-06T15:30:00' WHERE Order_ID = 11;
    UPDATE dbo.Orders SET Status = 'Cancelled' WHERE Order_ID = 10;

    -- 5. Thanh toán: Amount = Total_Amount của đơn; chèn Pending rồi chuyển trạng thái
    SET IDENTITY_INSERT dbo.Payment ON;
    INSERT INTO dbo.Payment (Payment_ID, Method, Amount, Order_ID) VALUES
        (1, N'COD', 1700000, 1),
        (2, N'E-Wallet', 523000, 2),
        (3, N'Credit Card', 6945000, 3),
        (4, N'Bank Transfer', 612000, 4),
        (5, N'COD', 181500, 5),
        (6, N'E-Wallet', 765000, 6),
        (7, N'Bank Transfer', 378000, 7),
        (8, N'Bank Transfer', 15040000, 8),
        (9, N'COD', 380000, 9),
        (10, N'Credit Card', 209000, 10),
        (11, N'COD', 449000, 11),
        (12, N'E-Wallet', 9015000, 12);
    SET IDENTITY_INSERT dbo.Payment OFF;
    UPDATE dbo.Payment SET Payment_Status = 'Paid', Paid_Date = '2026-10-09T10:45:00' WHERE Payment_ID = 1;
    UPDATE dbo.Payment SET Payment_Status = 'Refunded' WHERE Payment_ID = 1;
    UPDATE dbo.Payment SET Payment_Status = 'Paid', Paid_Date = '2026-10-12T14:25:00' WHERE Payment_ID = 2;
    UPDATE dbo.Payment SET Payment_Status = 'Paid', Paid_Date = '2026-10-20T10:10:00' WHERE Payment_ID = 3;
    UPDATE dbo.Payment SET Payment_Status = 'Paid', Paid_Date = '2026-11-02T19:45:00' WHERE Payment_ID = 4;
    UPDATE dbo.Payment SET Payment_Status = 'Paid', Paid_Date = '2026-10-22T09:20:00' WHERE Payment_ID = 5;
    UPDATE dbo.Payment SET Payment_Status = 'Paid', Paid_Date = '2026-10-28T21:05:00' WHERE Payment_ID = 6;
    UPDATE dbo.Payment SET Payment_Status = 'Paid', Paid_Date = '2026-11-10T11:15:00' WHERE Payment_ID = 7;
    UPDATE dbo.Payment SET Payment_Status = 'Paid', Paid_Date = '2026-11-12T15:55:00' WHERE Payment_ID = 8;
    UPDATE dbo.Payment SET Payment_Status = 'Failed' WHERE Payment_ID = 10;
    UPDATE dbo.Payment SET Payment_Status = 'Paid', Paid_Date = '2026-11-06T15:40:00' WHERE Payment_ID = 11;

    -- 6. Yêu cầu trả hàng (đúng đơn, đúng người mua): chèn Requested rồi chuyển trạng thái
    SET IDENTITY_INSERT dbo.Return_Request ON;
    INSERT INTO dbo.Return_Request (Return_ID, Request_Date, Reason, Order_ID, Buyer_ID) VALUES
        (1, '2026-10-11T09:00:00', N'Tai nghe bị rè âm bên trái', 1, 6),
        (2, '2026-10-18T10:30:00', N'Áo không đúng kích cỡ đã đặt', 2, 7),
        (3, '2026-10-27T08:45:00', N'Điện thoại có vết xước trên vỏ', 3, 6),
        (4, '2026-11-09T20:00:00', N'Đèn ngủ bị vỡ chân đế khi nhận hàng', 4, 7),
        (5, '2026-11-05T12:15:00', N'Tai nghe không kết nối được Bluetooth', 6, 2),
        (6, '2026-11-08T17:20:00', N'Kem chống nắng đã hết hạn sử dụng', 11, 5);
    SET IDENTITY_INSERT dbo.Return_Request OFF;
    UPDATE dbo.Return_Request SET Return_Status = 'Approved', Refund_Amount = 790000 WHERE Return_ID = 1;
    UPDATE dbo.Return_Request SET Return_Status = 'Refunded' WHERE Return_ID = 1;
    UPDATE dbo.Return_Request SET Return_Status = 'Approved', Refund_Amount = 189000 WHERE Return_ID = 2;
    UPDATE dbo.Return_Request SET Return_Status = 'Rejected' WHERE Return_ID = 3;
    UPDATE dbo.Return_Request SET Return_Status = 'Approved', Refund_Amount = 330000 WHERE Return_ID = 6;

    -- 7. Đánh giá: chỉ cho sản phẩm có trong đơn 'Delivery Successful' của chính người mua, ngày >= ngày giao.
    --    Một INSERT nhiều dòng: H1 kiểm tra cả tập và tính điểm cho các sản phẩm liên quan.
    SET IDENTITY_INSERT dbo.Review ON;
    INSERT INTO dbo.Review (Product_ID, Review_ID, Buyer_ID, Rating_Score, Comment, Review_Date) VALUES
        (2, 1, 6, 5, N'Âm thanh tốt, pin trâu, chống ồn ổn.', '2026-10-11T20:10:00'),
        (7, 2, 6, 4, N'Giáo trình dễ hiểu, nhiều ví dụ SQL.', '2026-10-12T21:00:00'),
        (1, 3, 6, 5, N'Máy chạy mượt, màn hình đẹp.', '2026-10-27T09:30:00'),
        (4, 4, 7, 3, N'Vải ổn nhưng form hơi rộng so với size M.', '2026-10-18T19:00:00'),
        (6, 5, 7, 5, N'Thấm nhanh, không bết dính.', '2026-10-18T19:05:00'),
        (9, 6, 7, 2, N'Đèn hơi tối so với mô tả.', '2026-11-09T22:00:00'),
        (7, 7, 1, 5, N'Sách hay, giao nhanh.', '2026-10-24T18:45:00'),
        (2, 8, 2, 3, N'Dùng được nhưng kết nối đôi khi chập chờn.', '2026-11-05T10:20:00'),
        (6, 9, 5, 4, N'Dùng tốt, đóng gói cẩn thận.', '2026-11-08T09:00:00');
    SET IDENTITY_INSERT dbo.Review OFF;

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    -- IDENTITY_INSERT là thiết lập của phiên, cần tắt cả khi nạp bị lỗi.
    SET IDENTITY_INSERT dbo.Users OFF;
    SET IDENTITY_INSERT dbo.Category OFF;
    SET IDENTITY_INSERT dbo.Product OFF;
    SET IDENTITY_INSERT dbo.Product_Variant OFF;
    SET IDENTITY_INSERT dbo.Shipping_Company OFF;
    SET IDENTITY_INSERT dbo.Orders OFF;
    SET IDENTITY_INSERT dbo.Payment OFF;
    SET IDENTITY_INSERT dbo.Return_Request OFF;
    SET IDENTITY_INSERT dbo.Review OFF;
    THROW;
END CATCH;
GO

-- 8. Đếm dòng từng bảng (mỗi bảng phải >= 5)
SELECT 'Users' AS Table_Name, COUNT(*) AS Row_Count FROM dbo.Users
UNION ALL SELECT 'User_Phone', COUNT(*) FROM dbo.User_Phone
UNION ALL SELECT 'Address', COUNT(*) FROM dbo.Address
UNION ALL SELECT 'Buyer', COUNT(*) FROM dbo.Buyer
UNION ALL SELECT 'Seller', COUNT(*) FROM dbo.Seller
UNION ALL SELECT 'Voucher', COUNT(*) FROM dbo.Voucher
UNION ALL SELECT 'Buyer_Voucher', COUNT(*) FROM dbo.Buyer_Voucher
UNION ALL SELECT 'Category', COUNT(*) FROM dbo.Category
UNION ALL SELECT 'Product', COUNT(*) FROM dbo.Product
UNION ALL SELECT 'Product_Variant', COUNT(*) FROM dbo.Product_Variant
UNION ALL SELECT 'Product_Image', COUNT(*) FROM dbo.Product_Image
UNION ALL SELECT 'Shipping_Company', COUNT(*) FROM dbo.Shipping_Company
UNION ALL SELECT 'Orders', COUNT(*) FROM dbo.Orders
UNION ALL SELECT 'Order_Detail', COUNT(*) FROM dbo.Order_Detail
UNION ALL SELECT 'Payment', COUNT(*) FROM dbo.Payment
UNION ALL SELECT 'Return_Request', COUNT(*) FROM dbo.Return_Request
UNION ALL SELECT 'Review', COUNT(*) FROM dbo.Review
ORDER BY Table_Name;
SELECT Product_ID, Name, Average_Rating FROM dbo.Product ORDER BY Product_ID;
GO
