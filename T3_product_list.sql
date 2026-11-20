/*
    BTL2 - Phan Thinh - Muc 2.3, truy van 1
    Danh sach san pham theo ten / danh muc / nguoi ban.

    Hop voi schema V2-shopee_schema.sql. Moi dong ket qua la mot san pham;
    gia va ton kho duoc tong hop tu cac bien the. Thu tuc chi doc du lieu.
    Frontend goi qua GET /api/products va backend thuc thi thu tuc nay.
*/
USE ShopeeDB;
GO

CREATE OR ALTER PROCEDURE dbo.usp_Product_List
    @SearchTerm NVARCHAR(200) = NULL,
    @Category_ID INT = NULL,
    @Seller_ID INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    -- Tra ve thong tin de hien thi danh sach san pham. LEFT JOIN giu lai
    -- san pham chua co bien the (neu co), INNER JOIN Seller/Category dam bao
    -- cac ten tham chieu ton tai theo FK.
    SELECT
        p.Product_ID,
        p.Name AS Product_Name,
        p.Description,
        p.Average_Rating,
        p.Category_ID,
        c.Category_Name,
        p.Seller_ID,
        u.Username AS Seller_Username,
        s.Shop_Name,
        (SELECT STRING_AGG(CONVERT(NVARCHAR(MAX), pi.Image_URL), N'|')
         FROM dbo.Product_Image AS pi
         WHERE pi.Product_ID = p.Product_ID) AS Image_Urls,
        COUNT(pv.Variant_ID) AS Variant_Count,
        SUM(CASE WHEN pv.Variant_ID IS NOT NULL AND pv.Stock_Quantity <= 10 THEN 1 ELSE 0 END) AS Low_Stock_Variant_Count,
        MIN(pv.Current_Price) AS Min_Price,
        MAX(pv.Current_Price) AS Max_Price,
        COALESCE(SUM(pv.Stock_Quantity), 0) AS Total_Stock
    FROM dbo.Product AS p
    INNER JOIN dbo.Category AS c ON c.Category_ID = p.Category_ID
    INNER JOIN dbo.Seller AS s ON s.User_ID = p.Seller_ID
    INNER JOIN dbo.Users AS u ON u.User_ID = s.User_ID
    LEFT JOIN dbo.Product_Variant AS pv ON pv.Product_ID = p.Product_ID
    WHERE
        (@SearchTerm IS NULL OR LTRIM(RTRIM(@SearchTerm)) = N''
            OR p.Name LIKE N'%' + LTRIM(RTRIM(@SearchTerm)) + N'%'
            OR s.Shop_Name LIKE N'%' + LTRIM(RTRIM(@SearchTerm)) + N'%')
        AND (@Category_ID IS NULL OR p.Category_ID = @Category_ID)
        AND (@Seller_ID IS NULL OR p.Seller_ID = @Seller_ID)
    GROUP BY
        p.Product_ID, p.Name, p.Description, p.Average_Rating,
        p.Category_ID, c.Category_Name, p.Seller_ID, u.Username, s.Shop_Name
    ORDER BY p.Name ASC, p.Product_ID ASC;
END;
GO

/* Demo calls (seed data from H2_seed.sql):
EXEC dbo.usp_Product_List @SearchTerm = N'tai nghe';
EXEC dbo.usp_Product_List @Category_ID = 2;
EXEC dbo.usp_Product_List @SearchTerm = N'Galaxy', @Seller_ID = 1;
*/
