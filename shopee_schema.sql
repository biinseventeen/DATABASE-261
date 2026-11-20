/* =====================================================================
   ShopeeDB - Phase 2: DDL, constraints, views, triggers
   Target : SQL Server 2022 / 2025 (Linux container), database ShopeeDB
   Style  : IDEMPOTENT. Re-running drops everything it owns (reverse FK
            order) and rebuilds it. Do NOT run against data you want to keep.
   Run    : sqlcmd -S localhost -U sa -C -I -b -i shopee_schema.sql
            (-I = QUOTED_IDENTIFIER ON, required for the filtered index;
             -b = abort with a non-zero exit code on the first error)
   Naming : Users and Orders (not USER / ORDER) because those are reserved
            words in T-SQL. Every other table keeps its diagram name.
   Money  : VND, DECIMAL(15,0).  Timestamps: DATETIME2(0).
   ===================================================================== */
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

IF DB_ID(N'ShopeeDB') IS NULL
    CREATE DATABASE ShopeeDB COLLATE Vietnamese_CI_AS;
GO
USE ShopeeDB;
GO
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

/* ---------------------------------------------------------------------
   0. TEARDOWN  (views first, then tables in REVERSE dependency order)
   --------------------------------------------------------------------- */
DROP VIEW  IF EXISTS dbo.vw_Seller_Rating;
DROP VIEW  IF EXISTS dbo.vw_Product_Rating;
DROP VIEW  IF EXISTS dbo.vw_Order_Total;

DROP TABLE IF EXISTS dbo.Review;
DROP TABLE IF EXISTS dbo.Return_Request;
DROP TABLE IF EXISTS dbo.Payment;
DROP TABLE IF EXISTS dbo.Order_Detail;
DROP TABLE IF EXISTS dbo.Orders;
DROP TABLE IF EXISTS dbo.Shipping_Company;
DROP TABLE IF EXISTS dbo.Product_Image;
DROP TABLE IF EXISTS dbo.Product_Variant;
DROP TABLE IF EXISTS dbo.Product;
DROP TABLE IF EXISTS dbo.Category;
DROP TABLE IF EXISTS dbo.Buyer_Voucher;
DROP TABLE IF EXISTS dbo.Voucher;
DROP TABLE IF EXISTS dbo.Seller;
DROP TABLE IF EXISTS dbo.Buyer;
DROP TABLE IF EXISTS dbo.Address;
DROP TABLE IF EXISTS dbo.User_Phone;
DROP TABLE IF EXISTS dbo.Users;
GO

/* ---------------------------------------------------------------------
   1. TABLES  (parents before children)
   --------------------------------------------------------------------- */

-- 1.1 Users -----------------------------------------------------------
-- Age is DERIVED (non-persisted computed column): GETDATE() is
-- non-deterministic, so it can never be PERSISTED or indexed - and a
-- stored age would go stale every birthday anyway.
-- Password is stored in PLAINTEXT so the CHECK can enforce the policy.
-- COURSEWORK ONLY: production systems store a salted hash (e.g. bcrypt/
-- Argon2) and validate the policy in the application layer.
CREATE TABLE dbo.Users (
    User_ID       INT IDENTITY(1,1) NOT NULL,
    Username      NVARCHAR(50)  NOT NULL,
    Fullname      NVARCHAR(100) NOT NULL,
    [Password]    VARCHAR(50)   NOT NULL,
    Email         NVARCHAR(254) NOT NULL,
    Gender        VARCHAR(10)   NULL,
    Date_of_Birth DATE          NOT NULL,
    Age AS ( DATEDIFF(YEAR, Date_of_Birth, GETDATE())
             - CASE WHEN DATEADD(YEAR, DATEDIFF(YEAR, Date_of_Birth, GETDATE()), Date_of_Birth)
                         > CAST(GETDATE() AS DATE) THEN 1 ELSE 0 END ),
    CONSTRAINT PK_Users          PRIMARY KEY (User_ID),
    CONSTRAINT UQ_Users_Username UNIQUE (Username),
    CONSTRAINT UQ_Users_Email    UNIQUE (Email),
    CONSTRAINT CK_Users_Gender   CHECK (Gender IN ('Male', 'Female', 'Other')),
    CONSTRAINT CK_Users_Email    CHECK (Email LIKE '_%@_%._%'),
    CONSTRAINT CK_Users_DOB      CHECK (Date_of_Birth >= '1900-01-01'
                                        AND Date_of_Birth <= CAST(GETDATE() AS DATE)),
    -- 8-16 chars, >=1 uppercase, >=1 lowercase, >=1 digit.
    -- The database collation is case-INsensitive, so [A-Z] / [a-z] must be
    -- tested under a binary collation or both patterns match any letter.
    CONSTRAINT CK_Users_Password CHECK (
            LEN([Password]) BETWEEN 8 AND 16
        AND [Password] COLLATE Latin1_General_100_BIN2 LIKE '%[A-Z]%'
        AND [Password] COLLATE Latin1_General_100_BIN2 LIKE '%[a-z]%'
        AND [Password] LIKE '%[0-9]%')
);
GO

-- 1.2 User_Phone (multivalued attribute) --------------------------------
CREATE TABLE dbo.User_Phone (
    User_ID      INT         NOT NULL,
    Phone_Number VARCHAR(15) NOT NULL,
    CONSTRAINT PK_User_Phone        PRIMARY KEY (User_ID, Phone_Number),
    CONSTRAINT FK_User_Phone_Users  FOREIGN KEY (User_ID) REFERENCES dbo.Users (User_ID) ON DELETE CASCADE,
    CONSTRAINT CK_User_Phone_Format CHECK (Phone_Number NOT LIKE '%[^0-9+]%'
                                           AND LEN(Phone_Number) BETWEEN 9 AND 15)
);
GO

