Create Database Project
Use Project
----------------------------------------
CREATE TABLE Users (
    UserID INT IDENTITY(1,1) PRIMARY KEY,  -- Cột tự tăng, khóa chính
    Username VARCHAR(50) NOT NULL UNIQUE,  -- Tên người dùng, không được trùng
    PasswordHash VARCHAR(255) NOT NULL,    -- Mật khẩu
    Email VARCHAR(100) NOT NULL UNIQUE,    -- Email, không được trùng
    Phone VARCHAR(15) NULL,                -- Số điện thoại, có thể null
    CreatedAt DATETIME DEFAULT GETDATE(),  -- Thời gian tạo, mặc định là thời gian hiện tại
    UpdatedAt DATETIME DEFAULT GETDATE()   -- Thời gian cập nhật, mặc định là thời gian hiện tại
);

----------------------------------------

CREATE TRIGGER trg_UpdateUsersUpdatedAt
ON Users
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    -- Cập nhật cột UpdatedAt chỉ khi giá trị cột UpdatedAt không thay đổi
    IF (NOT EXISTS (
        SELECT 1
        FROM inserted i
        JOIN deleted d ON i.UserID = d.UserID
        WHERE i.UpdatedAt = d.UpdatedAt
    ))
    BEGIN
        UPDATE Users
        SET UpdatedAt = GETDATE()
        WHERE UserID IN (SELECT DISTINCT UserID FROM inserted);
    END
END;

----------------------------------------

CREATE FUNCTION fn_GetUserInfo (@UserID INT) -- Lấy thông tin người dùng
RETURNS TABLE
AS
RETURN
(
    SELECT UserID, Username, PasswordHash, Email, Phone, CreatedAt, UpdatedAt
    FROM Users
    WHERE UserID = @UserID
);

----------------------------------------

CREATE PROCEDURE sp_GetUsers -- Lấy danh sách người dùng
AS
BEGIN
    SET NOCOUNT ON;

    SELECT UserID, Username, PasswordHash, Email, Phone, CreatedAt, UpdatedAt
    FROM Users;
END;

----------------------------------------

CREATE PROCEDURE sp_GetUserByUsername -- Lấy thông tin người dùng bằng username
    @Username VARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT UserID, Username, PasswordHash, Email, Phone, CreatedAt, UpdatedAt
    FROM Users
    WHERE Username = @Username;
END;

----------------------------------------

CREATE PROCEDURE sp_GetUserByEmail -- Lấy thông tin người dùng bằng email
    @Email VARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT UserID, Username, PasswordHash, Email, Phone, CreatedAt, UpdatedAt
    FROM Users
    WHERE Email = @Email;
END;

----------------------------------------

CREATE PROCEDURE sp_ThemUser --Thêm người dùng mới (Có sử dụng check tồn tại của fn_username và fn_email)
    @Username VARCHAR(50),
    @PasswordHash VARCHAR(255),
    @Email VARCHAR(100),
    @Phone VARCHAR(15) NULL
AS
BEGIN
    SET NOCOUNT ON;

    -- Kiểm tra xem Username hoặc Email đã tồn tại chưa
    IF dbo.fn_UsernameExists(@Username) = 1
    BEGIN
        RAISERROR ('Tên người dùng đã tồn tại', 16, 1);
        RETURN;
    END

    IF dbo.fn_EmailExists(@Email) = 1
    BEGIN
        RAISERROR ('Email đã tồn tại', 16, 1);
        RETURN;
    END

    -- Thêm người dùng mới
    INSERT INTO Users (Username, PasswordHash, Email, Phone)
    VALUES (@Username, @PasswordHash, @Email, @Phone);
END;

----------------------------------------

