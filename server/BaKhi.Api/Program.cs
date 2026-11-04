using BaKhi.Api;
using Microsoft.OpenApi;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddHttpClient<SupabaseGateway>(c => c.Timeout = TimeSpan.FromSeconds(20));
builder.Services.AddCors(o => o.AddDefaultPolicy(p => p.AllowAnyOrigin().AllowAnyHeader().AllowAnyMethod()));
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen(c =>
{
    c.SwaggerDoc("v1", new OpenApiInfo
    {
        Title = "Bá Khí Game Hub - API",
        Version = "v1",
        Description =
            "API của đồ án Bá Khí Game Hub (Sudoku, Xếp hình, Caro, Rubik).\n\n" +
            "Dữ liệu, đăng nhập và luật chống gian lận nằm trên Supabase (PostgreSQL + hàm SQL); " +
            "API này cung cấp các endpoint REST thống nhất cho chúng.\n\n" +
            "**Cách thử:** gọi `POST /api/auth/login`, sao chép `access_token`, bấm **Authorize** và dán vào.",
    });
    c.AddSecurityDefinition("Bearer", new OpenApiSecurityScheme
    {
        Type = SecuritySchemeType.Http,
        Scheme = "bearer",
        BearerFormat = "JWT",
        Description = "access_token nhận được từ POST /api/auth/login",
    });
    c.AddSecurityRequirement(document => new OpenApiSecurityRequirement
    {
        [new OpenApiSecuritySchemeReference("Bearer", document)] = [],
    });
});

var app = builder.Build();

app.UseCors();
app.UseSwagger();
app.UseSwaggerUI(ui =>
{
    ui.SwaggerEndpoint("/swagger/v1/swagger.json", "BaKhi_API v1");
    ui.DocumentTitle = "Bá Khí Game Hub API";
});
app.MapGet("/", () => Results.Redirect("/swagger")).ExcludeFromDescription();

static string? Bearer(HttpContext ctx) => SupabaseGateway.BearerOf(ctx);

static IResult NeedLogin() => Results.Problem(
    title: "Cần đăng nhập",
    detail: "Gửi header Authorization: Bearer <access_token> (bấm Authorize trong Swagger).",
    statusCode: StatusCodes.Status401Unauthorized);

// ---------- Health ----------
app.MapGet("/api/health", () => Results.Ok(new { status = "ok", time = DateTimeOffset.UtcNow }))
    .WithTags("Health").WithSummary("Kiểm tra API đang chạy");

// ---------- Auth ----------
var auth = app.MapGroup("/api/auth").WithTags("Auth");

auth.MapPost("/register", (RegisterRequest r, SupabaseGateway sb) =>
        sb.Auth(HttpMethod.Post, "signup", new
        {
            email = r.Email.Trim(),
            password = r.Password,
            data = new { display_name = r.DisplayName.Trim() },
        }))
    .WithSummary("Đăng ký tài khoản; mã xác nhận được gửi qua email");

auth.MapPost("/verify-otp", (VerifyOtpRequest r, SupabaseGateway sb) =>
        sb.Auth(HttpMethod.Post, "verify", new { type = r.Type, email = r.Email.Trim(), token = r.Code.Trim() }))
    .WithSummary("Xác nhận mã từ email (đăng ký hoặc quên mật khẩu); trả về access_token");

auth.MapPost("/resend-otp", (EmailRequest r, SupabaseGateway sb) =>
        sb.Auth(HttpMethod.Post, "resend", new { type = "signup", email = r.Email.Trim() }))
    .WithSummary("Gửi lại mã xác nhận đăng ký");

auth.MapPost("/login", (LoginRequest r, SupabaseGateway sb) =>
        sb.Auth(HttpMethod.Post, "token?grant_type=password", new { email = r.Email.Trim(), password = r.Password }))
    .WithSummary("Đăng nhập; trả về access_token (JWT) và refresh_token");

auth.MapPost("/refresh", (RefreshRequest r, SupabaseGateway sb) =>
        sb.Auth(HttpMethod.Post, "token?grant_type=refresh_token", new { refresh_token = r.RefreshToken }))
    .WithSummary("Lấy access_token mới bằng refresh_token");

auth.MapPost("/forgot-password", (EmailRequest r, SupabaseGateway sb) =>
        sb.Auth(HttpMethod.Post, "recover", new { email = r.Email.Trim() }))
    .WithSummary("Gửi mã đặt lại mật khẩu qua email (dùng /verify-otp với type = recovery)");

auth.MapGet("/me", (HttpContext ctx, SupabaseGateway sb) =>
        Bearer(ctx) is { } t ? sb.Auth(HttpMethod.Get, "user", null, t) : Task.FromResult(NeedLogin()))
    .WithSummary("Thông tin tài khoản đang đăng nhập");

