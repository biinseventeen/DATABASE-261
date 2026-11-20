/* H1 - Tạo hai trigger kiểm tra và xử lý đánh giá sản phẩm.
   Kiểm tra quyền/ngày đánh giá và cập nhật điểm trung bình khi Review thay đổi. */
USE ShopeeDB;
GO
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

/* 2.2.1 - Kiểm tra trên MỌI dòng mới trong inserted, kể cả UPDATE.
   Phải có đơn đã giao của đúng người mua, chứa biến thể của đúng sản phẩm.
   Ngày đánh giá >= ngày giao của ÍT NHẤT MỘT đơn như vậy (so theo NGÀY).
   INSERT/UPDATE Review được kiểm tra; DELETE không thể tạo đánh giá sai.

   Phạm vi: kiểm tra tại thời điểm ghi Review. Nhóm phải bảo vệ dữ liệu
   nguồn Orders/Order_Detail/Product_Variant để về sau không làm mất căn
   cứ của đánh giá cũ. H4 phát hiện dữ liệu hiện có bị sai; H4 không ngăn DML.
   Mã lỗi: 51101 chưa mua/nhận đúng sản phẩm; 51102 ngày đánh giá quá sớm. */
CREATE OR ALTER TRIGGER dbo.trg_Review_Eligibility_Timing
ON dbo.Review
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM inserted)
        RETURN;

    IF EXISTS (
        SELECT 1
        FROM inserted AS i
        WHERE NOT EXISTS (
            SELECT 1
            FROM dbo.Orders AS o
            JOIN dbo.Order_Detail AS od ON od.Order_ID = o.Order_ID
            JOIN dbo.Product_Variant AS pv ON pv.Variant_ID = od.Variant_ID
            WHERE o.Buyer_ID = i.Buyer_ID
              AND o.Status = 'Delivery Successful'
              AND pv.Product_ID = i.Product_ID
        )
    )
    BEGIN
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW 51101, N'Chỉ được đánh giá sản phẩm có trong đơn đã giao thành công của chính người mua.', 1;
    END;

    IF EXISTS (
        SELECT 1
        FROM inserted AS i
        WHERE NOT EXISTS (
            SELECT 1
            FROM dbo.Orders AS o
            JOIN dbo.Order_Detail AS od ON od.Order_ID = o.Order_ID
            JOIN dbo.Product_Variant AS pv ON pv.Variant_ID = od.Variant_ID
            WHERE o.Buyer_ID = i.Buyer_ID
              AND o.Status = 'Delivery Successful'
              AND pv.Product_ID = i.Product_ID
              AND CAST(i.Review_Date AS DATE) >= CAST(o.Delivered_At AS DATE)
        )
    )
    BEGIN
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW 51102, N'Ngày đánh giá phải từ ngày giao thành công của ít nhất một đơn hợp lệ trở đi.', 1;
    END;
END;
GO

/* 2.2.2 - Product.Average_Rating = trung bình Rating_Score, hai chữ số lẻ;
   chưa có đánh giá thì NULL. Tính trực tiếp từ Review, không có thuộc tính
   dẫn xuất trung gian. Không cho ứng dụng tự ghi đè cột cache này.

   INSERT: sản phẩm mới; DELETE: sản phẩm cũ;
   UPDATE Rating_Score: sản phẩm được sửa;
   UPDATE Product_ID: CẢ sản phẩm cũ và mới;
   UPDATE Comment/Buyer_ID/Review_Date: không đổi điểm, bỏ qua tính lại.
   inserted/deleted là TẬP dòng, không giả định mỗi lệnh chỉ có một dòng. */
CREATE OR ALTER TRIGGER dbo.trg_Review_AverageRating
ON dbo.Review
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;

    IF EXISTS (SELECT 1 FROM inserted) AND EXISTS (SELECT 1 FROM deleted)
       AND NOT (UPDATE(Rating_Score) OR UPDATE(Product_ID))
        RETURN;

    DECLARE @Affected TABLE (Product_ID INT NOT NULL PRIMARY KEY);

    INSERT @Affected (Product_ID)
    SELECT Product_ID FROM inserted
    UNION
    SELECT Product_ID FROM deleted;

    IF NOT EXISTS (SELECT 1 FROM @Affected)
        RETURN;

    -- Lấy khóa trên các Product liên quan trước khi tính/ghi cache.
    -- READCOMMITTEDLOCK phía dưới đọc Review bằng khóa thay vì bản snapshot.
    -- Vẫn có thể gặp deadlock khi ghi đồng thời: ứng dụng cần retry giao dịch.
    DECLARE @Locked INT;
    SELECT @Locked = COUNT(*)
    FROM dbo.Product AS p WITH (UPDLOCK)
    JOIN @Affected AS a ON a.Product_ID = p.Product_ID;

    UPDATE p
    SET Average_Rating = (
        SELECT CAST(AVG(CAST(r.Rating_Score AS DECIMAL(10,4))) AS DECIMAL(3,2))
        FROM dbo.Review AS r WITH (READCOMMITTEDLOCK)
        WHERE r.Product_ID = p.Product_ID
    )
    FROM dbo.Product AS p
    JOIN @Affected AS a ON a.Product_ID = p.Product_ID;
END;
GO

-- Ưu tiên kiểm tra quyền trước khi tính điểm. Nếu nhóm đã có trigger First,
-- vẫn đúng nhờ giao dịch: đánh giá bị từ chối sẽ hoàn tác cả thay đổi điểm.
BEGIN TRY
    EXEC sys.sp_settriggerorder
        @triggername = N'dbo.trg_Review_Eligibility_Timing',
        @order = N'First', @stmttype = N'INSERT';
    EXEC sys.sp_settriggerorder
        @triggername = N'dbo.trg_Review_Eligibility_Timing',
        @order = N'First', @stmttype = N'UPDATE';
END TRY
BEGIN CATCH
    PRINT CONCAT(N'Không đặt được thứ tự trigger: ', ERROR_MESSAGE());
END CATCH;
GO

-- Backfill: đồng bộ điểm cho Review có trước lúc cài trigger.
-- Đây là UPDATE một lần khi chạy H1, KHÔNG phải trigger thứ ba.
UPDATE p
SET Average_Rating = (
    SELECT CAST(AVG(CAST(r.Rating_Score AS DECIMAL(10,4))) AS DECIMAL(3,2))
    FROM dbo.Review AS r WHERE r.Product_ID = p.Product_ID
)
FROM dbo.Product AS p;
GO