CREATE PROCEDURE sp_UpdateUser -- Cập nhật thông tin người dùng
    @UserID INT,
    @Username VARCHAR(50) = NULL,
    @PasswordHash VARCHAR(255) = NULL,
    @Email VARCHAR(100) = NULL,
    @Phone VARCHAR(15) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    -- Kiểm tra xem UserID có tồn tại không
    IF NOT EXISTS (SELECT 1 FROM Users WHERE UserID = @UserID)
    BEGIN
        RAISERROR ('Người dùng không tồn tại', 16, 1);
        RETURN;
    END

    -- Cập nhật thông tin người dùng
    UPDATE Users
    SET 
        Username = ISNULL(@Username, Username),
        PasswordHash = ISNULL(@PasswordHash, PasswordHash),
        Email = ISNULL(@Email, Email),
        Phone = ISNULL(@Phone, Phone)
    WHERE UserID = @UserID;
END;

----------------------------------------

CREATE PROCEDURE sp_DeleteUser -- Xoá người dùng
    @UserID INT
AS
BEGIN
    SET NOCOUNT ON;

    -- Kiểm tra xem UserID có tồn tại không
    IF NOT EXISTS (SELECT 1 FROM Users WHERE UserID = @UserID)
    BEGIN
        RAISERROR ('Người dùng không tồn tại', 16, 1);
        RETURN;
    END

    -- Xóa người dùng
    DELETE FROM Users WHERE UserID = @UserID;
END;

----------------------------------------
--TẠO BẢNG ADMIN--
CREATE TABLE Admins (
    AdminID INT IDENTITY(1,1) PRIMARY KEY,
    UserID INT,
    -- Các trường thông tin khác về admin có thể được thêm vào ở đây
    FOREIGN KEY (UserID) REFERENCES Users(UserID)
);

--Thêm UserID là ADMIN--
CREATE PROCEDURE sp_AddAdmin
    @UserID INT
AS
BEGIN
    SET NOCOUNT ON;

    -- Kiểm tra xem UserID đã tồn tại trong bảng Users chưa
    IF NOT EXISTS (SELECT 1 FROM Users WHERE UserID = @UserID)
    BEGIN
        RAISERROR ('UserID không tồn tại trong bảng Users', 16, 1);
        RETURN;
    END

    -- Kiểm tra xem UserID đã là admin chưa
    IF EXISTS (SELECT 1 FROM Admins WHERE UserID = @UserID)
    BEGIN
        RAISERROR ('UserID đã là admin', 16, 1);
        RETURN;
    END

    -- Thêm UserID vào bảng Admins
    INSERT INTO Admins (UserID)
    VALUES (@UserID);
END;

--Lấy danh sách admin
CREATE PROCEDURE sp_GetAdminList
AS
BEGIN
    SET NOCOUNT ON;
    SELECT * FROM Admins;
END;
----------------------------------------
--NGĂN CHẶN XOÁ ADMIN--
ALTER TABLE Users ADD IsAdmin BIT DEFAULT 0; 

CREATE TRIGGER trg_PreventAdminDeletion
ON Users
INSTEAD OF DELETE
AS
BEGIN
    SET NOCOUNT ON;

    -- Kiểm tra xem có người dùng nào là admin trong danh sách cần xóa không
    IF EXISTS (SELECT 1 FROM deleted WHERE UserID IN (SELECT UserID FROM Admins))
    BEGIN
        RAISERROR ('Không thể xóa người dùng admin', 16, 1);
        ROLLBACK TRANSACTION; -- Lưu ý: Bạn cũng có thể sử dụng ROLLBACK TRANSACTION để hủy bỏ thao tác DELETE
        RETURN;
    END

    -- Xóa người dùng không phải admin
    DELETE FROM Users
    WHERE UserID IN (SELECT UserID FROM deleted);
END;

----------------------------------------

CREATE PROCEDURE sp_ChangeUserPassword -- Đổi pass người dùng
    @UserID INT,
    @OldPasswordHash VARCHAR(255),
    @NewPasswordHash VARCHAR(255)
