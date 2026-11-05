using System.Collections.Concurrent;
using System.Net.WebSockets;
using System.Text;
using System.Text.Json;
using System.Threading.Channels;
using Microsoft.IdentityModel.JsonWebTokens;
using Microsoft.IdentityModel.Tokens;
using Npgsql;

namespace BaKhi.Api;

/// <summary>
/// Open WebSocket connections by player. The app connects to /ws, sends
/// {"access_token": "..."} as its first message and then receives
/// {"type":"change","table":...,"op":...,"row":{...}} for every chat message,
/// challenge and Caro board that involves the player.
/// </summary>
public sealed class RealtimeHub(IConfiguration config, ILogger<RealtimeHub> log)
{
    sealed class Connection(WebSocket socket)
    {
        public WebSocket Socket { get; } = socket;
        // WebSocket allows one send at a time.
        public SemaphoreSlim Gate { get; } = new(1, 1);
    }

    readonly ConcurrentDictionary<Guid, ConcurrentDictionary<Connection, byte>> players = new();

    public async Task Serve(HttpContext ctx)
    {
        if (!ctx.WebSockets.IsWebSocketRequest)
        {
            ctx.Response.StatusCode = StatusCodes.Status400BadRequest;
            return;
        }
        using var socket = await ctx.WebSockets.AcceptWebSocketAsync();
        var userId = await Authenticate(socket, ctx.RequestAborted);
        if (userId is null)
        {
            await socket.CloseAsync((WebSocketCloseStatus)4001, "unauthorized", CancellationToken.None);
            return;
        }
        var connection = new Connection(socket);
        players.GetOrAdd(userId.Value, _ => new()).TryAdd(connection, 0);
        try
        {
            await SendTo(connection, """{"type":"ready"}""");
            var buffer = new byte[1024];
            // Incoming frames are only keep-alive pings; read until the app leaves.
            while (socket.State == WebSocketState.Open)
            {
                var frame = await socket.ReceiveAsync(buffer, ctx.RequestAborted);
                if (frame.MessageType == WebSocketMessageType.Close) break;
            }
        }
        catch (Exception e) when (e is WebSocketException or OperationCanceledException)
        {
            // The app went away without a close frame.
        }
        finally
        {
            if (players.TryGetValue(userId.Value, out var mine)) mine.TryRemove(connection, out _);
            if (socket.State is WebSocketState.Open or WebSocketState.CloseReceived)
            {
                await socket.CloseOutputAsync(WebSocketCloseStatus.NormalClosure, null, CancellationToken.None);
            }
        }
    }

    async Task<Guid?> Authenticate(WebSocket socket, CancellationToken aborted)
    {
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(aborted);
        timeout.CancelAfter(TimeSpan.FromSeconds(10));
        try
        {
            var buffer = new byte[4096];
            var frame = await socket.ReceiveAsync(buffer, timeout.Token);
            if (frame.MessageType != WebSocketMessageType.Text || !frame.EndOfMessage) return null;
            using var hello = JsonDocument.Parse(buffer.AsMemory(0, frame.Count));
            var token = hello.RootElement.GetProperty("access_token").GetString();
            var result = await new JsonWebTokenHandler().ValidateTokenAsync(token, Validation(config));
            return result.IsValid && result.Claims.TryGetValue("sub", out var sub) && Guid.TryParse(sub as string, out var id) ? id : null;
        }
        catch (Exception e) when (e is WebSocketException or OperationCanceledException or JsonException
                                      or KeyNotFoundException or InvalidOperationException)
        {
            return null;
        }
    }

    public static TokenValidationParameters Validation(IConfiguration config) => new()
    {
        ValidIssuer = JwtSettings.Issuer,
        ValidAudience = JwtSettings.Audience,
        IssuerSigningKey = JwtSettings.Key(config),
        ClockSkew = TimeSpan.FromSeconds(30),
    };

    public async Task Send(IEnumerable<Guid> userIds, string json)
    {
        foreach (var id in userIds.Distinct())
        {
            if (!players.TryGetValue(id, out var connections)) continue;
            foreach (var connection in connections.Keys) await SendTo(connection, json);
        }
    }

