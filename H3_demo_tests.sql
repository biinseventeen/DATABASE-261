/* H3 - Thực hiện 26 ca kiểm thử cho hai trigger đánh giá.
   Kiểm tra thao tác đúng/sai, mã lỗi và dữ liệu trước/sau;
   xuất kết quả PASS/FAIL và hoàn tác dữ liệu sau mỗi ca. */
USE ShopeeDB;
GO
SET NOCOUNT ON;
IF @@TRANCOUNT <> 0
    THROW 51110, N'Hãy chạy kiểm thử trong cửa sổ không có giao dịch đang mở.', 1;
SET IMPLICIT_TRANSACTIONS OFF;
SET XACT_ABORT OFF;

DECLARE @Cases TABLE (
    Case_ID varchar(6) PRIMARY KEY,
    Description nvarchar(200) NOT NULL,
    Action_SQL nvarchar(max) NOT NULL,
    Condition_SQL nvarchar(max) NOT NULL,
    Expected_Error int NULL
);

INSERT @Cases (Case_ID, Description, Action_SQL, Condition_SQL, Expected_Error)
VALUES
('QT-01', N'Hợp lệ: người mua 7 có đơn 4 (Delivery Successful) chứa sản phẩm 8',
 N'INSERT INTO dbo.Review (Product_ID, Rating_Score, Comment, Review_Date, Buyer_ID) VALUES (8, 3, ''T-QT01'', ''2026-11-12T09:00:00'', 7);',
 N'(SELECT COUNT(*) FROM dbo.Review WHERE Comment = ''T-QT01'') = 1 AND (SELECT Average_Rating FROM dbo.Product WHERE Product_ID = 8) = 3.00',
 NULL),

('QT-02', N'Đơn đang Shipping (người mua 3, sản phẩm 10)',
 N'INSERT INTO dbo.Review (Product_ID, Rating_Score, Comment, Review_Date, Buyer_ID) VALUES (10, 4, ''T-QT02'', ''2026-11-12T09:00:00'', 3);',
 N'(SELECT COUNT(*) FROM dbo.Review WHERE Comment = ''T-QT02'') = 0 AND (SELECT Average_Rating FROM dbo.Product WHERE Product_ID = 10) IS NULL',
 51101),

('QT-03', N'Đơn mới Confirmed, chưa giao (người mua 7, sản phẩm 1)',
 N'INSERT INTO dbo.Review (Product_ID, Rating_Score, Comment, Review_Date, Buyer_ID) VALUES (1, 4, ''T-QT03'', ''2026-11-12T09:00:00'', 7);',
 N'(SELECT COUNT(*) FROM dbo.Review WHERE Comment = ''T-QT03'') = 0 AND (SELECT Average_Rating FROM dbo.Product WHERE Product_ID = 1) = 5.00',
 51101),

('QT-04', N'Đơn Pending Confirmation (người mua 7, sản phẩm 5)',
 N'INSERT INTO dbo.Review (Product_ID, Rating_Score, Comment, Review_Date, Buyer_ID) VALUES (5, 4, ''T-QT04'', ''2026-11-12T09:00:00'', 7);',
 N'(SELECT COUNT(*) FROM dbo.Review WHERE Comment = ''T-QT04'') = 0 AND (SELECT Average_Rating FROM dbo.Product WHERE Product_ID = 5) IS NULL',
 51101),

('QT-05', N'Đơn đã hủy (người mua 4, sản phẩm 4)',
 N'INSERT INTO dbo.Review (Product_ID, Rating_Score, Comment, Review_Date, Buyer_ID) VALUES (4, 1, ''T-QT05'', ''2026-11-12T09:00:00'', 4);',
 N'(SELECT COUNT(*) FROM dbo.Review WHERE Comment = ''T-QT05'') = 0 AND (SELECT Average_Rating FROM dbo.Product WHERE Product_ID = 4) = 3.00',
 51101),

