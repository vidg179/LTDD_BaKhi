# Bá Khí Game Hub

Đồ án môn Lập trình di động: ứng dụng điện thoại với 4 trò chơi (Sudoku, Xếp hình, Caro, hướng dẫn giải Rubik), tài khoản, tính điểm, bảng xếp hạng, thách đấu và nhắn tin.

| Thư mục | Nội dung |
| --- | --- |
| [`frontend/`](frontend/) | **Frontend – app Flutter** (Dart): giao diện, luật 4 trò chơi, AI Caro, giải Sudoku, nhận diện màu Rubik. Hướng dẫn chạy: [`frontend/README.md`](frontend/README.md) |
| [`backend/`](backend/) | **Backend tự viết**: Web API ASP.NET Core (.NET 10) + PostgreSQL, có Swagger, chạy bằng Docker trên VPS tại **https://game.42-96-2-9.sslip.io/swagger**. Đăng nhập JWT (đăng ký là vào chơi ngay), luật chơi bằng hàm SQL và phân quyền RLS trong [`backend/database/`](backend/database/), realtime bằng WebSocket. Hướng dẫn: [`backend/README.md`](backend/README.md) |
| [`docs/`](docs/) | Báo cáo kiểm thử QA, tài liệu công nghệ |

## Chạy nhanh

```bash
# App Flutter (mặc định gọi API trên VPS)
cd frontend
flutter pub get
flutter run

# Web API (cần PostgreSQL, xem backend/README.md)
cd backend/BaKhi.Api
dotnet run

# Kiểm thử
cd frontend && flutter test                      # 71 test
npm ci --prefix backend/database/tests && npm test --prefix backend/database/tests   # 122 kiểm tra database
```

Tài liệu công nghệ dùng trong đồ án: [`docs/CONG_NGHE.md`](docs/CONG_NGHE.md).
