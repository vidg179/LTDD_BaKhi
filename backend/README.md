# BaKhi_API — Web API có Swagger

ASP.NET Core (.NET 10) Web API cho Bá Khí Game Hub, tài liệu bằng Swagger.

- **Swagger:** https://game.42-96-2-9.sslip.io/swagger
- **OpenAPI JSON:** https://game.42-96-2-9.sslip.io/swagger/v1/swagger.json

## Kiến trúc

```
App Flutter ──► Supabase (Auth, PostgreSQL, Realtime)
                     ▲
BaKhi_API (VPS) ─────┘  REST + Swagger, chuyển tiếp tới hàm SQL / bảng
```

API không giữ dữ liệu riêng: mỗi endpoint gọi đúng hàm SQL hoặc bảng trên Supabase mà app đang dùng, kèm token của người gọi. Vì vậy luật trò chơi, chống gian lận và phân quyền (RLS) giống hệt khi gọi từ app. App Flutter hiện vẫn gọi Supabase trực tiếp; chat và Caro online cần Realtime của Supabase.

| Nhóm | Endpoint chính |
| --- | --- |
| Auth | `POST /api/auth/register`, `/verify-otp`, `/login`, `/refresh`, `/forgot-password`, `GET /api/auth/me` |
| Games | `POST /api/games/sessions`, `POST /api/games/results`, `GET /api/games/score` |
| Leaderboard | `GET /api/leaderboard`, `GET /api/leaderboard/me` |
| Challenges | `GET/POST /api/challenges`, `/{id}/accept`, `/decline`, `/cancel`, `/resign`, `/check-timeout`, `/sudoku/start`, `/sudoku/submit` |
| Caro online | `POST /api/caro/{id}/start`, `GET /api/caro/{id}`, `POST /api/caro/{id}/moves` |
| Messages | `GET /api/messages/{userId}`, `POST /api/messages` |

**Thử trên Swagger:** gọi `POST /api/auth/login` → sao chép `access_token` → bấm **Authorize** → dán vào → gọi các endpoint khác.

## Chạy trên máy

```bash
cd backend/BaKhi.Api
Supabase__Url=https://<project>.supabase.co Supabase__AnonKey=<anon key> dotnet run
```

## Triển khai lên VPS

VPS chỉ ~1 GB RAM nên build trên máy, chép bản đã build lên:

```bash
cd backend
dotnet publish BaKhi.Api -c Release -o deploy/publish
scp -r deploy/Dockerfile deploy/docker-compose.yml deploy/publish root@42.96.2.9:/opt/bakhi-game-api/
ssh root@42.96.2.9 "cd /opt/bakhi-game-api && docker compose up -d --build"
```

`/opt/bakhi-game-api/.env` (theo `deploy/.env.example`) chứa `Supabase__Url` và `Supabase__AnonKey` — chỉ dùng anon key, không dùng service_role.

HTTPS do Caddy có sẵn trên VPS (dự án `/opt/bakhi-api`, API Điểm danh HUTECH) đảm nhận: container `bakhi-game-api` nối vào mạng `bakhi-api_default`, và Caddyfile có thêm khối `deploy/Caddyfile.snippet`. Caddyfile trên server là file bind-mount: sửa xong phải `docker cp` vào container rồi `caddy reload --config` file đó (hoặc khởi động lại container caddy).
