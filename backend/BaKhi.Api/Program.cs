using System.Threading.RateLimiting;
using BaKhi.Api;
using Microsoft.AspNetCore.HttpOverrides;
using Microsoft.OpenApi;
using Npgsql;

var builder = WebApplication.CreateBuilder(args);

var connectionString = builder.Configuration.GetConnectionString("Default")
    ?? throw new InvalidOperationException("Missing ConnectionStrings:Default (env ConnectionStrings__Default)");
builder.Services.AddSingleton(NpgsqlDataSource.Create(connectionString));
builder.Services.AddSingleton<Db>();
builder.Services.AddSingleton<EmailSender>();
builder.Services.AddSingleton<AuthService>();
builder.Services.AddSingleton<RealtimeHub>();
builder.Services.AddHostedService<ChangeListener>();

builder.Services.AddAuthentication().AddJwtBearer(o =>
{
    // Keep "sub" as "sub" instead of the long .NET claim type name.
    o.MapInboundClaims = false;
    o.TokenValidationParameters = RealtimeHub.Validation(builder.Configuration);
});
builder.Services.AddAuthorization();

// Caddy on the VPS terminates HTTPS and passes the client address along.
builder.Services.Configure<ForwardedHeadersOptions>(o =>
{
    o.ForwardedHeaders = ForwardedHeaders.XForwardedFor | ForwardedHeaders.XForwardedProto;
    o.KnownIPNetworks.Clear();
    o.KnownProxies.Clear();
});
// Slows down password guessing and code spamming. Per client address, and a
// whole class on one school Wi-Fi shares an address, so not too strict.
var authPerMinute = builder.Configuration.GetValue("RateLimit:AuthPerMinute", 60);
builder.Services.AddRateLimiter(o =>
{
    o.AddPolicy("auth", ctx => RateLimitPartition.GetFixedWindowLimiter(
        ctx.Connection.RemoteIpAddress?.ToString() ?? "unknown",
        _ => new FixedWindowRateLimiterOptions { PermitLimit = authPerMinute, Window = TimeSpan.FromMinutes(1) }));
    o.OnRejected = (ctx, _) =>
    {
        ctx.HttpContext.Response.StatusCode = StatusCodes.Status429TooManyRequests;
        return new ValueTask(ctx.HttpContext.Response.WriteAsJsonAsync(
            new ApiError("over_request_rate_limit", "Bạn thao tác quá nhanh. Hãy thử lại sau.")));
    };
});

builder.Services.AddCors(o => o.AddDefaultPolicy(p => p.AllowAnyOrigin().AllowAnyHeader().AllowAnyMethod()));
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen(c =>
{
    c.SwaggerDoc("v1", new OpenApiInfo
    {
        Title = "Bá Khí Game Hub - API",
        Version = "v1",
        Description =
            "Backend của đồ án Bá Khí Game Hub (Sudoku, Xếp hình, Caro, Rubik): ASP.NET Core + PostgreSQL, " +
            "tự triển khai trên VPS.\n\n" +
            "- **Tài khoản:** đăng ký, xác nhận bằng mã gửi qua email, đăng nhập trả về JWT.\n" +
            "- **Luật chơi và chống gian lận:** hàm SQL trong PostgreSQL; mỗi yêu cầu chạy với quyền của người gọi " +
            "(Row Level Security).\n" +
            "- **Realtime:** WebSocket `/ws` đẩy tin nhắn, lời mời và nước đi Caro tới hai người chơi.\n\n" +
            "**Cách thử:** `POST /api/auth/register` → nhập mã trong email ở `POST /api/auth/verify-otp` " +
            "(hoặc `POST /api/auth/login`) → sao chép `access_token` → bấm **Authorize** và dán vào.",
    });
    c.AddSecurityDefinition("Bearer", new OpenApiSecurityScheme
    {
        Type = SecuritySchemeType.Http,
        Scheme = "bearer",
        BearerFormat = "JWT",
        Description = "access_token nhận được từ /api/auth/login hoặc /api/auth/verify-otp",
    });
    c.AddSecurityRequirement(document => new OpenApiSecurityRequirement
    {
        [new OpenApiSecuritySchemeReference("Bearer", document)] = [],
    });
});

var app = builder.Build();

await MigrateWithRetry(app);

