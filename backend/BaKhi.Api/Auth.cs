using System.Security.Claims;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using MailKit.Net.Smtp;
using MailKit.Security;
using Microsoft.IdentityModel.JsonWebTokens;
using Microsoft.IdentityModel.Tokens;
using MimeKit;
using Npgsql;

namespace BaKhi.Api;

/// <summary>Settings for signing access tokens (section "Jwt").</summary>
public sealed class JwtSettings
{
    public const string Issuer = "bakhi-api";
    public const string Audience = "bakhi-app";
    public static readonly TimeSpan AccessLifetime = TimeSpan.FromHours(1);
    public static readonly TimeSpan RefreshLifetime = TimeSpan.FromDays(30);

    public static SymmetricSecurityKey Key(IConfiguration config)
    {
        var secret = config["Jwt:Secret"];
        if (string.IsNullOrEmpty(secret) || secret.Length < 32)
        {
            throw new InvalidOperationException("Jwt:Secret (env Jwt__Secret) must be at least 32 characters.");
        }
        return new SymmetricSecurityKey(Encoding.UTF8.GetBytes(secret));
    }
}

/// <summary>
/// Accounts: sign-up confirmed by a 6-digit code sent by email, sign-in with
/// a BCrypt-checked password, a 1-hour JWT access token plus a 30-day refresh
/// token, and password reset by emailed code.
/// </summary>
public sealed partial class AuthService(NpgsqlDataSource db, IConfiguration config, EmailSender email)
{
    static readonly TimeSpan CodeLifetime = TimeSpan.FromMinutes(15);
    static readonly TimeSpan CodeCooldown = TimeSpan.FromSeconds(60);
    const int MaxCodeAttempts = 5;
    // Compared against when the address is unknown, so both cases take as long.
    static readonly string MissingUserHash = BCrypt.Net.BCrypt.HashPassword("no such user");

    [GeneratedRegex(@"^[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}$")]
    private static partial Regex EmailPattern();

    static string NormalizeEmail(string value) => value.Trim().ToLowerInvariant();

    static IResult? CheckPassword(string password) =>
        password.Length < 8 || !password.Any(char.IsLetter) || !password.Any(char.IsDigit)
            ? Db.Error(400, "weak_password", "Mật khẩu cần ít nhất 8 ký tự, gồm cả chữ và số.")
            : null;

    public async Task<IResult> Register(RegisterRequest r)
    {
        var address = NormalizeEmail(r.Email);
        var name = r.DisplayName.Trim();
        if (!EmailPattern().IsMatch(address)) return Db.Error(400, "email_address_invalid", "Email chưa hợp lệ.");
        if (name.Length is < 2 or > 40) return Db.Error(400, "validation_failed", "Tên hiển thị cần 2–40 ký tự.");
        if (CheckPassword(r.Password) is { } weak) return weak;

        var hash = BCrypt.Net.BCrypt.HashPassword(r.Password);
        var meta = $$"""{"display_name":{{System.Text.Json.JsonSerializer.Serialize(name)}}}""";
        await using var cmd = db.CreateCommand("""
            insert into auth.users(email, password_hash, raw_user_meta_data) values ($1, $2, $3::jsonb)
            on conflict (email) do update
              set password_hash = excluded.password_hash, raw_user_meta_data = excluded.raw_user_meta_data, updated_at = now()
              where auth.users.email_confirmed_at is null
            returning id
            """);
        cmd.Parameters.AddWithValue(address);
        cmd.Parameters.AddWithValue(hash);
        cmd.Parameters.AddWithValue(meta);
        // No row back: the address already belongs to a confirmed account.
        if (await cmd.ExecuteScalarAsync() is null)
        {
            return Db.Error(409, "user_already_exists", "Email này đã được sử dụng.");
        }
        return await SendCode(address, "signup") ?? Results.Ok(new { confirmation_sent = true });
    }