-- 1.3 Address (weak entity of Users; composite key from the diagram) ----
CREATE TABLE dbo.Address (
    User_ID      INT           NOT NULL,
    Street       NVARCHAR(150) NOT NULL,
    Ward         NVARCHAR(60)  NOT NULL,
    District     NVARCHAR(60)  NOT NULL,
    City         NVARCHAR(60)  NOT NULL,
    Address_Type VARCHAR(10)   NOT NULL CONSTRAINT DF_Address_Type DEFAULT 'Home',
    CONSTRAINT PK_Address       PRIMARY KEY (User_ID, Street, Ward, District, City),
    CONSTRAINT FK_Address_Users FOREIGN KEY (User_ID) REFERENCES dbo.Users (User_ID) ON DELETE CASCADE,
    CONSTRAINT CK_Address_Type  CHECK (Address_Type IN ('Home', 'Office'))
);
GO

-- 1.4 Buyer / Seller (overlapping specialization of Users) --------------
-- Buyer lost Loyalty_Points (removed from the design): it is now a pure
-- "role" table, but still the FK target for orders, reviews and returns.
CREATE TABLE dbo.Buyer (
    User_ID INT NOT NULL,
    CONSTRAINT PK_Buyer       PRIMARY KEY (User_ID),
    CONSTRAINT FK_Buyer_Users FOREIGN KEY (User_ID) REFERENCES dbo.Users (User_ID) ON DELETE CASCADE
);
GO

CREATE TABLE dbo.Seller (
    User_ID          INT           NOT NULL,
    Shop_Name        NVARCHAR(100) NOT NULL,
    Shop_Description NVARCHAR(500) NULL,
    Tax_ID           VARCHAR(14)   NULL,
    CONSTRAINT PK_Seller       PRIMARY KEY (User_ID),
    CONSTRAINT FK_Seller_Users FOREIGN KEY (User_ID) REFERENCES dbo.Users (User_ID) ON DELETE CASCADE,
    CONSTRAINT CK_Seller_Tax   CHECK (Tax_ID IS NULL OR Tax_ID NOT LIKE '%[^0-9-]%')
);
GO

-- 1.5 Voucher -----------------------------------------------------------
-- Discount_Percent replaces Discount_Value (it is a percentage, 10-50).
-- Max_Discount_Amount caps the money off a single order.
-- Quantity = total number of (non-cancelled) orders that may use the voucher.
CREATE TABLE dbo.Voucher (
    Voucher_Code        VARCHAR(20)   NOT NULL,
    Discount_Percent    TINYINT       NOT NULL,
    Min_Order_Value     DECIMAL(15,0) NOT NULL CONSTRAINT DF_Voucher_MinOrder DEFAULT 0,
    Max_Discount_Amount DECIMAL(15,0) NOT NULL,
    Quantity            INT           NOT NULL,
    Start_Date          DATE          NOT NULL,
    End_Date            DATE          NOT NULL,
    CONSTRAINT PK_Voucher             PRIMARY KEY (Voucher_Code),
    CONSTRAINT CK_Voucher_Percent     CHECK (Discount_Percent BETWEEN 10 AND 50),
    CONSTRAINT CK_Voucher_MinOrder    CHECK (Min_Order_Value BETWEEN 0 AND 1000000000),
    CONSTRAINT CK_Voucher_MaxDiscount CHECK (Max_Discount_Amount BETWEEN 1 AND 1000000000),
    CONSTRAINT CK_Voucher_Quantity    CHECK (Quantity >= 1),
    CONSTRAINT CK_Voucher_Dates       CHECK (End_Date >= Start_Date)
);
GO

-- 1.6 Buyer_Voucher (the RECEIVED relationship, M:N) --------------------
CREATE TABLE dbo.Buyer_Voucher (
    Buyer_ID     INT         NOT NULL,
    Voucher_Code VARCHAR(20) NOT NULL,
    CONSTRAINT PK_Buyer_Voucher         PRIMARY KEY (Buyer_ID, Voucher_Code),
    CONSTRAINT FK_Buyer_Voucher_Buyer   FOREIGN KEY (Buyer_ID)     REFERENCES dbo.Buyer (User_ID)       ON DELETE CASCADE,
    CONSTRAINT FK_Buyer_Voucher_Voucher FOREIGN KEY (Voucher_Code) REFERENCES dbo.Voucher (Voucher_Code) ON DELETE CASCADE
);
GO

-- 1.7 Category (recursive; NULL parent = root category) -----------------
-- The CHECK stops direct self-parenting; deeper cycles need a trigger.
CREATE TABLE dbo.Category (
    Category_ID        INT IDENTITY(1,1) NOT NULL,
    Category_Name      NVARCHAR(100)     NOT NULL,
    Parent_Category_ID INT               NULL,
    CONSTRAINT PK_Category        PRIMARY KEY (Category_ID),
    CONSTRAINT FK_Category_Parent FOREIGN KEY (Parent_Category_ID) REFERENCES dbo.Category (Category_ID),
    CONSTRAINT CK_Category_NoSelfParent CHECK (Parent_Category_ID IS NULL OR Parent_Category_ID <> Category_ID)
);
GO

-- 1.8 Product (the base listing; price and stock now live on the variant)
-- Average_Rating is DERIVED -> see dbo.vw_Product_Rating.
CREATE TABLE dbo.Product (
    Product_ID  INT IDENTITY(1,1) NOT NULL,
    Name        NVARCHAR(200)     NOT NULL,
    Description NVARCHAR(MAX)     NULL,
    Category_ID INT               NOT NULL,
    Seller_ID   INT               NOT NULL,
    CONSTRAINT PK_Product          PRIMARY KEY (Product_ID),
    CONSTRAINT FK_Product_Category FOREIGN KEY (Category_ID) REFERENCES dbo.Category (Category_ID),
    CONSTRAINT FK_Product_Seller   FOREIGN KEY (Seller_ID)   REFERENCES dbo.Seller (User_ID)
);
GO