('QT-06', N'Đã mua sản phẩm khác, chưa mua sản phẩm này (người mua 6, sản phẩm 4)',
 N'INSERT INTO dbo.Review (Product_ID, Rating_Score, Comment, Review_Date, Buyer_ID) VALUES (4, 5, ''T-QT06'', ''2026-11-12T09:00:00'', 6);',
 N'(SELECT COUNT(*) FROM dbo.Review WHERE Comment = ''T-QT06'') = 0 AND (SELECT Average_Rating FROM dbo.Product WHERE Product_ID = 4) = 3.00',
 51101),

('QT-07', N'Người mua chưa có đơn nào (người mua 8, sản phẩm 1)',
 N'INSERT INTO dbo.Review (Product_ID, Rating_Score, Comment, Review_Date, Buyer_ID) VALUES (1, 5, ''T-QT07'', ''2026-11-12T09:00:00'', 8);',
 N'(SELECT COUNT(*) FROM dbo.Review WHERE Comment = ''T-QT07'') = 0 AND (SELECT Average_Rating FROM dbo.Product WHERE Product_ID = 1) = 5.00',
 51101),

('QT-08', N'Ngày đánh giá 05/11 sớm hơn ngày giao 07/11 (người mua 7, sản phẩm 9)',
 N'INSERT INTO dbo.Review (Product_ID, Rating_Score, Comment, Review_Date, Buyer_ID) VALUES (9, 3, ''T-QT08'', ''2026-11-05T09:00:00'', 7);',
 N'(SELECT COUNT(*) FROM dbo.Review WHERE Comment = ''T-QT08'') = 0 AND (SELECT Average_Rating FROM dbo.Product WHERE Product_ID = 9) = 2.00',
 51102),

('QT-09', N'Biên: đánh giá 07/11 08:00, giao 07/11 14:00 -> cùng NGÀY nên hợp lệ',
 N'INSERT INTO dbo.Review (Product_ID, Rating_Score, Comment, Review_Date, Buyer_ID) VALUES (9, 3, ''T-QT09'', ''2026-11-07T08:00:00'', 7);',
 N'(SELECT COUNT(*) FROM dbo.Review WHERE Comment = ''T-QT09'') = 1 AND (SELECT Average_Rating FROM dbo.Product WHERE Product_ID = 9) = 2.50',
 NULL),

('QT-10', N'UPDATE đổi người viết đánh giá 1 sang người mua 3 (chưa mua sản phẩm 2)',
 N'UPDATE dbo.Review SET Buyer_ID = 3 WHERE Review_ID = 1;',
 N'(SELECT COUNT(*) FROM dbo.Review WHERE Review_ID = 1 AND Buyer_ID = 6) = 1',
 51101),

('QT-11', N'UPDATE chuyển đánh giá 1 từ sản phẩm 2 sang sản phẩm 4 (người mua 6 chưa mua)',
 N'UPDATE dbo.Review SET Product_ID = 4 WHERE Review_ID = 1;',
 N'(SELECT COUNT(*) FROM dbo.Review WHERE Review_ID = 1 AND Product_ID = 2) = 1 AND (SELECT Average_Rating FROM dbo.Product WHERE Product_ID = 1) = 5.00 AND (SELECT Average_Rating FROM dbo.Product WHERE Product_ID = 2) = 4.00',
 51101),

('QT-12', N'UPDATE dời ngày đánh giá 1 về 01/10 (trước ngày giao 09/10)',
 N'UPDATE dbo.Review SET Review_Date = ''2026-10-01T10:00:00'' WHERE Review_ID = 1;',
 N'(SELECT COUNT(*) FROM dbo.Review WHERE Review_ID = 1 AND Review_Date = ''2026-10-11T20:10:00'') = 1',
 51102),

('QT-13', N'UPDATE chỉ sửa nhận xét của đánh giá 1: được phép, điểm giữ nguyên',
 N'UPDATE dbo.Review SET Comment = ''Da sua nhan xet'' WHERE Review_ID = 1;',
 N'(SELECT COUNT(*) FROM dbo.Review WHERE Review_ID = 1 AND Comment = ''Da sua nhan xet'' AND Rating_Score = 5) = 1 AND (SELECT Average_Rating FROM dbo.Product WHERE Product_ID = 1) = 5.00 AND (SELECT Average_Rating FROM dbo.Product WHERE Product_ID = 2) = 4.00',
 NULL),