app.UseForwardedHeaders();
app.UseCors();
app.UseRateLimiter();
app.UseAuthentication();
app.UseAuthorization();
app.UseWebSockets(new WebSocketOptions { KeepAliveInterval = TimeSpan.FromSeconds(30) });
app.UseSwagger();
app.UseSwaggerUI(ui =>
{
    ui.SwaggerEndpoint("/swagger/v1/swagger.json", "BaKhi_API v1");
    ui.DocumentTitle = "Bá Khí Game Hub API";
});
app.MapGet("/", () => Results.Redirect("/swagger")).ExcludeFromDescription();
app.Map("/ws", (HttpContext ctx, RealtimeHub hub) => hub.Serve(ctx)).ExcludeFromDescription();

// ---------- Health ----------
app.MapGet("/api/health", async (NpgsqlDataSource source) =>
    {
        await using var cmd = source.CreateCommand("select now()");
        return Results.Ok(new { status = "ok", database = await cmd.ExecuteScalarAsync() });
    })
    .WithTags("Health").WithSummary("Kiểm tra API và cơ sở dữ liệu đang chạy");

// ---------- Auth ----------
var auth = app.MapGroup("/api/auth").WithTags("Auth").RequireRateLimiting("auth");

auth.MapPost("/register", (RegisterRequest r, AuthService s) => s.Register(r))
    .WithSummary("Đăng ký tài khoản; mã xác nhận 6 số được gửi qua email");
auth.MapPost("/verify-otp", (VerifyOtpRequest r, AuthService s) => s.VerifyCode(r))
    .WithSummary("Xác nhận mã từ email (type: signup hoặc recovery); trả về access_token");
auth.MapPost("/resend-otp", (EmailRequest r, AuthService s) => s.ResendSignupCode(r.Email))
    .WithSummary("Gửi lại mã xác nhận đăng ký (tối đa 1 lần mỗi phút)");
auth.MapPost("/login", (LoginRequest r, AuthService s) => s.Login(r))
    .WithSummary("Đăng nhập; trả về access_token (JWT, 1 giờ) và refresh_token (30 ngày)");
auth.MapPost("/refresh", (RefreshRequest r, AuthService s) => s.Refresh(r.RefreshToken))
    .WithSummary("Đổi refresh_token lấy phiên mới (mỗi refresh_token dùng được một lần)");
auth.MapPost("/logout", (RefreshRequest r, AuthService s) => s.Logout(r.RefreshToken))
    .WithSummary("Đăng xuất: hủy refresh_token");
auth.MapPost("/forgot-password", (EmailRequest r, AuthService s) => s.ForgotPassword(r.Email))
    .WithSummary("Gửi mã đặt lại mật khẩu qua email (rồi gọi /verify-otp với type = recovery)");
auth.MapGet("/me", (HttpContext ctx, AuthService s) => s.Me(ctx.User))
    .RequireAuthorization().WithSummary("Thông tin tài khoản đang đăng nhập");
auth.MapPut("/password", (NewPasswordRequest r, HttpContext ctx, AuthService s) => s.ChangePassword(ctx.User, r.Password))
    .RequireAuthorization().WithSummary("Đặt mật khẩu mới (sau khi xác nhận mã quên mật khẩu)");

// Everything below runs as the signed-in player.
var api = app.MapGroup("/api").RequireAuthorization();

// ---------- Players ----------
var players = api.MapGroup("/players").WithTags("Players");

players.MapGet("/", (HttpContext ctx, Db db) => db.Json(ctx.User, """
        select coalesce(jsonb_agg(t order by t.display_name), '[]')::text from (
          select id, display_name from public.profiles where id <> auth.uid() order by display_name limit 100) t
        """))
    .WithSummary("Danh sách người chơi khác (tối đa 100)");
players.MapGet("/{id:guid}", (Guid id, HttpContext ctx, Db db) => db.Json(ctx.User,
        "select to_jsonb(t)::text from (select id, display_name from public.profiles where id = $1) t", id))
    .WithSummary("Tên hiển thị của một người chơi");

// ---------- Games & scoring ----------
var games = api.MapGroup("/games").WithTags("Games");

games.MapPost("/sessions", (StartGameRequest r, HttpContext ctx, Db db) => db.Json(ctx.User,
        "select public.start_game_session($1, $2)::text", r.Game, r.Difficulty))
    .WithSummary("Bắt đầu một ván: máy chủ ghi giờ bắt đầu để chống gian lận");