    public Task SendToAll(string json) => Send(players.Keys, json);

    async Task SendTo(Connection connection, string json)
    {
        await connection.Gate.WaitAsync();
        try
        {
            if (connection.Socket.State == WebSocketState.Open)
            {
                await connection.Socket.SendAsync(Encoding.UTF8.GetBytes(json), WebSocketMessageType.Text, true,
                    CancellationToken.None);
            }
        }
        catch (Exception e) when (e is WebSocketException or ObjectDisposedException)
        {
            log.LogDebug(e, "Dropped a realtime message for a closed connection");
        }
        finally
        {
            connection.Gate.Release();
        }
    }
}

/// <summary>
/// Listens on PostgreSQL channel bakhi_changes (triggers from migration 011),
/// reads each changed row and hands it to <see cref="RealtimeHub"/>.
/// </summary>
public sealed class ChangeListener(NpgsqlDataSource source, RealtimeHub hub, ILogger<ChangeListener> log)
    : BackgroundService
{
    // Table → key column named by the trigger. Nothing else is ever read.
    static readonly Dictionary<string, string> Keys = new()
    {
        ["messages"] = "id",
        ["challenges"] = "id",
        ["caro_matches"] = "challenge_id",
        ["challenge_runs"] = "id",
    };

    readonly Channel<string> queue = Channel.CreateUnbounded<string>(new() { SingleReader = true });

    protected override Task ExecuteAsync(CancellationToken stop) => Task.WhenAll(Listen(stop), Forward(stop));

    async Task Listen(CancellationToken stop)
    {
        var first = true;
        while (!stop.IsCancellationRequested)
        {
            try
            {
                await using var conn = await source.OpenConnectionAsync(stop);
                conn.Notification += (_, e) => queue.Writer.TryWrite(e.Payload);
                await using (var listen = new NpgsqlCommand("listen bakhi_changes", conn))
                {
                    await listen.ExecuteNonQueryAsync(stop);
                }
                // Changes made while the listener was down were never pushed.
                if (!first) await hub.SendToAll("""{"type":"resync"}""");
                first = false;
                while (!stop.IsCancellationRequested)
                {
                    if (!await conn.WaitAsync(TimeSpan.FromSeconds(30), stop))
                    {
                        // Quiet for a while: make sure the connection is still alive.
                        await using var ping = new NpgsqlCommand("select 1", conn);
                        await ping.ExecuteScalarAsync(stop);
                    }
                }
            }
            catch (OperationCanceledException) when (stop.IsCancellationRequested)
            {
                return;
            }
            catch (Exception e)
            {
                log.LogWarning(e, "Realtime listener lost the database; retrying");
                await Task.Delay(TimeSpan.FromSeconds(3), stop).ContinueWith(_ => { });
            }
        }
    }

    async Task Forward(CancellationToken stop)
    {
        await foreach (var payload in queue.Reader.ReadAllAsync(stop))
        {
            try
            {
                using var change = JsonDocument.Parse(payload);
                var root = change.RootElement;
                var table = root.GetProperty("table").GetString()!;
                if (!Keys.TryGetValue(table, out var keyColumn)) continue;
                var users = root.GetProperty("users").EnumerateArray()
                    .Select(u => Guid.TryParse(u.GetString(), out var id) ? id : Guid.Empty)
                    .Where(id => id != Guid.Empty).ToList();
                await using var read = source.CreateCommand(
                    $"select to_jsonb(t)::text from public.{table} t where t.{keyColumn} = $1::uuid");
                read.Parameters.AddWithValue(root.GetProperty("key").GetString()!);
                if (await read.ExecuteScalarAsync(stop) is not string row) continue;
                var message = $$"""{"type":"change","table":{{JsonSerializer.Serialize(table)}},"op":{{JsonSerializer.Serialize(root.GetProperty("op").GetString())}},"row":{{row}}}""";
                await hub.Send(users, message);
            }
            catch (Exception e) when (e is not OperationCanceledException)
            {
                log.LogWarning(e, "Could not forward change {Payload}", payload);
            }
        }
    }
}