('QT-14', N'Một lệnh nhiều dòng, có 1 dòng sai: cả lệnh bị hoàn tác',
 N'INSERT INTO dbo.Review (Product_ID, Rating_Score, Comment, Review_Date, Buyer_ID) VALUES (8, 3, ''T-QT14a'', ''2026-11-12T09:00:00'', 7), (10, 4, ''T-QT14b'', ''2026-11-12T09:00:00'', 3);',
 N'(SELECT COUNT(*) FROM dbo.Review WHERE Comment LIKE ''T-QT14%'') = 0 AND (SELECT Average_Rating FROM dbo.Product WHERE Product_ID = 8) IS NULL AND (SELECT Average_Rating FROM dbo.Product WHERE Product_ID = 10) IS NULL',
 51101),

('DT-01', N'Điểm trung bình của dữ liệu mẫu (P3, P5, P8, P10 chưa có đánh giá -> NULL)',
 N'SET NOCOUNT ON;',
 N'(SELECT Average_Rating FROM dbo.Product WHERE Product_ID = 1) = 5.00 AND (SELECT Average_Rating FROM dbo.Product WHERE Product_ID = 2) = 4.00 AND (SELECT Average_Rating FROM dbo.Product WHERE Product_ID = 3) IS NULL AND (SELECT Average_Rating FROM dbo.Product WHERE Product_ID = 4) = 3.00 AND (SELECT Average_Rating FROM dbo.Product WHERE Product_ID = 5) IS NULL AND (SELECT Average_Rating FROM dbo.Product WHERE Product_ID = 6) = 4.50 AND (SELECT Average_Rating FROM dbo.Product WHERE Product_ID = 7) = 4.50 AND (SELECT Average_Rating FROM dbo.Product WHERE Product_ID = 8) IS NULL AND (SELECT Average_Rating FROM dbo.Product WHERE Product_ID = 9) = 2.00 AND (SELECT Average_Rating FROM dbo.Product WHERE Product_ID = 10) IS NULL AND (SELECT Average_Rating FROM dbo.Product WHERE Product_ID = 11) IS NULL',
 NULL),

('DT-02', N'Thêm đánh giá hợp lệ: P7 từ (4+5) thành (4+5+2)/3 = 3.67',
 N'INSERT INTO dbo.Review (Product_ID, Rating_Score, Comment, Review_Date, Buyer_ID) VALUES (7, 2, ''T-DT02'', ''2026-11-12T09:00:00'', 6);',
 N'(SELECT Average_Rating FROM dbo.Product WHERE Product_ID = 7) = 3.67 AND (SELECT Average_Rating FROM dbo.Product WHERE Product_ID = 1) = 5.00 AND (SELECT Average_Rating FROM dbo.Product WHERE Product_ID = 2) = 4.00',
 NULL),

('DT-03', N'Sửa điểm 2 -> 5: P7 = (4+5+5)/3 = 4.67',
 N'INSERT INTO dbo.Review (Product_ID, Rating_Score, Comment, Review_Date, Buyer_ID) VALUES (7, 2, ''T-DT03'', ''2026-11-12T09:00:00'', 6);
   UPDATE dbo.Review SET Rating_Score = 5 WHERE Comment = ''T-DT03'';',
 N'(SELECT Average_Rating FROM dbo.Product WHERE Product_ID = 7) = 4.67',
 NULL),

('DT-04', N'Xóa đánh giá vừa thêm: P7 trở về 4.50',
 N'INSERT INTO dbo.Review (Product_ID, Rating_Score, Comment, Review_Date, Buyer_ID) VALUES (7, 2, ''T-DT04'', ''2026-11-12T09:00:00'', 6);
   DELETE FROM dbo.Review WHERE Comment = ''T-DT04'';',
 N'(SELECT Average_Rating FROM dbo.Product WHERE Product_ID = 7) = 4.50 AND (SELECT COUNT(*) FROM dbo.Review WHERE Product_ID = 7) = 2',
 NULL),