-- 1.9 Product_Variant (a sellable version: its own price and stock) ------
-- Every product should have >= 1 variant ("Default" if it has no options).
-- That rule cannot be enforced at INSERT time (see audit queries).
CREATE TABLE dbo.Product_Variant (
    Variant_ID     INT IDENTITY(1,1) NOT NULL,
    Product_ID     INT               NOT NULL,
    Variant_Name   NVARCHAR(100)     NOT NULL,
    Current_Price  DECIMAL(15,0)     NOT NULL,
    Stock_Quantity INT               NOT NULL CONSTRAINT DF_Variant_Stock DEFAULT 0,
    CONSTRAINT PK_Product_Variant         PRIMARY KEY (Variant_ID),
    CONSTRAINT UQ_Product_Variant_Name    UNIQUE (Product_ID, Variant_Name),
    CONSTRAINT FK_Product_Variant_Product FOREIGN KEY (Product_ID) REFERENCES dbo.Product (Product_ID) ON DELETE CASCADE,
    CONSTRAINT CK_Variant_Price           CHECK (Current_Price BETWEEN 1 AND 1000000000),
    CONSTRAINT CK_Variant_Stock           CHECK (Stock_Quantity >= 0)
);
GO

-- 1.10 Product_Image (multivalued attribute) ------------------------------
CREATE TABLE dbo.Product_Image (
    Product_ID INT          NOT NULL,
    Image_URL  VARCHAR(400) NOT NULL,
    CONSTRAINT PK_Product_Image         PRIMARY KEY (Product_ID, Image_URL),
    CONSTRAINT FK_Product_Image_Product FOREIGN KEY (Product_ID) REFERENCES dbo.Product (Product_ID) ON DELETE CASCADE,
    CONSTRAINT CK_Product_Image_URL     CHECK (Image_URL LIKE 'http%')
);
GO

-- 1.11 Shipping_Company ---------------------------------------------------
CREATE TABLE dbo.Shipping_Company (
    Company_ID   INT IDENTITY(1,1) NOT NULL,
    Company_Name NVARCHAR(100)     NOT NULL,
    CONSTRAINT PK_Shipping_Company      PRIMARY KEY (Company_ID),
    CONSTRAINT UQ_Shipping_Company_Name UNIQUE (Company_Name)
);
GO

-- 1.12 Orders ---------------------------------------------------------------
-- * Total_Amount is DERIVED -> dbo.vw_Order_Total (no column here).
-- * Delivered_At = when Status became 'Delivery Successful' (Review Timing).
-- * FK_Orders_Address: (Buyer_ID, Street, Ward, District, City) must exist in
--   Address under the SAME user id -> the "User Address" rule, enforced by
--   structure alone (no trigger).
-- * FK_Orders_BuyerVoucher: (Buyer_ID, Voucher_Code) must exist in
--   Buyer_Voucher -> the "voucher must have been received" rule. When
--   Voucher_Code IS NULL, SQL Server skips a composite FK, which is exactly
--   what we want. This also guarantees the voucher exists, so a separate
--   FK to Voucher would be redundant.
-- * UQ (Order_ID, Buyer_ID) exists only so Return_Request can reference it.
CREATE TABLE dbo.Orders (
    Order_ID     INT IDENTITY(1,1) NOT NULL,
    Order_Date   DATETIME2(0)      NOT NULL CONSTRAINT DF_Orders_Date   DEFAULT SYSDATETIME(),
    Status       VARCHAR(25)       NOT NULL CONSTRAINT DF_Orders_Status DEFAULT 'Pending Confirmation',
    Shipping_Fee DECIMAL(15,0)     NOT NULL CONSTRAINT DF_Orders_Fee    DEFAULT 0,
    Delivered_At DATETIME2(0)      NULL,
    Company_ID   INT               NOT NULL,
    Voucher_Code VARCHAR(20)       NULL,
    Buyer_ID     INT               NOT NULL,
    Street       NVARCHAR(150)     NOT NULL,
    Ward         NVARCHAR(60)      NOT NULL,
    District     NVARCHAR(60)      NOT NULL,
    City         NVARCHAR(60)      NOT NULL,
    CONSTRAINT PK_Orders             PRIMARY KEY (Order_ID),
    CONSTRAINT UQ_Orders_Order_Buyer UNIQUE (Order_ID, Buyer_ID),
    CONSTRAINT FK_Orders_Buyer       FOREIGN KEY (Buyer_ID)   REFERENCES dbo.Buyer (User_ID),
    CONSTRAINT FK_Orders_Company     FOREIGN KEY (Company_ID) REFERENCES dbo.Shipping_Company (Company_ID),
    CONSTRAINT FK_Orders_Address     FOREIGN KEY (Buyer_ID, Street, Ward, District, City)
                                     REFERENCES dbo.Address (User_ID, Street, Ward, District, City),
    CONSTRAINT FK_Orders_BuyerVoucher FOREIGN KEY (Buyer_ID, Voucher_Code)
                                     REFERENCES dbo.Buyer_Voucher (Buyer_ID, Voucher_Code),
    CONSTRAINT CK_Orders_Status      CHECK (Status IN ('Pending Confirmation', 'Confirmed', 'Shipping',
                                                       'Delivery Successful', 'Cancelled')),
    CONSTRAINT CK_Orders_Fee         CHECK (Shipping_Fee BETWEEN 0 AND 5000000),
    CONSTRAINT CK_Orders_Delivered   CHECK (Delivered_At IS NULL
                                            OR (Status = 'Delivery Successful' AND Delivered_At >= Order_Date))
);
GO

-- Voucher single-use per buyer: at most ONE non-cancelled order per
-- (buyer, voucher). A filtered unique index is declarative and race-free.
CREATE UNIQUE INDEX UX_Orders_Buyer_Voucher
    ON dbo.Orders (Buyer_ID, Voucher_Code)
    WHERE Voucher_Code IS NOT NULL AND Status <> 'Cancelled';
