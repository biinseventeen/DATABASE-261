/* H4 - Tính tổng tiền đơn hàng và kiểm tra dữ liệu bằng 11 nhóm truy vấn.
   Tổng hợp số vi phạm và liệt kê các bản ghi không thỏa điều kiện kiểm tra. */
USE ShopeeDB;
GO
SET NOCOUNT ON;

DROP TABLE IF EXISTS #OrderTotals;

;WITH Subtotals AS (
    SELECT o.Order_ID,
           COALESCE(SUM(od.Purchased_Quantity * od.Unit_Price_At_Order_Time), 0) AS Subtotal
    FROM dbo.Orders AS o
    LEFT JOIN dbo.Order_Detail AS od ON od.Order_ID = o.Order_ID
    GROUP BY o.Order_ID
), Discounts AS (
    SELECT o.Order_ID, s.Subtotal, o.Shipping_Fee,
           CASE
               WHEN v.Voucher_Code IS NULL THEN 0
               WHEN ROUND(s.Subtotal * v.Discount_Percent / 100.0, 0) < v.Max_Discount_Amount
                   THEN ROUND(s.Subtotal * v.Discount_Percent / 100.0, 0)
               ELSE v.Max_Discount_Amount
           END AS Discount_Amount
    FROM dbo.Orders AS o
    JOIN Subtotals AS s ON s.Order_ID = o.Order_ID
    LEFT JOIN dbo.Voucher AS v ON v.Voucher_Code = o.Voucher_Code
)
SELECT Order_ID, Subtotal, Discount_Amount, Shipping_Fee,
       Subtotal - Discount_Amount + Shipping_Fee AS Total_Amount
INTO #OrderTotals
FROM Discounts;

SELECT * FROM #OrderTotals ORDER BY Order_ID;

DECLARE @Rules TABLE (Audit_ID char(3) PRIMARY KEY, Description nvarchar(200));
INSERT @Rules VALUES
('A01', N'Thanh toán Paid/Refunded khớp tổng tiền đơn'),
('A02', N'Ngày đặt đơn nằm trong thời hạn voucher'),
('A03', N'Đơn đã xác nhận đạt mức tối thiểu của voucher'),
('A04', N'Số đơn chưa hủy dùng voucher không vượt Quantity'),
('A05', N'Đơn giao thành công có Delivered_At'),
('A06', N'Người đánh giá đã nhận đúng sản phẩm'),
('A07', N'Ngày đánh giá không trước ngày giao hợp lệ'),
('A08', N'Mỗi tài khoản đều có vai trò Buyer'),
('A09', N'Mỗi sản phẩm có ít nhất một biến thể'),
('A10', N'Người bán đủ 18 tuổi tính đến hôm nay'),
('A11', N'Điểm lưu khớp điểm tính từ Review');

DECLARE @Violations TABLE (
    Audit_ID char(3) NOT NULL,
    Record_Key nvarchar(100) NOT NULL,
    Detail nvarchar(1000) NULL
);

-- A01: kiểm tra số tiền đã được xác nhận; không ép thanh toán Pending/Failed.
INSERT @Violations
SELECT 'A01', CONVERT(nvarchar(100), p.Payment_ID),
       CONCAT(N'Amount=', p.Amount, N'; Total_Amount=', t.Total_Amount)
FROM dbo.Payment AS p
JOIN #OrderTotals AS t ON t.Order_ID = p.Order_ID
WHERE p.Payment_Status IN ('Paid', 'Refunded')
  AND p.Amount <> t.Total_Amount;

-- A02: BETWEEN gồm cả ngày đầu và ngày cuối.
INSERT @Violations
SELECT 'A02', CONVERT(nvarchar(100), o.Order_ID), o.Voucher_Code
FROM dbo.Orders AS o
JOIN dbo.Voucher AS v ON v.Voucher_Code = o.Voucher_Code
WHERE CAST(o.Order_Date AS DATE) NOT BETWEEN v.Start_Date AND v.End_Date;

-- A03: ngưỡng voucher kiểm lúc xác nhận, không áp cho giỏ/đơn còn Pending.
INSERT @Violations
SELECT 'A03', CONVERT(nvarchar(100), o.Order_ID),
       CONCAT(N'Subtotal=', t.Subtotal, N'; Min_Order_Value=', v.Min_Order_Value)
FROM dbo.Orders AS o
JOIN #OrderTotals AS t ON t.Order_ID = o.Order_ID
JOIN dbo.Voucher AS v ON v.Voucher_Code = o.Voucher_Code
WHERE o.Status IN ('Confirmed', 'Shipping', 'Delivery Successful')
  AND t.Subtotal < v.Min_Order_Value;