games.MapPost("/results", (SubmitResultRequest r, HttpContext ctx, Db db) => db.Json(ctx.User,
        "select public.submit_game_result($1, $2, $3, $4, $5, $6, $7, $8, $9)::text",
        r.ResultId ?? Guid.NewGuid(), new NpgsqlParameter { Value = (object?)r.SessionId ?? DBNull.Value, NpgsqlDbType = NpgsqlTypes.NpgsqlDbType.Uuid },
        r.Game, r.Difficulty, r.Seconds, r.Mistakes, r.Moves, r.Outcome, (r.PlayedAt ?? DateTimeOffset.UtcNow).ToUniversalTime()))
    .WithSummary("Nộp kết quả ván; máy chủ tính điểm và quyết định có xếp hạng hay không (gửi lại cùng resultId không tạo bản ghi trùng)");
games.MapGet("/score", (string game, string difficulty, int seconds, int mistakes, string? outcome, HttpContext ctx, Db db) =>
        db.Json(ctx.User, "select to_jsonb(public.game_score($1, $2, $3, $4, $5))::text",
            game, difficulty, seconds, mistakes, outcome ?? "win"))
    .WithSummary("Tính thử điểm: gốc × hệ số × T / (T + giây), mỗi lỗi −5%");

// ---------- Leaderboard ----------
var board = api.MapGroup("/leaderboard").WithTags("Leaderboard");

board.MapGet("/", (string game, string difficulty, HttpContext ctx, Db db) => db.Json(ctx.User, """
        select coalesce(jsonb_agg(t order by t.score desc, t.seconds, t.mistakes, t.achieved_at), '[]')::text from (
          select * from public.leaderboard where game = $1 and difficulty = $2
          order by score desc, seconds, mistakes, achieved_at limit 50) t
        """, game, difficulty))
    .WithSummary("Top 50 theo game và độ khó (game: sudoku | puzzle | caro; difficulty: easy | medium | hard)");
board.MapGet("/me", (string game, string difficulty, HttpContext ctx, Db db) => db.Json(ctx.User,
        "select public.my_leaderboard_rank($1, $2)::text", game, difficulty))
    .WithSummary("Hạng và kết quả tốt nhất của người đang đăng nhập (null nếu chưa có)");

// ---------- Challenges ----------
var challenges = api.MapGroup("/challenges").WithTags("Challenges");

challenges.MapGet("/", (HttpContext ctx, Db db) => db.Json(ctx.User, """
        select coalesce(jsonb_agg(t order by t.created_at desc), '[]')::text from (
          select * from public.challenges order by created_at desc limit 50) t
        """))
    .WithSummary("Lời mời và thách đấu của tôi (50 gần nhất)");
challenges.MapPost("/", (CreateChallengeRequest r, HttpContext ctx, Db db) => db.Json(ctx.User,
        "select to_jsonb(public.create_game_challenge($1, $2, $3))::text", r.OpponentId, r.Difficulty, r.Game))
    .WithSummary("Gửi lời mời thách đấu (hết hạn sau 24 giờ); trả về id thách đấu");
challenges.MapPost("/{id:guid}/accept", (Guid id, HttpContext ctx, Db db) =>
        db.Exec(ctx.User, "select public.respond_challenge($1, true)::text", id))
    .WithSummary("Chấp nhận lời mời");
challenges.MapPost("/{id:guid}/decline", (Guid id, HttpContext ctx, Db db) =>
        db.Exec(ctx.User, "select public.respond_challenge($1, false)::text", id))
    .WithSummary("Từ chối lời mời");
challenges.MapPost("/{id:guid}/cancel", (Guid id, HttpContext ctx, Db db) =>
        db.Exec(ctx.User, "select public.cancel_challenge($1)::text", id))
    .WithSummary("Người gửi hủy lời mời đang chờ");
challenges.MapPost("/{id:guid}/resign", (Guid id, HttpContext ctx, Db db) =>
        db.Exec(ctx.User, "select public.resign_challenge($1)::text", id))
    .WithSummary("Đầu hàng: đối thủ được tính thắng");
challenges.MapPost("/{id:guid}/check-timeout", (Guid id, HttpContext ctx, Db db) =>
        db.Json(ctx.User, "select to_jsonb(public.check_challenge_timeout($1))::text", id))
    .WithSummary("Chốt kết quả nếu đã quá hạn (lời mời, hạn thi đấu, 60 giây mỗi lượt Caro); true nếu có thay đổi");