GO

-- 1.13 Order_Detail (ORDERED: M:N between Orders and Product_Variant) -------
-- Product_ID is NOT stored here: it is derivable through Variant_ID.
CREATE TABLE dbo.Order_Detail (
    Order_ID                 INT           NOT NULL,
    Variant_ID               INT           NOT NULL,
    Purchased_Quantity       INT           NOT NULL,
    Unit_Price_At_Order_Time DECIMAL(15,0) NOT NULL,
    CONSTRAINT PK_Order_Detail         PRIMARY KEY (Order_ID, Variant_ID),
    CONSTRAINT FK_Order_Detail_Orders  FOREIGN KEY (Order_ID)   REFERENCES dbo.Orders (Order_ID) ON DELETE CASCADE,
    CONSTRAINT FK_Order_Detail_Variant FOREIGN KEY (Variant_ID) REFERENCES dbo.Product_Variant (Variant_ID),
    CONSTRAINT CK_Order_Detail_Qty     CHECK (Purchased_Quantity > 0),
    CONSTRAINT CK_Order_Detail_Price   CHECK (Unit_Price_At_Order_Time BETWEEN 1 AND 1000000000)
);
GO

-- 1.14 Payment ----------------------------------------------------------------
CREATE TABLE dbo.Payment (
    Payment_ID     INT IDENTITY(1,1) NOT NULL,
    Method         VARCHAR(20)       NOT NULL,
    Amount         DECIMAL(15,0)     NOT NULL,
    Payment_Status VARCHAR(10)       NOT NULL CONSTRAINT DF_Payment_Status DEFAULT 'Pending',
    Paid_Date      DATETIME2(0)      NULL,
    Order_ID       INT               NOT NULL,
    CONSTRAINT PK_Payment        PRIMARY KEY (Payment_ID),
    CONSTRAINT UQ_Payment_Order  UNIQUE (Order_ID),
    CONSTRAINT FK_Payment_Orders FOREIGN KEY (Order_ID) REFERENCES dbo.Orders (Order_ID),
    CONSTRAINT CK_Payment_Method CHECK (Method IN ('COD', 'Bank Transfer', 'E-Wallet', 'Credit Card')),
    CONSTRAINT CK_Payment_Status CHECK (Payment_Status IN ('Pending', 'Paid', 'Failed', 'Refunded')),
    CONSTRAINT CK_Payment_Amount CHECK (Amount BETWEEN 1 AND 1000000000000),
    CONSTRAINT CK_Payment_PaidDate CHECK (
           (Payment_Status IN ('Paid', 'Refunded') AND Paid_Date IS NOT NULL)
        OR (Payment_Status IN ('Pending', 'Failed') AND Paid_Date IS NULL))
);
GO

-- 1.15 Return_Request -----------------------------------------------------------
-- The composite FK (Order_ID, Buyer_ID) -> Orders guarantees the requesting
-- buyer is the buyer who placed the order (Buyer_ID is redundant by 3NF
-- standards but required by the ERD's REQUESTS relationship, so we make the
-- database police the redundancy instead of trusting the application).
CREATE TABLE dbo.Return_Request (
    Return_ID     INT IDENTITY(1,1) NOT NULL,
    Request_Date  DATETIME2(0)      NOT NULL CONSTRAINT DF_Return_Date   DEFAULT SYSDATETIME(),
    Reason        NVARCHAR(500)     NOT NULL,
    Return_Status VARCHAR(10)       NOT NULL CONSTRAINT DF_Return_Status DEFAULT 'Requested',
    Refund_Amount DECIMAL(15,0)     NOT NULL CONSTRAINT DF_Return_Refund DEFAULT 0,
    Order_ID      INT               NOT NULL,
    Buyer_ID      INT               NOT NULL,
    CONSTRAINT PK_Return_Request       PRIMARY KEY (Return_ID),
    CONSTRAINT FK_Return_Order_Buyer   FOREIGN KEY (Order_ID, Buyer_ID) REFERENCES dbo.Orders (Order_ID, Buyer_ID),
    CONSTRAINT FK_Return_Buyer         FOREIGN KEY (Buyer_ID) REFERENCES dbo.Buyer (User_ID),
    CONSTRAINT CK_Return_Status        CHECK (Return_Status IN ('Requested', 'Approved', 'Rejected', 'Refunded')),
    CONSTRAINT CK_Return_Refund        CHECK (Refund_Amount BETWEEN 0 AND 1000000000000)
);
GO

-- 1.16 Review (weak entity of Product; Review_ID is a global IDENTITY) -----------
CREATE TABLE dbo.Review (
    Product_ID   INT               NOT NULL,
    Review_ID    INT IDENTITY(1,1) NOT NULL,
    Rating_Score TINYINT           NOT NULL,
    Comment      NVARCHAR(1000)    NULL,
    Review_Date  DATETIME2(0)      NOT NULL CONSTRAINT DF_Review_Date DEFAULT SYSDATETIME(),
    Buyer_ID     INT               NOT NULL,
    CONSTRAINT PK_Review          PRIMARY KEY (Product_ID, Review_ID),
    CONSTRAINT FK_Review_Product  FOREIGN KEY (Product_ID) REFERENCES dbo.Product (Product_ID) ON DELETE CASCADE,
    CONSTRAINT FK_Review_Buyer    FOREIGN KEY (Buyer_ID)   REFERENCES dbo.Buyer (User_ID),
    CONSTRAINT CK_Review_Rating   CHECK (Rating_Score BETWEEN 1 AND 5)
);
GO

/* ---------------------------------------------------------------------
   2. INDEXES on foreign-key columns
      SQL Server does NOT index FK columns automatically. Without these,
      every parent DELETE/UPDATE and every join scans the child table.
   --------------------------------------------------------------------- */