('DT-05', N'Xóa đánh giá cuối cùng của P9: điểm thành NULL',
 N'DELETE FROM dbo.Review WHERE Review_ID = 6;',
 N'(SELECT COUNT(*) FROM dbo.Review WHERE Product_ID = 9) = 0 AND (SELECT Average_Rating FROM dbo.Product WHERE Product_ID = 9) IS NULL AND (SELECT Average_Rating FROM dbo.Product WHERE Product_ID = 1) = 5.00 AND (SELECT Average_Rating FROM dbo.Product WHERE Product_ID = 2) = 4.00',
 NULL),

('DT-06', N'Chuyển đánh giá P7 sang P2 (người mua 6 đã mua cả hai): tính lại 2 sản phẩm',
 N'INSERT INTO dbo.Review (Product_ID, Rating_Score, Comment, Review_Date, Buyer_ID) VALUES (7, 2, ''T-DT06'', ''2026-11-12T09:00:00'', 6);
   UPDATE dbo.Review SET Product_ID = 2 WHERE Comment = ''T-DT06'';',
 N'(SELECT Average_Rating FROM dbo.Product WHERE Product_ID = 7) = 4.50 AND (SELECT Average_Rating FROM dbo.Product WHERE Product_ID = 2) = 3.33',
 NULL),

('DT-07', N'Đánh giá bị chặn không làm đổi điểm hay số đánh giá (người mua 8, sản phẩm 1)',
 N'INSERT INTO dbo.Review (Product_ID, Rating_Score, Comment, Review_Date, Buyer_ID) VALUES (1, 1, ''T-DT07'', ''2026-11-12T09:00:00'', 8);',
 N'(SELECT Average_Rating FROM dbo.Product WHERE Product_ID = 1) = 5.00 AND (SELECT COUNT(*) FROM dbo.Review WHERE Product_ID = 1) = 1',
 51101),

('DT-08', N'Một lệnh thêm 2 đánh giá hợp lệ cho 2 sản phẩm: P7 = 3.67, P1 = 4.00',
 N'INSERT INTO dbo.Review (Product_ID, Rating_Score, Comment, Review_Date, Buyer_ID) VALUES (7, 2, ''T-DT08a'', ''2026-11-12T09:00:00'', 6), (1, 3, ''T-DT08b'', ''2026-11-12T09:00:00'', 6);',
 N'(SELECT Average_Rating FROM dbo.Product WHERE Product_ID = 7) = 3.67 AND (SELECT Average_Rating FROM dbo.Product WHERE Product_ID = 1) = 4.00',
 NULL),

('DT-09', N'Sửa điểm đánh giá duy nhất của P1 từ 5 xuống 1: P1 = 1.00',
 N'UPDATE dbo.Review SET Rating_Score = 1 WHERE Review_ID = 3;',
 N'(SELECT Average_Rating FROM dbo.Product WHERE Product_ID = 1) = 1.00',
 NULL),

('QT-15', N'UPDATE đổi sang người mua khác ĐÃ nhận cùng sản phẩm: hợp lệ',
 N'UPDATE dbo.Review SET Buyer_ID = 1, Review_Date = ''2026-11-12T09:00:00'' WHERE Review_ID = 2;',
 N'(SELECT COUNT(*) FROM dbo.Review WHERE Review_ID = 2 AND Buyer_ID = 1) = 1 AND (SELECT Average_Rating FROM dbo.Product WHERE Product_ID = 7) = 4.50',
 NULL),

('DT-10', N'Một UPDATE sửa điểm của hai sản phẩm: P1 = 1.00, P2 = 2.00',
 N'UPDATE dbo.Review SET Rating_Score = 1 WHERE Review_ID IN (1, 3);',
 N'(SELECT Average_Rating FROM dbo.Product WHERE Product_ID = 1) = 1.00 AND (SELECT Average_Rating FROM dbo.Product WHERE Product_ID = 2) = 2.00',
 NULL),

('DT-11', N'Một DELETE xóa ở hai sản phẩm: P7 còn 5.00, P9 hết đánh giá -> NULL',
 N'DELETE FROM dbo.Review WHERE Review_ID IN (2, 6);',
 N'(SELECT Average_Rating FROM dbo.Product WHERE Product_ID = 7) = 5.00 AND (SELECT Average_Rating FROM dbo.Product WHERE Product_ID = 9) IS NULL',
 NULL);

