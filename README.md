# Bá Khí Game Hub

Đồ án môn Lập trình di động: ứng dụng điện thoại với 4 trò chơi (Sudoku, Xếp hình, Caro, hướng dẫn giải Rubik), tài khoản, tính điểm, bảng xếp hạng, thách đấu và nhắn tin.

| Thư mục | Nội dung |
| --- | --- |
| [`frontend/`](frontend/) | **Frontend – app Flutter** (Dart): giao diện, luật 4 trò chơi, AI Caro, giải Sudoku, nhận diện màu Rubik. Hướng dẫn chạy: [`frontend/README.md`](frontend/README.md) |
| [`backend/`](backend/) | **Backend**: Web API ASP.NET Core (.NET 10) có Swagger, chạy trên VPS tại **https://game.42-96-2-9.sslip.io/swagger**; database Supabase (PostgreSQL, hàm SQL, phân quyền RLS) trong [`backend/supabase/`](backend/supabase/). Hướng dẫn: [`backend/README.md`](backend/README.md) |
| [`docs/`](docs/) | Báo cáo kiểm thử QA, hướng dẫn cài đặt Supabase, tài liệu công nghệ |

## Chạy nhanh

```bash
# App Flutter (cần frontend/config/supabase.json, xem frontend/README.md)
cd frontend
flutter pub get
flutter run

# Web API
cd backend/BaKhi.Api
dotnet run

# Kiểm thử
cd frontend && flutter test                      # 64 test
npm ci --prefix backend/supabase/tests && npm test --prefix backend/supabase/tests   # 114 kiểm tra database
```

Tài liệu công nghệ dùng trong đồ án: [`docs/CONG_NGHE.md`](docs/CONG_NGHE.md).