CREATE INDEX IX_Category_Parent      ON dbo.Category (Parent_Category_ID);
CREATE INDEX IX_Product_Category     ON dbo.Product (Category_ID);
CREATE INDEX IX_Product_Seller       ON dbo.Product (Seller_ID);
CREATE INDEX IX_Orders_Buyer         ON dbo.Orders (Buyer_ID);
CREATE INDEX IX_Orders_Voucher       ON dbo.Orders (Voucher_Code) WHERE Voucher_Code IS NOT NULL;
CREATE INDEX IX_Orders_Company       ON dbo.Orders (Company_ID);
CREATE INDEX IX_Order_Detail_Variant ON dbo.Order_Detail (Variant_ID);
CREATE INDEX IX_Review_Buyer         ON dbo.Review (Buyer_ID);
CREATE INDEX IX_Return_Order_Buyer   ON dbo.Return_Request (Order_ID, Buyer_ID);
GO

/* ---------------------------------------------------------------------
   3. VIEWS  (derived attributes - computed on read, never stored)
   --------------------------------------------------------------------- */

-- Total_Amount = Subtotal - Discount_Amount + Shipping_Fee
--   Subtotal        = SUM(Purchased_Quantity * Unit_Price_At_Order_Time)
--   Discount_Amount = MIN( ROUND(Subtotal * Discount_Percent / 100, 0),
--                          Max_Discount_Amount )          (0 if no voucher)
CREATE VIEW dbo.vw_Order_Total AS
SELECT o.Order_ID,
       o.Buyer_ID,
       s.Subtotal,
       d.Discount_Amount,
       o.Shipping_Fee,
       CAST(s.Subtotal - d.Discount_Amount + o.Shipping_Fee AS DECIMAL(15,0)) AS Total_Amount
FROM dbo.Orders AS o
LEFT JOIN dbo.Voucher AS v ON v.Voucher_Code = o.Voucher_Code
CROSS APPLY (SELECT CAST(ISNULL(SUM(od.Purchased_Quantity * od.Unit_Price_At_Order_Time), 0) AS DECIMAL(15,0)) AS Subtotal
             FROM dbo.Order_Detail AS od
             WHERE od.Order_ID = o.Order_ID) AS s
CROSS APPLY (SELECT CASE
                      WHEN v.Voucher_Code IS NULL THEN CAST(0 AS DECIMAL(15,0))
                      WHEN ROUND(s.Subtotal * v.Discount_Percent / 100.0, 0) > v.Max_Discount_Amount
                           THEN v.Max_Discount_Amount
                      ELSE CAST(ROUND(s.Subtotal * v.Discount_Percent / 100.0, 0) AS DECIMAL(15,0))
                    END AS Discount_Amount) AS d;
GO

-- Average_Rating: AVG() of an INT column returns an INT in T-SQL (4.6 -> 4),
-- so cast to DECIMAL first. Products with no reviews yield NULL, not 0.
CREATE VIEW dbo.vw_Product_Rating AS
SELECT p.Product_ID,
       CAST(AVG(CAST(r.Rating_Score AS DECIMAL(5,2))) AS DECIMAL(3,2)) AS Average_Rating,
       COUNT(r.Review_ID) AS Review_Count
FROM dbo.Product AS p
LEFT JOIN dbo.Review AS r ON r.Product_ID = p.Product_ID
GROUP BY p.Product_ID;
GO

-- Shop rating (used by the Phase 3 sample data): mean rating over every
-- review of every product the seller owns.
CREATE VIEW dbo.vw_Seller_Rating AS
SELECT s.User_ID AS Seller_ID,
       s.Shop_Name,
       CAST(AVG(CAST(r.Rating_Score AS DECIMAL(5,2))) AS DECIMAL(3,2)) AS Shop_Rating,
       COUNT(r.Review_ID) AS Review_Count
FROM dbo.Seller AS s
LEFT JOIN dbo.Product AS p ON p.Seller_ID = s.User_ID
LEFT JOIN dbo.Review  AS r ON r.Product_ID = p.Product_ID
GROUP BY s.User_ID, s.Shop_Name;
GO

/* ---------------------------------------------------------------------
   4. TRIGGERS  (only for rules a CREATE TABLE constraint cannot express:
      they read OTHER tables or OTHER ROWS, or compare OLD vs NEW values)
      Pattern: ROLLBACK + THROW => the offending statement is undone and
      the caller gets a readable message (error numbers 51001+).
   --------------------------------------------------------------------- */

-- 4.1 Seller Age (a): a user who becomes a seller must be 18+ ---------------
-- CHECK is row-local; Age lives in Users and the role in Seller (2 tables).
CREATE TRIGGER dbo.trg_Seller_Age ON dbo.Seller
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS (SELECT 1
               FROM inserted AS i
               JOIN dbo.Users AS u ON u.User_ID = i.User_ID
               WHERE u.Age < 18)
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 51001, N'Seller Age Constraint: a user must be at least 18 to be a seller.', 1;
    END
END;
GO

-- 4.2 Seller Age (b): an existing seller cannot be edited to under 18 -------
CREATE TRIGGER dbo.trg_Users_DobSellerAge ON dbo.Users
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT UPDATE(Date_of_Birth) RETURN;
    IF EXISTS (SELECT 1
               FROM inserted AS i
               JOIN dbo.Seller AS s ON s.User_ID = i.User_ID
               JOIN dbo.Users  AS u ON u.User_ID = i.User_ID
               WHERE u.Age < 18)
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 51002, N'Seller Age Constraint: this change would make an existing seller younger than 18.', 1;
    END
END;
GO