AS
BEGIN
    SET NOCOUNT ON;

    -- Kiểm tra xem UserID và mật khẩu cũ có khớp không
    IF NOT EXISTS (SELECT 1 FROM Users WHERE UserID = @UserID AND PasswordHash = @OldPasswordHash)
    BEGIN
        RAISERROR ('Mật khẩu cũ không đúng', 16, 1);
        RETURN;
    END

    -- Cập nhật mật khẩu mới
    UPDATE Users
    SET PasswordHash = @NewPasswordHash
    WHERE UserID = @UserID;
END;

----------------------------------------

CREATE FUNCTION fn_UsernameExists (@Username VARCHAR(50)) -- Kiểm tra xem username có tồn tại không
RETURNS BIT
AS
BEGIN
    DECLARE @Exists BIT;

    IF EXISTS (SELECT 1 FROM Users WHERE Username = @Username)
        SET @Exists = 1;
    ELSE
        SET @Exists = 0;

    RETURN @Exists;
END;

----------------------------------------

CREATE FUNCTION fn_EmailExists (@Email VARCHAR(100)) -- Kiểm tra email có tồn tại không
RETURNS BIT
AS
BEGIN
    DECLARE @Exists BIT;

    IF EXISTS (SELECT 1 FROM Users WHERE Email = @Email)
        SET @Exists = 1;
    ELSE
        SET @Exists = 0;

    RETURN @Exists;
END;

----------------------------------------
--	<<Tạo bảng Audit và trigger để theo dõi thay đổi dữ liệu người dùng>>
CREATE TABLE UserAudit (
    AuditID INT IDENTITY(1,1) PRIMARY KEY,
    UserID INT,
    Username VARCHAR(50),
    PasswordHash VARCHAR(255),
    Email VARCHAR(100),
    Phone VARCHAR(15),
    CreatedAt DATETIME,
    UpdatedAt DATETIME,
    Action VARCHAR(10),
    ChangeDate DATETIME DEFAULT GETDATE(),
    ChangedBy VARCHAR(50)
);



CREATE TRIGGER trg_AuditUserInsert
ON Users
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO UserAudit (UserID, Username, PasswordHash, Email, Phone, CreatedAt, UpdatedAt, Action, ChangeDate, ChangedBy)
    SELECT UserID, Username, PasswordHash, Email, Phone, CreatedAt, UpdatedAt, 'INSERT', GETDATE(), SYSTEM_USER
    FROM inserted;
END;

CREATE TRIGGER trg_AuditUserUpdate
ON Users
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    -- Chỉ thêm bản ghi vào bảng UserAudit nếu các cột khác ngoài UpdatedAt thay đổi
    IF (NOT EXISTS (
        SELECT 1
        FROM inserted i
        JOIN deleted d ON i.UserID = d.UserID
        WHERE i.Username = d.Username
        AND i.PasswordHash = d.PasswordHash
        AND i.Email = d.Email
        AND i.Phone = d.Phone
        AND i.CreatedAt = d.CreatedAt
        AND i.UpdatedAt = d.UpdatedAt
    ))
    BEGIN
        INSERT INTO UserAudit (UserID, Username, PasswordHash, Email, Phone, CreatedAt, UpdatedAt, Action, ChangeDate, ChangedBy)
        SELECT UserID, Username, PasswordHash, Email, Phone, CreatedAt, UpdatedAt, 'UPDATE', GETDATE(), SYSTEM_USER
        FROM inserted;
    END
END;

CREATE TRIGGER trg_AuditUserDelete
ON Users
AFTER DELETE
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO UserAudit (UserID, Username, PasswordHash, Email, Phone, CreatedAt, UpdatedAt, Action, ChangeDate, ChangedBy)
    SELECT UserID, Username, PasswordHash, Email, Phone, CreatedAt, UpdatedAt, 'DELETE', GETDATE(), SYSTEM_USER
    FROM deleted;
END;