INSERT @Violations
SELECT 'A04', v.Voucher_Code, CONCAT(N'Uses=', COUNT(o.Order_ID), N'; Quantity=', v.Quantity)
FROM dbo.Voucher AS v
JOIN dbo.Orders AS o ON o.Voucher_Code = v.Voucher_Code
WHERE o.Status <> 'Cancelled'
GROUP BY v.Voucher_Code, v.Quantity
HAVING COUNT(o.Order_ID) > v.Quantity;

INSERT @Violations
SELECT 'A05', CONVERT(nvarchar(100), Order_ID), N'Thiếu ngày giao thành công'
FROM dbo.Orders
WHERE Status = 'Delivery Successful' AND Delivered_At IS NULL;

INSERT @Violations
SELECT 'A06', CONCAT(r.Product_ID, '/', r.Review_ID), CONCAT(N'Buyer_ID=', r.Buyer_ID)
FROM dbo.Review AS r
WHERE NOT EXISTS (
    SELECT 1
    FROM dbo.Orders AS o
    JOIN dbo.Order_Detail AS od ON od.Order_ID = o.Order_ID
    JOIN dbo.Product_Variant AS pv ON pv.Variant_ID = od.Variant_ID
    WHERE o.Buyer_ID = r.Buyer_ID
      AND o.Status = 'Delivery Successful'
      AND pv.Product_ID = r.Product_ID
);

INSERT @Violations
SELECT 'A07', CONCAT(r.Product_ID, '/', r.Review_ID), CONVERT(nvarchar(30), r.Review_Date, 126)
FROM dbo.Review AS r
WHERE NOT EXISTS (
    SELECT 1
    FROM dbo.Orders AS o
    JOIN dbo.Order_Detail AS od ON od.Order_ID = o.Order_ID
    JOIN dbo.Product_Variant AS pv ON pv.Variant_ID = od.Variant_ID
    WHERE o.Buyer_ID = r.Buyer_ID
      AND o.Status = 'Delivery Successful'
      AND pv.Product_ID = r.Product_ID
      AND CAST(r.Review_Date AS DATE) >= CAST(o.Delivered_At AS DATE)
);

-- A08 dùng quy ước người dùng đã chốt: tạo tài khoản là Buyer, chưa cần mua.
-- Có thể đồng thời là Seller sau khi mở shop. Không chỉ kiểm Buyer OR Seller.
INSERT @Violations
SELECT 'A08', CONVERT(nvarchar(100), u.User_ID), N'Tài khoản chưa có dòng Buyer'
FROM dbo.Users AS u
WHERE NOT EXISTS (SELECT 1 FROM dbo.Buyer AS b WHERE b.User_ID = u.User_ID);

INSERT @Violations
SELECT 'A09', CONVERT(nvarchar(100), p.Product_ID), N'Sản phẩm chưa có biến thể'
FROM dbo.Product AS p
WHERE NOT EXISTS (SELECT 1 FROM dbo.Product_Variant AS v WHERE v.Product_ID = p.Product_ID);

INSERT @Violations
SELECT 'A10', CONVERT(nvarchar(100), s.User_ID), CONVERT(nvarchar(10), u.Date_of_Birth, 23)
FROM dbo.Seller AS s
JOIN dbo.Users AS u ON u.User_ID = s.User_ID
WHERE u.Date_of_Birth > DATEADD(YEAR, -18, CAST(GETDATE() AS DATE));

INSERT @Violations
SELECT 'A11', CONVERT(nvarchar(100), p.Product_ID),
       CONCAT(N'Average_Rating=', COALESCE(CONVERT(varchar(10), p.Average_Rating), 'NULL'))
FROM dbo.Product AS p
WHERE COALESCE(p.Average_Rating, -1) <> COALESCE((
    SELECT CAST(AVG(CAST(r.Rating_Score AS DECIMAL(10,4))) AS DECIMAL(3,2))
    FROM dbo.Review AS r WHERE r.Product_ID = p.Product_ID
), -1);

SELECT a.Audit_ID, a.Description, COUNT(v.Audit_ID) AS Violation_Count
FROM @Rules AS a
LEFT JOIN @Violations AS v ON v.Audit_ID = a.Audit_ID
GROUP BY a.Audit_ID, a.Description
ORDER BY a.Audit_ID;

SELECT Audit_ID, Record_Key, Detail FROM @Violations ORDER BY Audit_ID, Record_Key;
DROP TABLE #OrderTotals;

IF EXISTS (SELECT 1 FROM @Violations)
    THROW 51112, N'H4 phát hiện dữ liệu vi phạm. Xem bảng chi tiết phía trên.', 1;
GO
