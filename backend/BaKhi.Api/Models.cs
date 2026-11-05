using System.ComponentModel;
using System.ComponentModel.DataAnnotations;

namespace BaKhi.Api;

// Request bodies. Names and examples show up in Swagger.

public record RegisterRequest(
    [property: Required, Description("Tên hiển thị, 2–40 ký tự"), DefaultValue("Người chơi")] string DisplayName,
    [property: Required, Description("Email đăng ký"), DefaultValue("player@example.com")] string Email,
    [property: Required, Description("Ít nhất 8 ký tự, có chữ và số"), DefaultValue("matkhau123")] string Password);

public record LoginRequest(
    [property: Required, DefaultValue("player@example.com")] string Email,
    [property: Required, DefaultValue("matkhau123")] string Password);

public record VerifyOtpRequest(
    [property: Required, DefaultValue("player@example.com")] string Email,
    [property: Required, Description("Mã gồm các chữ số trong email"), DefaultValue("123456")] string Code,
    [property: Description("Luôn là recovery (đặt lại mật khẩu)"), DefaultValue("recovery")] string Type = "recovery");

public record EmailRequest([property: Required, DefaultValue("player@example.com")] string Email);

public record RefreshRequest([property: Required, Description("refresh_token nhận được khi đăng nhập")] string RefreshToken);

public record NewPasswordRequest([property: Required, DefaultValue("matkhaumoi123")] string Password);

public record StartGameRequest(
    [property: Required, Description("sudoku | puzzle | caro"), DefaultValue("sudoku")] string Game,
    [property: Required, Description("easy | medium | hard"), DefaultValue("easy")] string Difficulty);

public record SubmitResultRequest(
    [property: Required, Description("sudoku | puzzle | caro"), DefaultValue("sudoku")] string Game,
    [property: Required, Description("easy | medium | hard"), DefaultValue("easy")] string Difficulty,
    [property: Description("Thời gian chơi (giây)"), DefaultValue(300)] int Seconds,
    [property: Description("Số lỗi"), DefaultValue(1)] int Mistakes,
    [property: Description("Số nước đi"), DefaultValue(45)] int Moves,
    [property: Description("win | loss | draw"), DefaultValue("win")] string Outcome,
    [property: Description("Mã phiên từ POST /api/games/sessions; thiếu thì kết quả không được xếp hạng")] Guid? SessionId = null,
    [property: Description("Mã kết quả; gửi lại cùng mã không tạo bản ghi trùng")] Guid? ResultId = null,
    DateTimeOffset? PlayedAt = null);

public record CreateChallengeRequest(
    [property: Required, Description("Id người được mời")] Guid OpponentId,
    [property: Description("sudoku | caro"), DefaultValue("caro")] string Game = "caro",
    [property: Description("easy | medium | hard (Sudoku)"), DefaultValue("easy")] string Difficulty = "easy");

public record SudokuSubmitRequest(
    [property: Required, Description("81 số 1–9, theo hàng từ trái sang phải")] int[] Answer,
    [property: Description("Số lỗi đã mắc"), DefaultValue(0)] int Mistakes = 0);

public record CaroMoveRequest(
    [property: Description("Hàng 0–14"), DefaultValue(7)] int Row,
    [property: Description("Cột 0–14"), DefaultValue(7)] int Col);

public record SendMessageRequest(
    [property: Required, Description("Id người nhận")] Guid RecipientId,
    [property: Required, Description("Nội dung, 1–2000 ký tự"), DefaultValue("Chào bạn!")] string Body,
    [property: Description("Mã tin nhắn do app tạo; gửi lại cùng mã không tạo tin trùng")] Guid? Id = null);