DECLARE @Results TABLE (
    Case_ID varchar(6) PRIMARY KEY, Description nvarchar(200) NOT NULL, Passed bit NOT NULL,
    Actual_Error int NULL, Detail nvarchar(4000) NULL, Ratings_Before nvarchar(300) NULL, Product_Ratings nvarchar(300) NULL);

DECLARE @CaseID varchar(6), @Description nvarchar(200), @Action nvarchar(max), @Cond nvarchar(max),
        @ExpectedError int, @ActualError int, @Passed bit, @Detail nvarchar(4000),
        @Observed nvarchar(300), @Before nvarchar(300), @CondSql nvarchar(max), @Ok int;

SELECT @CaseID = MIN(Case_ID) FROM @Cases;

WHILE @CaseID IS NOT NULL
BEGIN
    SELECT @Description = Description, @Action = Action_SQL, @Cond = Condition_SQL, @ExpectedError = Expected_Error
    FROM @Cases WHERE Case_ID = @CaseID;

    SET @ActualError = NULL; SET @Detail = NULL; SET @Passed = 0; SET @Ok = 0;

    SELECT @Before = CONCAT(
        'P1=', COALESCE(CONVERT(varchar(10), MAX(CASE WHEN Product_ID = 1 THEN Average_Rating END)), 'NULL'),
        ', P2=', COALESCE(CONVERT(varchar(10), MAX(CASE WHEN Product_ID = 2 THEN Average_Rating END)), 'NULL'),
        ', P3=', COALESCE(CONVERT(varchar(10), MAX(CASE WHEN Product_ID = 3 THEN Average_Rating END)), 'NULL'),
        ', P4=', COALESCE(CONVERT(varchar(10), MAX(CASE WHEN Product_ID = 4 THEN Average_Rating END)), 'NULL'),
        ', P5=', COALESCE(CONVERT(varchar(10), MAX(CASE WHEN Product_ID = 5 THEN Average_Rating END)), 'NULL'),
        ', P6=', COALESCE(CONVERT(varchar(10), MAX(CASE WHEN Product_ID = 6 THEN Average_Rating END)), 'NULL'),
        ', P7=', COALESCE(CONVERT(varchar(10), MAX(CASE WHEN Product_ID = 7 THEN Average_Rating END)), 'NULL'),
        ', P8=', COALESCE(CONVERT(varchar(10), MAX(CASE WHEN Product_ID = 8 THEN Average_Rating END)), 'NULL'),
        ', P9=', COALESCE(CONVERT(varchar(10), MAX(CASE WHEN Product_ID = 9 THEN Average_Rating END)), 'NULL'),
        ', P10=', COALESCE(CONVERT(varchar(10), MAX(CASE WHEN Product_ID = 10 THEN Average_Rating END)), 'NULL'),
        ', P11=', COALESCE(CONVERT(varchar(10), MAX(CASE WHEN Product_ID = 11 THEN Average_Rating END)), 'NULL'))
    FROM dbo.Product WHERE Product_ID BETWEEN 1 AND 11;

    BEGIN TRANSACTION;
    BEGIN TRY
        EXEC sys.sp_executesql @Action;
    END TRY
    BEGIN CATCH
        SELECT @ActualError = ERROR_NUMBER(), @Detail = ERROR_MESSAGE();
    END CATCH;

    -- Điều kiện kiểm tra chạy TRƯỚC khi hoàn tác, để thấy cả tác dụng phụ còn sót lại.
    SET @CondSql = N'SELECT @ok_out = CASE WHEN (' + @Cond + N') AND
        NOT EXISTS (
            SELECT 1 FROM dbo.Product AS p
            WHERE COALESCE(p.Average_Rating, -1) <> COALESCE((
                SELECT CAST(AVG(CAST(r.Rating_Score AS DECIMAL(10,4))) AS DECIMAL(3,2))
                FROM dbo.Review AS r WHERE r.Product_ID = p.Product_ID
            ), -1)
        ) THEN 1 ELSE 0 END';
    BEGIN TRY
        EXEC sys.sp_executesql @CondSql, N'@ok_out int OUTPUT', @ok_out = @Ok OUTPUT;
    END TRY
    BEGIN CATCH
        SET @Ok = 0;
        SET @Detail = CONCAT(@Detail, N' Lỗi khi kiểm tra kết quả: ', ERROR_MESSAGE());
    END CATCH;

    IF (@ExpectedError IS NULL AND @ActualError IS NULL) OR (@ExpectedError = @ActualError)
    BEGIN
        SET @Passed = CASE WHEN @Ok = 1 THEN 1 ELSE 0 END
        IF @Ok = 0 SET @Detail = CONCAT(@Detail, N' Điều kiện kiểm tra dữ liệu sau thao tác không thỏa.')
    END
    ELSE IF @ExpectedError IS NOT NULL AND @ActualError IS NULL
    BEGIN
        SET @Detail = CONCAT(N'Thao tác thành công nhưng cần lỗi ', @ExpectedError, N'.')
    END
    ELSE
    BEGIN
        SET @Detail = CONCAT(N'Lỗi không như mong đợi (', @ActualError, N'): ', @Detail)
    END

    SELECT @Observed = CONCAT(
        'P1=', COALESCE(CONVERT(varchar(10), MAX(CASE WHEN Product_ID = 1 THEN Average_Rating END)), 'NULL'),
        ', P2=', COALESCE(CONVERT(varchar(10), MAX(CASE WHEN Product_ID = 2 THEN Average_Rating END)), 'NULL'),
        ', P3=', COALESCE(CONVERT(varchar(10), MAX(CASE WHEN Product_ID = 3 THEN Average_Rating END)), 'NULL'),
        ', P4=', COALESCE(CONVERT(varchar(10), MAX(CASE WHEN Product_ID = 4 THEN Average_Rating END)), 'NULL'),
        ', P5=', COALESCE(CONVERT(varchar(10), MAX(CASE WHEN Product_ID = 5 THEN Average_Rating END)), 'NULL'),
        ', P6=', COALESCE(CONVERT(varchar(10), MAX(CASE WHEN Product_ID = 6 THEN Average_Rating END)), 'NULL'),
        ', P7=', COALESCE(CONVERT(varchar(10), MAX(CASE WHEN Product_ID = 7 THEN Average_Rating END)), 'NULL'),
        ', P8=', COALESCE(CONVERT(varchar(10), MAX(CASE WHEN Product_ID = 8 THEN Average_Rating END)), 'NULL'),
        ', P9=', COALESCE(CONVERT(varchar(10), MAX(CASE WHEN Product_ID = 9 THEN Average_Rating END)), 'NULL'),
        ', P10=', COALESCE(CONVERT(varchar(10), MAX(CASE WHEN Product_ID = 10 THEN Average_Rating END)), 'NULL'),
        ', P11=', COALESCE(CONVERT(varchar(10), MAX(CASE WHEN Product_ID = 11 THEN Average_Rating END)), 'NULL'))
    FROM dbo.Product WHERE Product_ID BETWEEN 1 AND 11;

    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;

    INSERT @Results (Case_ID, Description, Passed, Actual_Error, Detail, Ratings_Before, Product_Ratings)
    VALUES (@CaseID, @Description, @Passed, @ActualError, @Detail, @Before, @Observed);

    SELECT @CaseID = MIN(Case_ID) FROM @Cases WHERE Case_ID > @CaseID;
END;

SELECT r.Case_ID, r.Description, CASE WHEN r.Passed = 1 THEN 'PASS' ELSE 'FAIL' END AS Result,
       c.Expected_Error, r.Actual_Error, r.Ratings_Before, r.Product_Ratings, r.Detail
FROM @Results AS r JOIN @Cases AS c ON c.Case_ID = r.Case_ID
ORDER BY r.Case_ID;

SELECT COUNT(*) AS Total_Cases, SUM(CONVERT(int, Passed)) AS Passed_Cases FROM @Results;

IF EXISTS (SELECT 1 FROM @Results WHERE Passed = 0)
    THROW 51111, N'Có ca kiểm thử thất bại. Xem bảng kết quả để tìm ca lỗi.', 1;
GO