-- 4.3 Category Recursion: no cycles through any chain of ancestors ----------
-- CHECK only sees one row; a cycle (A->B->C->A) spans many rows.
CREATE TRIGGER dbo.trg_Category_NoCycle ON dbo.Category
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @loops INT = 0;

    ;WITH Ancestors AS (
        SELECT c.Category_ID AS Start_ID, c.Parent_Category_ID AS Ancestor_ID
        FROM dbo.Category AS c
        JOIN inserted     AS i ON i.Category_ID = c.Category_ID
        WHERE c.Parent_Category_ID IS NOT NULL
        UNION ALL
        SELECT a.Start_ID, p.Parent_Category_ID
        FROM Ancestors    AS a
        JOIN dbo.Category AS p ON p.Category_ID = a.Ancestor_ID
        WHERE p.Parent_Category_ID IS NOT NULL
          AND a.Ancestor_ID <> a.Start_ID          -- stop as soon as we are back at the start
    )
    SELECT @loops = COUNT(*) FROM Ancestors WHERE Ancestor_ID = Start_ID;

    IF @loops > 0
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 51003, N'Category Recursion Constraint: a category cannot be its own ancestor.', 1;
    END
END;
GO

-- 4.4 Voucher terms: frozen once used; Quantity cannot drop below usage -----
-- Total_Amount is derived from the voucher, so editing a used voucher would
-- silently rewrite the totals of historical orders.
CREATE TRIGGER dbo.trg_Voucher_Terms ON dbo.Voucher
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    IF EXISTS (SELECT 1
               FROM inserted AS i
               JOIN deleted  AS d ON d.Voucher_Code = i.Voucher_Code
               WHERE (   i.Discount_Percent    <> d.Discount_Percent
                      OR i.Min_Order_Value     <> d.Min_Order_Value
                      OR i.Max_Discount_Amount <> d.Max_Discount_Amount
                      OR i.Start_Date          <> d.Start_Date
                      OR i.End_Date            <> d.End_Date)
                 AND EXISTS (SELECT 1 FROM dbo.Orders AS o WHERE o.Voucher_Code = i.Voucher_Code))
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 51004, N'Voucher Terms Constraint: discount, limits and dates of a voucher that has been used cannot be changed.', 1;
    END

    IF EXISTS (SELECT 1
               FROM inserted AS i
               WHERE i.Quantity < (SELECT COUNT(*) FROM dbo.Orders AS o
                                   WHERE o.Voucher_Code = i.Voucher_Code AND o.Status <> 'Cancelled'))
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 51005, N'Voucher Quantity Constraint: Quantity cannot be lower than the number of orders already using the voucher.', 1;
    END
END;
GO

