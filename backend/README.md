# BaKhi_API — backend tự viết

Backend của Bá Khí Game Hub: **ASP.NET Core (.NET 10) Web API + PostgreSQL 17**, tài liệu bằng Swagger, chạy bằng Docker trên VPS của nhóm. App Flutter chỉ gọi API này; không dùng dịch vụ backend bên ngoài.

- **Swagger:** https://game.42-96-2-9.sslip.io/swagger
- **OpenAPI JSON:** https://game.42-96-2-9.sslip.io/swagger/v1/swagger.json
- **WebSocket realtime:** `wss://game.42-96-2-9.sslip.io/ws`

## Kiến trúc

```
App Flutter ──HTTPS (REST + JWT)──► Caddy ──► BaKhi_API (ASP.NET Core) ──► PostgreSQL
            ◄──WebSocket /ws───────────────┘        ▲  LISTEN bakhi_changes │
                                                     └──────────────────────┘
Gmail SMTP ◄── BaKhi_API (gửi mã xác nhận / đặt lại mật khẩu)
```

| Thành phần | File | Việc làm |
| --- | --- | --- |
| Tài khoản | `BaKhi.Api/Auth.cs` | Đăng ký, mã 6 số qua email (lưu SHA-256, hết hạn 15 phút, tối đa 5 lần nhập, 1 phút mới gửi lại), mật khẩu băm BCrypt, JWT HS256 1 giờ + refresh token 30 ngày (dùng một lần), quên mật khẩu |
| Truy cập dữ liệu | `BaKhi.Api/Db.cs` | Mỗi yêu cầu chạy trong một transaction với role `authenticated` và id người chơi, nên Row Level Security và hàm SQL tự kiểm tra quyền; lỗi luật chơi trả về 400 kèm thông báo tiếng Việt |
| Luật chơi | `database/migrations/*.sql` | Hàm PL/pgSQL: tính điểm, chống gửi điểm giả, thách đấu Sudoku/Caro, luật chặn hai đầu, hết giờ, đầu hàng, xếp hạng |
| Realtime | `BaKhi.Api/Realtime.cs` + `011_self_hosted.sql` | Trigger `pg_notify` khi có tin nhắn / thách đấu / nước cờ → API `LISTEN` → đẩy qua WebSocket tới đúng hai người chơi |
| Tạo bảng | `Migrator` trong `Db.cs` | Các file SQL được nhúng vào DLL; khi khởi động API tự chạy file chưa chạy (ghi trong `schema_migrations`) |
| Chống dò mật khẩu | `Program.cs` | Giới hạn số lần gọi `/api/auth/*` theo địa chỉ IP |

| Nhóm | Endpoint |
| --- | --- |
| Auth | `POST /api/auth/register`, `/verify-otp`, `/resend-otp`, `/login`, `/refresh`, `/logout`, `/forgot-password`; `GET /api/auth/me`; `PUT /api/auth/password` |
| Players | `GET /api/players`, `GET /api/players/{id}` |
| Games | `POST /api/games/sessions`, `POST /api/games/results`, `GET /api/games/score` |
| Leaderboard | `GET /api/leaderboard`, `GET /api/leaderboard/me` |
| Challenges | `GET/POST /api/challenges`, `/{id}/accept`, `/decline`, `/cancel`, `/resign`, `/check-timeout`, `/sudoku/start`, `/sudoku/submit`, `GET /{id}/runs` |
| Caro online | `POST /api/caro/{id}/start`, `GET /api/caro/{id}`, `POST /api/caro/{id}/moves` |
| Messages | `GET /api/messages/{userId}`, `POST /api/messages` |

**Thử trên Swagger:** `POST /api/auth/register` → lấy mã trong email → `POST /api/auth/verify-otp` (hoặc `POST /api/auth/login`) → sao chép `access_token` → bấm **Authorize** → dán vào → gọi các endpoint khác.

## Chạy trên máy

Cần PostgreSQL (bất kỳ bản 14+). `appsettings.Development.json` trỏ tới `localhost:5432`, database/user/mật khẩu `bakhi`. Ở môi trường Development, nếu chưa cấu hình SMTP thì mã xác nhận được in ra log của API.

```bash
cd backend/BaKhi.Api
dotnet run
```

## Kiểm thử

```bash
npm ci --prefix backend/database/tests
npm test --prefix backend/database/tests        # migration + RLS + luật chơi trên PostgreSQL nhúng (PGlite)

# End-to-end với API đang chạy ở Development (đọc mã xác nhận từ log của API):
API_URL=http://localhost:5080 CODE_LOG=<file log của API> node backend/database/tests/api.mjs
```

## Triển khai lên VPS

VPS chỉ ~1 GB RAM nên build trên máy, chép bản đã build lên:

```bash
cd backend
dotnet publish BaKhi.Api -c Release -o deploy/publish
scp -r deploy/Dockerfile deploy/docker-compose.yml deploy/publish root@42.96.2.9:/opt/bakhi-game-api/
ssh root@42.96.2.9 "cd /opt/bakhi-game-api && docker compose up -d --build"
```

`/opt/bakhi-game-api/.env` (theo `deploy/.env.example`, không commit) chứa mật khẩu database, khóa ký JWT và tài khoản Gmail SMTP (mật khẩu ứng dụng của Google).

`docker-compose.yml` chạy hai container: `bakhi-game-db` (PostgreSQL, dữ liệu trong volume `db-data`, chỉ mở ở `127.0.0.1:5433` của VPS) và `bakhi-game-api`. HTTPS do Caddy có sẵn trên VPS (dự án `/opt/bakhi-api`) đảm nhận: API nối vào mạng `bakhi-api_default`, Caddyfile có thêm khối `deploy/Caddyfile.snippet` (Caddy tự chuyển tiếp WebSocket).

Sao lưu database:

```bash
ssh root@42.96.2.9 "docker exec bakhi-game-db pg_dump -U bakhi bakhi" > bakhi-backup.sql
```