auth.MapPut("/password", (NewPasswordRequest r, HttpContext ctx, SupabaseGateway sb) =>
        Bearer(ctx) is { } t ? sb.Auth(HttpMethod.Put, "user", new { password = r.Password }, t) : Task.FromResult(NeedLogin()))
    .WithSummary("Đổi mật khẩu (sau khi xác nhận mã quên mật khẩu)");

// ---------- Players ----------
app.MapGet("/api/players", (HttpContext ctx, SupabaseGateway sb) =>
        sb.Select("profiles?select=id,display_name&order=display_name.asc&limit=100", Bearer(ctx)))
    .WithTags("Players").WithSummary("Danh sách người chơi (tối đa 100)");

// ---------- Games & scoring ----------
var games = app.MapGroup("/api/games").WithTags("Games");

games.MapPost("/sessions", (StartGameRequest r, HttpContext ctx, SupabaseGateway sb) =>
        sb.Rpc("start_game_session", new { game_name = r.Game, level = r.Difficulty }, Bearer(ctx)))
    .WithSummary("Bắt đầu một ván: máy chủ ghi giờ bắt đầu để chống gian lận");

games.MapPost("/results", (SubmitResultRequest r, HttpContext ctx, SupabaseGateway sb) =>
        sb.Rpc("submit_game_result", new
        {
            result_id = r.ResultId ?? Guid.NewGuid(),
            game_session = r.SessionId,
            game_name = r.Game,
            level = r.Difficulty,
            seconds_taken = r.Seconds,
            mistake_count = r.Mistakes,
            move_count = r.Moves,
            result_outcome = r.Outcome,
            played = r.PlayedAt ?? DateTimeOffset.UtcNow,
        }, Bearer(ctx)))
    .WithSummary("Nộp kết quả ván; máy chủ tính điểm và quyết định có xếp hạng hay không");

games.MapGet("/score", (string game, string difficulty, int seconds, int mistakes, string? outcome,
            HttpContext ctx, SupabaseGateway sb) =>
        sb.Rpc("game_score", new { game, difficulty, seconds, mistakes, outcome = outcome ?? "win" }, Bearer(ctx)))
    .WithSummary("Tính thử điểm theo công thức: gốc × hệ số × T / (T + giây), mỗi lỗi −5%");

// ---------- Leaderboard ----------
var board = app.MapGroup("/api/leaderboard").WithTags("Leaderboard");

board.MapGet("/", (string game, string difficulty, HttpContext ctx, SupabaseGateway sb) =>
        sb.Select(
            $"leaderboard?select=*&game=eq.{Uri.EscapeDataString(game)}&difficulty=eq.{Uri.EscapeDataString(difficulty)}" +
            "&order=score.desc,seconds.asc,mistakes.asc,achieved_at.asc&limit=50",
            Bearer(ctx)))
    .WithSummary("Top 50 theo game và độ khó (game: sudoku | puzzle | caro; difficulty: easy | medium | hard)");

board.MapGet("/me", (string game, string difficulty, HttpContext ctx, SupabaseGateway sb) =>
        sb.Rpc("my_leaderboard_rank", new { game_name = game, level = difficulty }, Bearer(ctx)))
    .WithSummary("Hạng của người đang đăng nhập");

// ---------- Challenges ----------
var challenges = app.MapGroup("/api/challenges").WithTags("Challenges");

challenges.MapGet("/", (HttpContext ctx, SupabaseGateway sb) =>
        sb.Select("challenges?select=*&order=created_at.desc&limit=50", Bearer(ctx)))
    .WithSummary("Lời mời và thách đấu của tôi (50 gần nhất)");

challenges.MapPost("/", (CreateChallengeRequest r, HttpContext ctx, SupabaseGateway sb) =>
        sb.Rpc("create_game_challenge", new { opponent_id = r.OpponentId, level = r.Difficulty, game_name = r.Game }, Bearer(ctx)))
    .WithSummary("Gửi lời mời thách đấu (hết hạn sau 24 giờ)");

challenges.MapPost("/{id:guid}/accept", (Guid id, HttpContext ctx, SupabaseGateway sb) =>
        sb.Rpc("respond_challenge", new { challenge_id = id, accept_invite = true }, Bearer(ctx)))
    .WithSummary("Chấp nhận lời mời");

challenges.MapPost("/{id:guid}/decline", (Guid id, HttpContext ctx, SupabaseGateway sb) =>
        sb.Rpc("respond_challenge", new { challenge_id = id, accept_invite = false }, Bearer(ctx)))
    .WithSummary("Từ chối lời mời");

challenges.MapPost("/{id:guid}/cancel", (Guid id, HttpContext ctx, SupabaseGateway sb) =>
        sb.Rpc("cancel_challenge", new { challenge_id = id }, Bearer(ctx)))
    .WithSummary("Người gửi hủy lời mời đang chờ");