-- 4.5 Orders: lifecycle, voucher rules, stock movement, delivery stamp ------
CREATE TRIGGER dbo.trg_Orders_Integrity ON dbo.Orders
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @isUpdate BIT = CASE WHEN EXISTS (SELECT 1 FROM deleted) THEN 1 ELSE 0 END;

    -- (1) A new order always starts as 'Pending Confirmation'.
    IF @isUpdate = 0 AND EXISTS (SELECT 1 FROM inserted WHERE Status <> 'Pending Confirmation')
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 51010, N'Status Sequence Constraint: a new order must start as ''Pending Confirmation''.', 1;
    END

    IF @isUpdate = 1
    BEGIN
        -- (2) Status Sequence: only the allowed transitions (needs OLD vs NEW).
        IF EXISTS (SELECT 1
                   FROM inserted AS i
                   JOIN deleted  AS d ON d.Order_ID = i.Order_ID
                   WHERE i.Status <> d.Status
                     AND NOT EXISTS (SELECT 1
                                     FROM (VALUES ('Pending Confirmation', 'Confirmed'),
                                                  ('Pending Confirmation', 'Cancelled'),
                                                  ('Confirmed',            'Shipping'),
                                                  ('Confirmed',            'Cancelled'),
                                                  ('Shipping',             'Delivery Successful')) AS t(From_S, To_S)
                                     WHERE t.From_S = d.Status AND t.To_S = i.Status))
        BEGIN
            ROLLBACK TRANSACTION;
            THROW 51011, N'Status Sequence Constraint: illegal order status transition.', 1;
        END

        -- (3) Money-affecting columns are frozen once the order leaves 'Pending Confirmation'.
        IF EXISTS (SELECT 1
                   FROM inserted AS i
                   JOIN deleted  AS d ON d.Order_ID = i.Order_ID
                   WHERE d.Status <> 'Pending Confirmation'
                     AND (   i.Shipping_Fee <> d.Shipping_Fee
                          OR ISNULL(i.Voucher_Code, '') <> ISNULL(d.Voucher_Code, '')
                          OR i.Buyer_ID <> d.Buyer_ID))
        BEGIN
            ROLLBACK TRANSACTION;
            THROW 51012, N'Order Freeze Constraint: shipping fee, voucher and buyer cannot change after the order is confirmed.', 1;
        END

        -- (3b) Delivered_At is write-once (reviews are validated against it).
        IF EXISTS (SELECT 1
                   FROM inserted AS i
                   JOIN deleted  AS d ON d.Order_ID = i.Order_ID
                   WHERE d.Delivered_At IS NOT NULL
                     AND ISNULL(i.Delivered_At, '1900-01-01') <> d.Delivered_At)
        BEGIN
            ROLLBACK TRANSACTION;
            THROW 51013, N'Review Timing Constraint: Delivered_At cannot be changed once set.', 1;
        END
    END

    -- (4) Voucher Validity: the order date must fall inside the voucher's window (inclusive).
    IF EXISTS (SELECT 1
               FROM inserted AS i
               JOIN dbo.Voucher AS v ON v.Voucher_Code = i.Voucher_Code
               WHERE CAST(i.Order_Date AS DATE) NOT BETWEEN v.Start_Date AND v.End_Date)
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 51014, N'Voucher Validity Constraint: the order date is outside the voucher''s Start_Date..End_Date.', 1;
    END

    -- (5) Voucher Quantity: non-cancelled orders using a voucher <= Quantity.
    --     UPDLOCK+HOLDLOCK serialises two checkouts racing for the last use.
    IF EXISTS (SELECT 1
               FROM dbo.Voucher AS v WITH (UPDLOCK, HOLDLOCK)
               WHERE v.Voucher_Code IN (SELECT Voucher_Code FROM inserted WHERE Voucher_Code IS NOT NULL)
                 AND (SELECT COUNT(*) FROM dbo.Orders AS o
                      WHERE o.Voucher_Code = v.Voucher_Code AND o.Status <> 'Cancelled') > v.Quantity)
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 51015, N'Voucher Quantity Constraint: this voucher has no uses left.', 1;
    END

    IF @isUpdate = 0 RETURN;   -- everything below reacts to status CHANGES

    DECLARE @Confirmed TABLE (Order_ID INT PRIMARY KEY);
    DECLARE @Restored  TABLE (Order_ID INT PRIMARY KEY);
    DECLARE @Delivered TABLE (Order_ID INT PRIMARY KEY);

    INSERT @Confirmed SELECT i.Order_ID FROM inserted i JOIN deleted d ON d.Order_ID = i.Order_ID
                      WHERE d.Status = 'Pending Confirmation' AND i.Status = 'Confirmed';
    INSERT @Restored  SELECT i.Order_ID FROM inserted i JOIN deleted d ON d.Order_ID = i.Order_ID
                      WHERE d.Status = 'Confirmed' AND i.Status = 'Cancelled';
    INSERT @Delivered SELECT i.Order_ID FROM inserted i JOIN deleted d ON d.Order_ID = i.Order_ID
                      WHERE d.Status = 'Shipping' AND i.Status = 'Delivery Successful';

    -- (6a) Order Completeness: an order needs >= 1 line before it can be confirmed.
    IF EXISTS (SELECT 1 FROM @Confirmed AS c
               WHERE NOT EXISTS (SELECT 1 FROM dbo.Order_Detail AS od WHERE od.Order_ID = c.Order_ID))
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 51016, N'Order Completeness Constraint: an order with no items cannot be confirmed.', 1;
    END

    -- (6b) Voucher Condition: product subtotal >= Min_Order_Value (checked here because
    --      the lines are inserted AFTER the order header, so the header alone cannot know).
    IF EXISTS (SELECT 1
               FROM @Confirmed AS c
               JOIN dbo.Orders         AS o ON o.Order_ID = c.Order_ID
               JOIN dbo.Voucher        AS v ON v.Voucher_Code = o.Voucher_Code
               JOIN dbo.vw_Order_Total AS t ON t.Order_ID = c.Order_ID
               WHERE t.Subtotal < v.Min_Order_Value)
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 51017, N'Voucher Condition Constraint: the order''s product total is below the voucher''s Min_Order_Value.', 1;
    END

    -- (6c) Inventory Constraint (re-check at confirmation, summed per variant across ALL
    --      orders confirmed by this statement; UPDLOCK stops concurrent overselling).
    IF EXISTS (SELECT 1
               FROM (SELECT od.Variant_ID, SUM(od.Purchased_Quantity) AS Qty
                     FROM @Confirmed AS c
                     JOIN dbo.Order_Detail AS od ON od.Order_ID = c.Order_ID
                     GROUP BY od.Variant_ID) AS need
               JOIN dbo.Product_Variant AS v WITH (UPDLOCK, HOLDLOCK) ON v.Variant_ID = need.Variant_ID
               WHERE need.Qty > v.Stock_Quantity)
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 51018, N'Inventory Constraint: not enough stock to confirm this order.', 1;
    END

    -- (6d) Inventory Update: confirmed orders take stock out.
    UPDATE v
    SET v.Stock_Quantity = v.Stock_Quantity - need.Qty
    FROM dbo.Product_Variant AS v
    JOIN (SELECT od.Variant_ID, SUM(od.Purchased_Quantity) AS Qty
          FROM @Confirmed AS c
          JOIN dbo.Order_Detail AS od ON od.Order_ID = c.Order_ID
          GROUP BY od.Variant_ID) AS need ON need.Variant_ID = v.Variant_ID;

    -- (7) Cancelling a CONFIRMED order puts the stock back.
    UPDATE v
    SET v.Stock_Quantity = v.Stock_Quantity + back.Qty
    FROM dbo.Product_Variant AS v
    JOIN (SELECT od.Variant_ID, SUM(od.Purchased_Quantity) AS Qty
          FROM @Restored AS r
          JOIN dbo.Order_Detail AS od ON od.Order_ID = r.Order_ID
          GROUP BY od.Variant_ID) AS back ON back.Variant_ID = v.Variant_ID;

    -- (8) Stamp Delivered_At unless the caller supplied it in the same UPDATE.
    UPDATE o
    SET o.Delivered_At = SYSDATETIME()
    FROM dbo.Orders AS o
    JOIN @Delivered AS x ON x.Order_ID = o.Order_ID
    WHERE o.Delivered_At IS NULL;
END;
GO

-- 4.6 Orders are history: only 'Pending Confirmation' orders may be deleted ---
CREATE TRIGGER dbo.trg_Orders_NoDelete ON dbo.Orders
AFTER DELETE
AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS (SELECT 1 FROM deleted WHERE Status <> 'Pending Confirmation')
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 51019, N'Order History Constraint: only orders that are still ''Pending Confirmation'' can be deleted.', 1;
    END
END;
GO

