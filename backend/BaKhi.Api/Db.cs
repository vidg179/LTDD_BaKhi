using System.Reflection;
using System.Security.Claims;
using Npgsql;

namespace BaKhi.Api;

/// <summary>
/// PostgreSQL access. Every player request runs in its own transaction as
/// role <c>authenticated</c> (or <c>anon</c> without a token) with the
/// player's id in <c>request.jwt.claim.sub</c>, so row level security and the
/// SQL game functions (migrations 001–011) decide what the player may see and
/// do. Queries return their result as JSON text built by PostgreSQL.
/// </summary>
public sealed class Db(NpgsqlDataSource source)
{
    public NpgsqlDataSource Source => source;

    /// <summary>The player id ("sub") of a validated access token.</summary>
    public static Guid? UserId(ClaimsPrincipal user) =>
        Guid.TryParse(user.FindFirstValue("sub"), out var id) ? id : null;

    /// <summary>
    /// Runs <paramref name="sql"/> as the player and answers with its single
    /// JSON value (or <c>null</c>). Errors raised by the game rules come back
    /// as 400 with their Vietnamese message.
    /// </summary>
    public async Task<IResult> Json(ClaimsPrincipal user, string sql, params object?[] args)
    {
        try
        {
            var json = await Scalar(UserId(user), sql, args);
            return Results.Content(json ?? "null", "application/json; charset=utf-8");
        }
        catch (PostgresException e)
        {
            return Problem(e);
        }
    }

    /// <summary>Same as <see cref="Json"/> for statements without a result.</summary>
    public async Task<IResult> Exec(ClaimsPrincipal user, string sql, params object?[] args)
    {
        try
        {
            await Scalar(UserId(user), sql, args);
            return Results.NoContent();
        }
        catch (PostgresException e)
        {
            return Problem(e);
        }
    }

    public async Task<string?> Scalar(Guid? userId, string sql, params object?[] args)
    {
        await using var conn = await source.OpenConnectionAsync();
        await using var tx = await conn.BeginTransactionAsync();
        // set_config(..., true) is "set local": it ends with the transaction.
        await using (var who = new NpgsqlCommand(
            "select set_config('role', $1, true), set_config('request.jwt.claim.sub', $2, true)", conn, tx))
        {
            who.Parameters.AddWithValue(userId is null ? "anon" : "authenticated");
            who.Parameters.AddWithValue(userId?.ToString() ?? "");
            await who.ExecuteNonQueryAsync();
        }
        string? result;
        await using (var cmd = new NpgsqlCommand(sql, conn, tx))
        {
            foreach (var arg in args) cmd.Parameters.Add(arg is NpgsqlParameter p ? p : new NpgsqlParameter { Value = arg ?? DBNull.Value });
            result = await cmd.ExecuteScalarAsync() is string s ? s : null;
        }
        await tx.CommitAsync();
        return result;
    }

    public static IResult Error(int status, string code, string message) =>
        Results.Json(new ApiError(code, message), statusCode: status);

    static IResult Problem(PostgresException e) => e.SqlState switch
    {
        // raise exception '...' in the game functions: a rule was broken.
        "P0001" => Error(400, "rule", e.MessageText),
        PostgresErrorCodes.InsufficientPrivilege => Error(403, "forbidden", "Bạn không có quyền thực hiện thao tác này."),
        PostgresErrorCodes.ForeignKeyViolation => Error(400, "not_found", "Người chơi hoặc trận đấu không tồn tại."),
        PostgresErrorCodes.CheckViolation or PostgresErrorCodes.InvalidTextRepresentation
            or PostgresErrorCodes.NotNullViolation or PostgresErrorCodes.InvalidParameterValue
            => Error(400, "invalid", "Dữ liệu gửi lên không hợp lệ."),
        _ => throw e,
    };
}

public record ApiError(string Code, string Message);

/// <summary>
/// Applies the SQL files in database/migrations (embedded in the build) that
/// the database has not seen yet, in name order, once each.
/// </summary>
public static class Migrator
{
    public static async Task RunAsync(NpgsqlDataSource source, ILogger logger)
    {
        await using var conn = await source.OpenConnectionAsync();
        await using (var init = new NpgsqlCommand(
            "create table if not exists public.schema_migrations(name text primary key, applied_at timestamptz not null default now())",
            conn))
        {
            await init.ExecuteNonQueryAsync();
        }
        var applied = new HashSet<string>();
        await using (var read = new NpgsqlCommand("select name from public.schema_migrations", conn))
        await using (var rows = await read.ExecuteReaderAsync())
        {
            while (await rows.ReadAsync()) applied.Add(rows.GetString(0));
        }

        var assembly = Assembly.GetExecutingAssembly();
        const string prefix = "migrations/";
        foreach (var resource in assembly.GetManifestResourceNames()
                     .Where(n => n.StartsWith(prefix) && n.EndsWith(".sql")).Order())
        {
            var name = resource[prefix.Length..];
            if (applied.Contains(name)) continue;
            await using var stream = assembly.GetManifestResourceStream(resource)!;
            var sql = await new StreamReader(stream).ReadToEndAsync();
            // Each file has its own begin/commit.
            await using (var run = new NpgsqlCommand(sql, conn)) await run.ExecuteNonQueryAsync();
            await using var mark = new NpgsqlCommand("insert into public.schema_migrations(name) values ($1)", conn);
            mark.Parameters.AddWithValue(name);
            await mark.ExecuteNonQueryAsync();
            logger.LogInformation("Applied migration {Name}", name);
        }
    }
}
