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
-- Average_Rating is a stored derived value maintained by the Review trigger.
-- NULL means the product has no reviews; otherwise the value is 1.00..5.00.
CREATE TABLE dbo.Product (
    Product_ID  INT IDENTITY(1,1) NOT NULL,
    Name        NVARCHAR(200)     NOT NULL,
    Description NVARCHAR(MAX)     NULL,
    Average_Rating DECIMAL(3,2)    NULL,
    Category_ID INT               NOT NULL,
    Seller_ID   INT               NOT NULL,
    CONSTRAINT PK_Product          PRIMARY KEY (Product_ID),
    CONSTRAINT FK_Product_Category FOREIGN KEY (Category_ID) REFERENCES dbo.Category (Category_ID),
    CONSTRAINT FK_Product_Seller   FOREIGN KEY (Seller_ID)   REFERENCES dbo.Seller (User_ID),
    CONSTRAINT CK_Product_AvgRating CHECK (Average_Rating IS NULL OR Average_Rating BETWEEN 1 AND 5)
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

   --TODO--
   
/* ---------------------------------------------------------------------
   3. VIEWS  (read models and values computed on read)
   --------------------------------------------------------------------- */

   --TODO--
   
-- Total_Amount = Subtotal - Discount_Amount + Shipping_Fee
--   Subtotal        = SUM(Purchased_Quantity * Unit_Price_At_Order_Time)
--   Discount_Amount = MIN( ROUND(Subtotal * Discount_Percent / 100, 0),
--                          Max_Discount_Amount )          (0 if no voucher)

-- Average_Rating: AVG() of an INT column returns an INT in T-SQL (4.6 -> 4),
-- so cast to DECIMAL first. Products with no reviews yield NULL, not 0.
-- Product.Average_Rating stores this derived value; H1_triggers.sql maintains
-- it after Review INSERT/UPDATE/DELETE and backfills existing reviews.

-- Shop rating (used by the Phase 3 sample data): mean rating over every
-- review of every product the seller owns.

/* ---------------------------------------------------------------------
   4. TRIGGERS  (only for rules a CREATE TABLE constraint cannot express:
      they read OTHER tables or OTHER ROWS, or compare OLD vs NEW values)
      Pattern: ROLLBACK + THROW => the offending statement is undone and
      the caller gets a readable message (error numbers 51001+).
   --------------------------------------------------------------------- */

   --TODO--
   
-- 4.1 Seller Age (a): a user who becomes a seller must be 18+ ---------------
-- CHECK is row-local; Age lives in Users and the role in Seller (2 tables).

-- 4.2 Seller Age (b): an existing seller cannot be edited to under 18 -------

-- 4.3 Category Recursion: no cycles through any chain of ancestors ----------
-- CHECK only sees one row; a cycle (A->B->C->A) spans many rows.

-- 4.4 Voucher terms: frozen once used; Quantity cannot drop below usage -----
-- Total_Amount is derived from the voucher, so editing a used voucher would
-- silently rewrite the totals of historical orders.

-- 4.5 Orders: lifecycle, voucher rules, stock movement, delivery stamp ------
    -- (1) A new order always starts as 'Pending Confirmation'.
        -- (2) Status Sequence: only the allowed transitions (needs OLD vs NEW).
        -- (3) Money-affecting columns are frozen once the order leaves 'Pending Confirmation'.
        -- (3b) Delivered_At is write-once (reviews are validated against it).
    -- (4) Voucher Validity: the order date must fall inside the voucher's window (inclusive).
    -- (5) Voucher Quantity: non-cancelled orders using a voucher <= Quantity.
    --     UPDLOCK+HOLDLOCK serialises two checkouts racing for the last use.
    -- (6a) Order Completeness: an order needs >= 1 line before it can be confirmed.
    -- (6b) Voucher Condition: product subtotal >= Min_Order_Value (checked here because
    --      the lines are inserted AFTER the order header, so the header alone cannot know).
    -- (6c) Inventory Constraint (re-check at confirmation, summed per variant across ALL
    --      orders confirmed by this statement; UPDLOCK stops concurrent overselling).
    -- (6d) Inventory Update: confirmed orders take stock out.
    -- (7) Cancelling a CONFIRMED order puts the stock back.
    -- (8) Stamp Delivered_At unless the caller supplied it in the same UPDATE.
-- 4.6 Orders are history: only 'Pending Confirmation' orders may be deleted ---
-- 4.7 Order_Detail: stock check at checkout + freeze after confirmation/payment
-- 4.8 Payment: status sequence + Amount must equal the derived Total_Amount ---
-- 4.9 Return_Request: status sequence -----------------------------------------
-- 4.10 Review: Eligibility + Timing --------------------------------------------
-- REVIEW has no Order_ID, so both rules read as "there EXISTS a delivered order
-- of this buyer that contains a variant of this product":
--   Eligibility: at least one such order exists.
--   Timing     : at least one such order was delivered on or before the review DATE.