-- 4.7 Order_Detail: stock check at checkout + freeze after confirmation/payment
CREATE TRIGGER dbo.trg_OrderDetail_Rules ON dbo.Order_Detail
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Affected TABLE (Order_ID INT PRIMARY KEY);
    INSERT @Affected
    SELECT Order_ID FROM inserted
    UNION
    SELECT Order_ID FROM deleted;

    -- Order Freeze: lines may only change while the order is pending AND unpaid
    -- (otherwise the derived Total_Amount would drift away from Payment.Amount).
    IF EXISTS (SELECT 1
               FROM @Affected AS a
               JOIN dbo.Orders AS o ON o.Order_ID = a.Order_ID
               WHERE o.Status <> 'Pending Confirmation'
                  OR EXISTS (SELECT 1 FROM dbo.Payment AS p
                             WHERE p.Order_ID = o.Order_ID AND p.Payment_Status IN ('Paid', 'Refunded')))
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 51020, N'Order Freeze Constraint: items cannot change once the order is confirmed or paid.', 1;
    END

    -- Inventory Constraint at checkout: quantity <= variant stock right now.
    IF EXISTS (SELECT 1
               FROM inserted AS i
               JOIN dbo.Product_Variant AS v ON v.Variant_ID = i.Variant_ID
               WHERE i.Purchased_Quantity > v.Stock_Quantity)
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 51021, N'Inventory Constraint: Purchased_Quantity exceeds the stock available for this variant.', 1;
    END
END;
GO

-- 4.8 Payment: status sequence + Amount must equal the derived Total_Amount ---
CREATE TRIGGER dbo.trg_Payment_Rules ON dbo.Payment
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @isUpdate BIT = CASE WHEN EXISTS (SELECT 1 FROM deleted) THEN 1 ELSE 0 END;

    IF @isUpdate = 0 AND EXISTS (SELECT 1 FROM inserted WHERE Payment_Status <> 'Pending')
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 51030, N'Status Sequence Constraint: a new payment must start as ''Pending''.', 1;
    END

    IF @isUpdate = 1
       AND EXISTS (SELECT 1
                   FROM inserted AS i
                   JOIN deleted  AS d ON d.Payment_ID = i.Payment_ID
                   WHERE i.Payment_Status <> d.Payment_Status
                     AND NOT EXISTS (SELECT 1
                                     FROM (VALUES ('Pending', 'Paid'),
                                                  ('Pending', 'Failed'),
                                                  ('Paid',    'Refunded')) AS t(From_S, To_S)
                                     WHERE t.From_S = d.Payment_Status AND t.To_S = i.Payment_Status))
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 51031, N'Status Sequence Constraint: illegal payment status transition.', 1;
    END

    IF EXISTS (SELECT 1
               FROM inserted AS i
               JOIN dbo.vw_Order_Total AS t ON t.Order_ID = i.Order_ID
               WHERE i.Payment_Status IN ('Paid', 'Refunded')
                 AND i.Amount <> t.Total_Amount)
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 51032, N'Payment Amount Constraint: a confirmed payment must equal the order''s Total_Amount.', 1;
    END
END;
GO

-- 4.9 Return_Request: status sequence -----------------------------------------
CREATE TRIGGER dbo.trg_Return_StatusSequence ON dbo.Return_Request
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @isUpdate BIT = CASE WHEN EXISTS (SELECT 1 FROM deleted) THEN 1 ELSE 0 END;

    IF @isUpdate = 0 AND EXISTS (SELECT 1 FROM inserted WHERE Return_Status <> 'Requested')
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 51040, N'Status Sequence Constraint: a new return request must start as ''Requested''.', 1;
    END

    IF @isUpdate = 1
       AND EXISTS (SELECT 1
                   FROM inserted AS i
                   JOIN deleted  AS d ON d.Return_ID = i.Return_ID
                   WHERE i.Return_Status <> d.Return_Status
                     AND NOT EXISTS (SELECT 1
                                     FROM (VALUES ('Requested', 'Approved'),
                                                  ('Requested', 'Rejected'),
                                                  ('Approved',  'Refunded')) AS t(From_S, To_S)
                                     WHERE t.From_S = d.Return_Status AND t.To_S = i.Return_Status))
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 51041, N'Status Sequence Constraint: illegal return status transition.', 1;
    END
END;
GO

-- 4.10 Review: Eligibility + Timing --------------------------------------------
-- REVIEW has no Order_ID, so both rules read as "there EXISTS a delivered order
-- of this buyer that contains a variant of this product":
--   Eligibility: at least one such order exists.
--   Timing     : at least one such order was delivered on or before the review DATE.
CREATE TRIGGER dbo.trg_Review_Rules ON dbo.Review
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    IF EXISTS (SELECT 1
               FROM inserted AS i
               WHERE NOT EXISTS (SELECT 1
                                 FROM dbo.Orders AS o
                                 JOIN dbo.Order_Detail    AS od ON od.Order_ID   = o.Order_ID
                                 JOIN dbo.Product_Variant AS pv ON pv.Variant_ID = od.Variant_ID
                                 WHERE o.Buyer_ID = i.Buyer_ID
                                   AND pv.Product_ID = i.Product_ID
                                   AND o.Status = 'Delivery Successful'))
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 51050, N'Review Eligibility Constraint: the buyer has no completed order containing this product.', 1;
    END

    IF EXISTS (SELECT 1
               FROM inserted AS i
               WHERE NOT EXISTS (SELECT 1
                                 FROM dbo.Orders AS o
                                 JOIN dbo.Order_Detail    AS od ON od.Order_ID   = o.Order_ID
                                 JOIN dbo.Product_Variant AS pv ON pv.Variant_ID = od.Variant_ID
                                 WHERE o.Buyer_ID = i.Buyer_ID
                                   AND pv.Product_ID = i.Product_ID
                                   AND o.Status = 'Delivery Successful'
                                   AND CAST(o.Delivered_At AS DATE) <= CAST(i.Review_Date AS DATE)))
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 51051, N'Review Timing Constraint: Review_Date cannot be earlier than the delivery date.', 1;
    END
END;
GO

PRINT 'ShopeeDB schema created: 17 tables, 3 views, 10 triggers.';
GO