    public async Task<IResult> ResendSignupCode(string emailAddress)
    {
        var address = NormalizeEmail(emailAddress);
        var user = await FindUser(address);
        // Same answer whether or not the address is registered.
        if (user is { Confirmed: false } && await SendCode(address, "signup") is { } problem) return problem;
        return Results.Ok(new { sent = true });
    }

    public async Task<IResult> ForgotPassword(string emailAddress)
    {
        var address = NormalizeEmail(emailAddress);
        var user = await FindUser(address);
        if (user is { Confirmed: true } && await SendCode(address, "recovery") is { } problem) return problem;
        return Results.Ok(new { sent = true });
    }

    public async Task<IResult> VerifyCode(VerifyOtpRequest r)
    {
        var address = NormalizeEmail(r.Email);
        var purpose = r.Type == "recovery" ? "recovery" : "signup";
        var expired = Db.Error(400, "otp_expired", "Mã đã hết hạn hoặc không đúng.");

        await using var conn = await db.OpenConnectionAsync();
        await using var tx = await conn.BeginTransactionAsync();
        string? stored;
        await using (var read = new NpgsqlCommand("""
            select code_hash from auth.email_codes
            where email = $1 and purpose = $2 and expires_at > now() and attempts < $3
            for update
            """, conn, tx))
        {
            read.Parameters.AddWithValue(address);
            read.Parameters.AddWithValue(purpose);
            read.Parameters.AddWithValue(MaxCodeAttempts);
            stored = await read.ExecuteScalarAsync() as string;
        }
        if (stored is null) return expired;
        if (!CryptographicOperations.FixedTimeEquals(
                Encoding.ASCII.GetBytes(stored), Encoding.ASCII.GetBytes(HashCode(address, r.Code.Trim()))))
        {
            await using var miss = new NpgsqlCommand(
                "update auth.email_codes set attempts = attempts + 1 where email = $1 and purpose = $2", conn, tx);
            miss.Parameters.AddWithValue(address);
            miss.Parameters.AddWithValue(purpose);
            await miss.ExecuteNonQueryAsync();
            await tx.CommitAsync();
            return expired;
        }
        await using (var used = new NpgsqlCommand(
            "delete from auth.email_codes where email = $1 and purpose = $2", conn, tx))
        {
            used.Parameters.AddWithValue(address);
            used.Parameters.AddWithValue(purpose);
            await used.ExecuteNonQueryAsync();
        }
        if (purpose == "signup")
        {
            // Confirming creates the player's profile (trigger in 011).
            await using var confirm = new NpgsqlCommand(
                "update auth.users set email_confirmed_at = now() where email = $1 and email_confirmed_at is null", conn, tx);
            confirm.Parameters.AddWithValue(address);
            await confirm.ExecuteNonQueryAsync();
        }
        await tx.CommitAsync();

        var user = await FindUser(address);
        return user is null ? expired : Results.Ok(await Issue(user));
    }

    public async Task<IResult> Login(LoginRequest r)
    {
        var user = await FindUser(NormalizeEmail(r.Email));
        if (!BCrypt.Net.BCrypt.Verify(r.Password, user?.PasswordHash ?? MissingUserHash) || user is null)
        {
            return Db.Error(400, "invalid_credentials", "Email hoặc mật khẩu chưa đúng.");
        }
        if (!user.Confirmed) return Db.Error(400, "email_not_confirmed", "Hãy xác nhận email trước khi đăng nhập.");
        return Results.Ok(await Issue(user));
    }

    public async Task<IResult> Refresh(string refreshToken)
    {
        // Each refresh token works once; a new one comes with the new session.
        await using var cmd = db.CreateCommand(
            "delete from auth.refresh_tokens where token_hash = $1 and expires_at > now() returning user_id");
        cmd.Parameters.AddWithValue(Sha256(refreshToken));
        if (await cmd.ExecuteScalarAsync() is not Guid id || await FindUser(id) is not { } user)
        {
            return Db.Error(401, "refresh_token_not_found", "Phiên đăng nhập đã hết hạn. Hãy đăng nhập lại.");
        }
        return Results.Ok(await Issue(user));
    }