challenges.MapPost("/{id:guid}/resign", (Guid id, HttpContext ctx, SupabaseGateway sb) =>
        sb.Rpc("resign_challenge", new { challenge_id = id }, Bearer(ctx)))
    .WithSummary("Đầu hàng: đối thủ được tính thắng");

challenges.MapPost("/{id:guid}/check-timeout", (Guid id, HttpContext ctx, SupabaseGateway sb) =>
        sb.Rpc("check_challenge_timeout", new { challenge_id = id }, Bearer(ctx)))
    .WithSummary("Chốt kết quả nếu đã quá hạn (lời mời, hạn thi đấu, 60 giây mỗi lượt Caro)");

challenges.MapPost("/{id:guid}/sudoku/start", (Guid id, HttpContext ctx, SupabaseGateway sb) =>
        sb.Rpc("start_challenge", new { challenge_id = id }, Bearer(ctx)))
    .WithSummary("Bắt đầu thách đấu Sudoku: nhận đề, máy chủ bắt đầu bấm giờ");

challenges.MapPost("/{id:guid}/sudoku/submit", (Guid id, SudokuSubmitRequest r, HttpContext ctx, SupabaseGateway sb) =>
        sb.Rpc("submit_challenge", new { challenge_id = id, answer = r.Answer, error_count = r.Mistakes }, Bearer(ctx)))
    .WithSummary("Nộp bài Sudoku; máy chủ kiểm tra đáp án, tính điểm và xác định người thắng");

challenges.MapGet("/{id:guid}/runs", (Guid id, HttpContext ctx, SupabaseGateway sb) =>
        sb.Select($"challenge_runs?select=*&challenge_id=eq.{id}", Bearer(ctx)))
    .WithSummary("Kết quả của hai người trong thách đấu Sudoku");

// ---------- Caro online ----------
var caro = app.MapGroup("/api/caro").WithTags("Caro online");

caro.MapPost("/{id:guid}/start", (Guid id, HttpContext ctx, SupabaseGateway sb) =>
        sb.Rpc("start_caro_challenge", new { challenge_id = id }, Bearer(ctx)))
    .WithSummary("Vào trận Caro; đồng hồ 60 giây mỗi lượt chạy khi cả hai đã vào");

caro.MapGet("/{id:guid}", (Guid id, HttpContext ctx, SupabaseGateway sb) =>
        sb.Select($"caro_matches?select=*&challenge_id=eq.{id}", Bearer(ctx)))
    .WithSummary("Bàn cờ hiện tại (225 ô: 0 trống, 1 = X, 2 = O), lượt đi, người thắng");

caro.MapPost("/{id:guid}/moves", (Guid id, CaroMoveRequest r, HttpContext ctx, SupabaseGateway sb) =>
        r.Row is < 0 or > 14 || r.Col is < 0 or > 14
            ? Task.FromResult(Results.Problem(title: "Ô cờ không hợp lệ", detail: "Hàng và cột phải từ 0 đến 14.", statusCode: 400))
            : sb.Rpc("play_caro_move", new { challenge_id = id, cell_index = r.Row * 15 + r.Col }, Bearer(ctx)))
    .WithSummary("Đi một nước; máy chủ kiểm tra lượt, ô trống, thắng theo luật chặn hai đầu");

// ---------- Messages ----------
var messages = app.MapGroup("/api/messages").WithTags("Messages");

messages.MapGet("/{userId:guid}", (Guid userId, int? limit, HttpContext ctx, SupabaseGateway sb) =>
        Bearer(ctx) is { } t
            ? sb.Select(
                $"messages?select=*&or=(sender_id.eq.{userId},recipient_id.eq.{userId})" +
                $"&order=created_at.desc&limit={Math.Clamp(limit ?? 50, 1, 100)}", t)
            : Task.FromResult(NeedLogin()))
    .WithSummary("Tin nhắn giữa tôi và một người chơi (mới nhất trước)");

messages.MapPost("/", (SendMessageRequest r, HttpContext ctx, SupabaseGateway sb) =>
    {
        var token = Bearer(ctx);
        if (SupabaseGateway.UserIdOf(token) is not { } me) return Task.FromResult(NeedLogin());
        var body = r.Body.Trim();
        if (body.Length == 0 || body.EnumerateRunes().Count() > 2000)
        {
            return Task.FromResult(Results.Problem(title: "Nội dung không hợp lệ", detail: "Tin nhắn phải có 1–2000 ký tự.", statusCode: 400));
        }
        return sb.Insert("messages", new { id = Guid.NewGuid(), sender_id = me, recipient_id = r.RecipientId, body }, token);
    })
    .WithSummary("Gửi tin nhắn (người nhận thấy ngay qua Realtime trong app)");

app.Run();
