using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;

namespace BaKhi.Api;

/// <summary>
/// Forwards calls to the Supabase project (Auth, PostgREST tables and SQL
/// functions). The game rules and anti-cheat checks stay in those SQL
/// functions; this API gives them stable REST routes and Swagger docs.
/// The caller's bearer token is passed on, so row level security applies
/// to every request exactly as it does for the mobile app.
/// </summary>
public sealed class SupabaseGateway(HttpClient http, IConfiguration config)
{
    static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web);

    string BaseUrl => (config["Supabase:Url"] ?? throw new InvalidOperationException(
        "Missing Supabase:Url (env Supabase__Url)")).TrimEnd('/');

    string AnonKey => config["Supabase:AnonKey"] ?? throw new InvalidOperationException(
        "Missing Supabase:AnonKey (env Supabase__AnonKey)");

    /// <summary>The caller's JWT from "Authorization: Bearer …", if any.</summary>
    public static string? BearerOf(HttpContext ctx)
    {
        var header = ctx.Request.Headers.Authorization.ToString();
        return header.StartsWith("Bearer ", StringComparison.OrdinalIgnoreCase)
            ? header["Bearer ".Length..].Trim()
            : null;
    }

    /// <summary>
    /// The user id ("sub") inside a Supabase JWT. Only read, not verified:
    /// Supabase verifies the token on every forwarded request anyway.
    /// </summary>
    public static string? UserIdOf(string? jwt)
    {
        var parts = jwt?.Split('.');
        if (parts is not { Length: 3 }) return null;
        try
        {
            var payload = parts[1].Replace('-', '+').Replace('_', '/');
            payload = payload.PadRight(payload.Length + (4 - payload.Length % 4) % 4, '=');
            using var doc = JsonDocument.Parse(Convert.FromBase64String(payload));
            return doc.RootElement.TryGetProperty("sub", out var sub) ? sub.GetString() : null;
        }
        catch (Exception)
        {
            return null;
        }
    }

    public Task<IResult> Auth(HttpMethod method, string path, object? body, string? bearer = null) =>
        Send(method, $"/auth/v1/{path}", body, bearer);

    public Task<IResult> Rpc(string function, object body, string? bearer) =>
        Send(HttpMethod.Post, $"/rest/v1/rpc/{function}", body, bearer);

    public Task<IResult> Select(string tableAndQuery, string? bearer) =>
        Send(HttpMethod.Get, $"/rest/v1/{tableAndQuery}", null, bearer);

    public Task<IResult> Insert(string table, object row, string? bearer) =>
        Send(HttpMethod.Post, $"/rest/v1/{table}", row, bearer, preferRepresentation: true);

    async Task<IResult> Send(HttpMethod method, string path, object? body, string? bearer,
        bool preferRepresentation = false)
    {
        using var request = new HttpRequestMessage(method, BaseUrl + path);
        request.Headers.Add("apikey", AnonKey);
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", bearer ?? AnonKey);
        if (preferRepresentation) request.Headers.Add("Prefer", "return=representation");
        if (body is not null)
        {
            request.Content = new StringContent(
                JsonSerializer.Serialize(body, Json), Encoding.UTF8, "application/json");
        }

        try
        {
            using var response = await http.SendAsync(request);
            var text = await response.Content.ReadAsStringAsync();
            return Results.Content(
                string.IsNullOrEmpty(text) ? "null" : text,
                "application/json",
                Encoding.UTF8,
                (int)response.StatusCode);
        }
        catch (Exception ex) when (ex is HttpRequestException or TaskCanceledException)
        {
            return Results.Problem(
                title: "Không kết nối được Supabase",
                detail: ex.Message,
                statusCode: StatusCodes.Status502BadGateway);
        }
    }
}