challenges.MapPost("/{id:guid}/sudoku/start", (Guid id, HttpContext ctx, Db db) =>
        db.Json(ctx.User, "select public.start_challenge($1)::text", id))
    .WithSummary("Bắt đầu thách đấu Sudoku: nhận đề, máy chủ bắt đầu bấm giờ");
challenges.MapPost("/{id:guid}/sudoku/submit", (Guid id, SudokuSubmitRequest r, HttpContext ctx, Db db) =>
        db.Json(ctx.User, "select public.submit_challenge($1, $2, $3)::text", id, r.Answer, r.Mistakes))
    .WithSummary("Nộp bài Sudoku; máy chủ kiểm tra đáp án, tính điểm và xác định người thắng");
challenges.MapGet("/{id:guid}/runs", (Guid id, HttpContext ctx, Db db) => db.Json(ctx.User,
        "select coalesce(jsonb_agg(t), '[]')::text from (select * from public.challenge_runs where challenge_id = $1) t", id))
    .WithSummary("Kết quả của hai người trong thách đấu Sudoku");

// ---------- Caro online ----------
var caro = api.MapGroup("/caro").WithTags("Caro online");

caro.MapPost("/{id:guid}/start", (Guid id, HttpContext ctx, Db db) =>
        db.Json(ctx.User, "select public.start_caro_challenge($1)::text", id))
    .WithSummary("Vào trận Caro; đồng hồ 60 giây mỗi lượt chạy khi cả hai đã vào");
caro.MapGet("/{id:guid}", (Guid id, HttpContext ctx, Db db) => db.Json(ctx.User,
        "select coalesce(jsonb_agg(t), '[]')::text from (select * from public.caro_matches where challenge_id = $1) t", id))
    .WithSummary("Bàn cờ hiện tại (225 ô: 0 trống, 1 = X, 2 = O), lượt đi, người thắng");
caro.MapPost("/{id:guid}/moves", (Guid id, CaroMoveRequest r, HttpContext ctx, Db db) =>
        r.Row is < 0 or > 14 || r.Col is < 0 or > 14
            ? Task.FromResult(Db.Error(400, "invalid", "Hàng và cột phải từ 0 đến 14."))
            : db.Exec(ctx.User, "select public.play_caro_move($1, $2)::text", id, r.Row * 15 + r.Col))
    .WithSummary("Đi một nước; máy chủ kiểm tra lượt, ô trống, thắng theo luật chặn hai đầu");

// ---------- Messages ----------
var messages = api.MapGroup("/messages").WithTags("Messages");

messages.MapGet("/{userId:guid}", (Guid userId, int? limit, HttpContext ctx, Db db) => db.Json(ctx.User, """
        select coalesce(jsonb_agg(t order by t.created_at desc), '[]')::text from (
          select * from public.messages
          where room_key = least(auth.uid()::text, $1::text) || ':' || greatest(auth.uid()::text, $1::text)
          order by created_at desc limit $2) t
        """, userId, Math.Clamp(limit ?? 100, 1, 100)))
    .WithSummary("Tin nhắn giữa tôi và một người chơi (mới nhất trước)");
messages.MapPost("/", (SendMessageRequest r, HttpContext ctx, Db db) =>
    {
        var body = r.Body.Trim();
        if (body.Length == 0 || body.EnumerateRunes().Count() > 2000)
        {
            return Task.FromResult(Db.Error(400, "invalid", "Tin nhắn phải có 1–2000 ký tự."));
        }
        // The app sends its own id, so a retried send is stored only once.
        return db.Json(ctx.User, """
            with saved as (
              insert into public.messages(id, sender_id, recipient_id, body) values ($1, auth.uid(), $2, $3)
              on conflict (id) do nothing returning *)
            select to_jsonb(s)::text from saved s
            """, r.Id ?? Guid.NewGuid(), r.RecipientId, body);
    })
    .WithSummary("Gửi tin nhắn; người nhận thấy ngay qua WebSocket /ws");

app.Run();

static async Task MigrateWithRetry(WebApplication app)
{
    var source = app.Services.GetRequiredService<NpgsqlDataSource>();
    for (var attempt = 1; ; attempt++)
    {
        try
        {
            await Migrator.RunAsync(source, app.Logger);
            return;
        }
        // The database container may still be starting.
        catch (NpgsqlException e) when (attempt < 30 && e is not PostgresException)
        {
            app.Logger.LogWarning("Database not ready ({Message}); retrying", e.Message);
            await Task.Delay(TimeSpan.FromSeconds(2));
        }
    }
}