    public async Task<IResult> Logout(string refreshToken)
    {
        await using var cmd = db.CreateCommand("delete from auth.refresh_tokens where token_hash = $1");
        cmd.Parameters.AddWithValue(Sha256(refreshToken));
        await cmd.ExecuteNonQueryAsync();
        return Results.NoContent();
    }

    public async Task<IResult> Me(ClaimsPrincipal principal) =>
        Db.UserId(principal) is { } id && await FindUser(id) is { } user
            ? Results.Ok(user.Public)
            : Results.Unauthorized();

    public async Task<IResult> ChangePassword(ClaimsPrincipal principal, string password)
    {
        if (Db.UserId(principal) is not { } id || await FindUser(id) is not { } user) return Results.Unauthorized();
        if (CheckPassword(password) is { } weak) return weak;
        if (BCrypt.Net.BCrypt.Verify(password, user.PasswordHash))
        {
            return Db.Error(400, "same_password", "Mật khẩu mới phải khác mật khẩu cũ.");
        }
        await using var cmd = db.CreateCommand(
            "update auth.users set password_hash = $2, updated_at = now() where id = $1");
        cmd.Parameters.AddWithValue(id);
        cmd.Parameters.AddWithValue(BCrypt.Net.BCrypt.HashPassword(password));
        await cmd.ExecuteNonQueryAsync();
        return Results.NoContent();
    }

    /// <summary>Stores a new code (only its hash) and emails it; null when sent.</summary>
    async Task<IResult?> SendCode(string address, string purpose)
    {
        var code = RandomNumberGenerator.GetInt32(0, 1_000_000).ToString("D6");
        await using var cmd = db.CreateCommand("""
            insert into auth.email_codes(email, purpose, code_hash, expires_at) values ($1, $2, $3, now() + $4)
            on conflict (email, purpose) do update
              set code_hash = excluded.code_hash, attempts = 0, expires_at = excluded.expires_at, created_at = now()
              where auth.email_codes.created_at < now() - $5
            returning 1
            """);
        cmd.Parameters.AddWithValue(address);
        cmd.Parameters.AddWithValue(purpose);
        cmd.Parameters.AddWithValue(HashCode(address, code));
        cmd.Parameters.AddWithValue(CodeLifetime);
        cmd.Parameters.AddWithValue(CodeCooldown);
        if (await cmd.ExecuteScalarAsync() is null)
        {
            return Db.Error(429, "over_email_send_rate_limit", "Vừa gửi mã xong. Hãy chờ 1 phút rồi thử lại.");
        }
        try
        {
            await email.SendCode(address, code, purpose);
            return null;
        }
        catch (Exception)
        {
            // An unsent code must not hold the address in the 1-minute cooldown.
            await using var drop = db.CreateCommand("delete from auth.email_codes where email = $1 and purpose = $2");
            drop.Parameters.AddWithValue(address);
            drop.Parameters.AddWithValue(purpose);
            await drop.ExecuteNonQueryAsync();
            return Db.Error(502, "email_send_failed", "Chưa gửi được email. Hãy thử lại sau ít phút.");
        }
    }

    async Task<object> Issue(Account user)
    {
        var now = DateTime.UtcNow;
        var access = new JsonWebTokenHandler().CreateToken(new SecurityTokenDescriptor
        {
            Issuer = JwtSettings.Issuer,
            Audience = JwtSettings.Audience,
            IssuedAt = now,
            NotBefore = now,
            Expires = now + JwtSettings.AccessLifetime,
            Claims = new Dictionary<string, object>
            {
                ["sub"] = user.Id.ToString(),
                ["email"] = user.Email,
                ["name"] = user.DisplayName,
            },
            SigningCredentials = new SigningCredentials(JwtSettings.Key(config), SecurityAlgorithms.HmacSha256),
        });
        var refresh = Base64UrlEncoder.Encode(RandomNumberGenerator.GetBytes(32));
        await using var cmd = db.CreateCommand(
            "insert into auth.refresh_tokens(token_hash, user_id, expires_at) values ($1, $2, now() + $3)");
        cmd.Parameters.AddWithValue(Sha256(refresh));
        cmd.Parameters.AddWithValue(user.Id);
        cmd.Parameters.AddWithValue(JwtSettings.RefreshLifetime);
        await cmd.ExecuteNonQueryAsync();
        return new
        {
            access_token = access,
            token_type = "bearer",
            expires_in = (int)JwtSettings.AccessLifetime.TotalSeconds,
            refresh_token = refresh,
            user = user.Public,
        };
    }

    sealed record Account(Guid Id, string Email, string PasswordHash, string DisplayName, bool Confirmed)
    {
        public object Public => new { id = Id, email = Email, display_name = DisplayName };
    }

    const string AccountColumns = """
        select u.id, u.email, u.password_hash,
               coalesce(p.display_name, u.raw_user_meta_data->>'display_name', 'Người chơi'),
               u.email_confirmed_at is not null
        from auth.users u left join public.profiles p on p.id = u.id
        """;

    Task<Account?> FindUser(string address) => ReadAccount($"{AccountColumns} where u.email = $1", address);

    Task<Account?> FindUser(Guid id) => ReadAccount($"{AccountColumns} where u.id = $1", id);

    async Task<Account?> ReadAccount(string sql, object key)
    {
        await using var cmd = db.CreateCommand(sql);
        cmd.Parameters.AddWithValue(key);
        await using var row = await cmd.ExecuteReaderAsync();
        return await row.ReadAsync()
            ? new Account(row.GetGuid(0), row.GetString(1), row.GetString(2), row.GetString(3), row.GetBoolean(4))
            : null;
    }

    // Salted with the address, so equal codes for two players hash differently.
    static string HashCode(string address, string code) => Sha256($"{address}:{code}");

    static string Sha256(string value) => Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(value)));
}

/// <summary>
/// Sends the confirmation and reset codes through SMTP (section "Smtp", for
/// Gmail: smtp.gmail.com, port 587, the account and a Google app password).
/// Without SMTP settings, Development prints the code in the server log.
/// </summary>
public sealed class EmailSender(IConfiguration config, IHostEnvironment env, ILogger<EmailSender> log)
{
    public async Task SendCode(string to, string code, string purpose)
    {
        var host = config["Smtp:Host"];
        if (string.IsNullOrEmpty(host))
        {
            if (!env.IsDevelopment()) throw new InvalidOperationException("Smtp:Host is not configured.");
            log.LogWarning("No SMTP configured. {Purpose} code for {Email}: {Code}", purpose, to, code);
            return;
        }
        var user = config["Smtp:User"];
        var signup = purpose == "signup";
        var message = new MimeMessage
        {
            Subject = signup ? "Mã xác nhận tài khoản Bá Khí Game Hub" : "Mã đặt lại mật khẩu Bá Khí Game Hub",
            Body = new TextPart("plain")
            {
                Text = (signup
                        ? "Chào bạn,\n\nMã xác nhận tài khoản Bá Khí Game Hub của bạn là:\n\n"
                        : "Chào bạn,\n\nMã đặt lại mật khẩu Bá Khí Game Hub của bạn là:\n\n") +
                       $"    {code}\n\nMã có hiệu lực trong 15 phút. Nếu bạn không yêu cầu, hãy bỏ qua email này.",
            },
        };
        message.From.Add(new MailboxAddress(config["Smtp:FromName"] ?? "Bá Khí Game Hub", config["Smtp:From"] ?? user ?? ""));
        message.To.Add(MailboxAddress.Parse(to));

        using var smtp = new SmtpClient();
        await smtp.ConnectAsync(host, int.TryParse(config["Smtp:Port"], out var port) ? port : 587, SecureSocketOptions.Auto);
        if (!string.IsNullOrEmpty(user)) await smtp.AuthenticateAsync(user, config["Smtp:Password"] ?? "");
        await smtp.SendAsync(message);
        await smtp.DisconnectAsync(true);
    }
}
