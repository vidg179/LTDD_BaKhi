# Công nghệ sử dụng trong Bá Khí Game Hub

Tài liệu ôn tập cho buổi bảo vệ đồ án: dùng công nghệ gì, để làm gì, và trả lời khi được hỏi.

## 1. Nền tảng chính

| Công nghệ | Dùng để làm gì | Vì sao chọn |
| --- | --- | --- |
| **Flutter 3.47** (ngôn ngữ **Dart 3.13**) | Viết toàn bộ app: giao diện, luật 4 trò chơi | Một mã nguồn cho cả Android và iOS, giao diện mượt, hot reload giúp sửa nhanh |
| **Android** (Android 7 / API 24 trở lên) | Nền tảng chạy và kiểm thử chính | Đã chạy trên điện thoại thật và máy ảo; iOS có cấu hình nhưng chưa chạy thử (cần máy Mac) |
| **ASP.NET Core 10** (C#) — BaKhi_API | Máy chủ (backend) do nhóm tự viết | Web API có Swagger, tự triển khai bằng Docker trên VPS của nhóm; toàn quyền về dữ liệu và luật chơi |
| **PostgreSQL 17** | Cơ sở dữ liệu | Mã nguồn mở, mạnh về SQL, có Row Level Security để phân quyền ngay trong database |

## 2. Backend tự viết (thư mục `backend/`)

| Phần | Dùng để làm gì |
| --- | --- |
| **Đăng nhập (JWT)** | Đăng ký là vào chơi ngay (không cần xác nhận email), đăng nhập trả về access token (1 giờ) + refresh token (30 ngày), quên mật khẩu bằng mã gửi qua email. Mật khẩu băm bằng **BCrypt**, mã đặt lại chỉ lưu dạng băm SHA-256 |
| **Gmail SMTP** (thư viện **MailKit**) | Gửi email chứa mã đặt lại mật khẩu |
| **Npgsql** | Thư viện C# kết nối PostgreSQL |
| **Row Level Security (RLS)** | Phân quyền ngay trong database: API chạy mỗi yêu cầu với quyền của đúng người chơi, nên ví dụ chỉ hai người trong cuộc mới đọc được tin nhắn |
| **Hàm SQL** (`plpgsql`) | Luật chạy trên máy chủ: kiểm tra nước đi Caro, đáp án Sudoku, tính điểm, hết giờ, đầu hàng. App chỉ gửi yêu cầu, máy chủ quyết định |
| **WebSocket** + `LISTEN/NOTIFY` | Realtime: khi có tin nhắn, lời mời hay nước cờ, trigger trong PostgreSQL báo cho API, API đẩy ngay qua WebSocket tới hai người chơi |
| **Swagger** (Swashbuckle) | Trang tài liệu và thử API: https://game.42-96-2-9.sslip.io/swagger |
| **Docker + Caddy** | Chạy API và database trên VPS; Caddy cấp HTTPS |
| **Migration** (`backend/database/migrations/000`–`011`) | File SQL tạo và cập nhật cấu trúc database; API tự chạy khi khởi động |

## 3. Thư viện Flutter

| Package | Dùng ở đâu |
| --- | --- |
| `http` | Gọi Web API (REST) kèm JWT |
| `web_socket_channel` | Kết nối WebSocket để nhận tin nhắn, lời mời, nước cờ tức thì |
| `camera` | Chụp các mặt khối Rubik |
| `image` | Đọc ảnh để nhận diện màu ô Rubik |
| `cuber` | Thuật toán giải Rubik (Kociemba hai pha), lời giải tối đa 24 bước |
| `image_picker` | Chọn ảnh trong máy cho trò Xếp hình |
| `shared_preferences` | Lưu lịch sử chơi trên điện thoại, dùng được khi không có mạng |
| `uuid` | Mã định danh duy nhất cho mỗi ván và tin nhắn, tránh lưu trùng khi gửi lại |
| `flutter_local_notifications` | Thông báo tin nhắn và lời mời thách đấu mới |
| `flutter_lints`, `flutter_test` | Kiểm tra chuẩn code và kiểm thử tự động |

**Quản lý trạng thái:** `ChangeNotifier` (lớp `AppStore`) kết hợp `setState`, có sẵn trong Flutter. App nhỏ nên một nơi giữ dữ liệu chung là đủ và dễ hiểu.

## 4. Thuật toán nhóm tự viết

| Trò chơi | Thuật toán |
| --- | --- |
| **Sudoku** | Sinh đề bằng quay lui (backtracking); kiểm tra đúng một lời giải; chấm độ khó bằng cách giải như người chơi (naked/hidden single, naked pair/triple, hidden pair, locked candidates) |
| **Caro** | Mức Khó: Negamax (dạng Minimax) với cắt tỉa Alpha-Beta, tính trước 4 lớp; đánh giá thế cờ theo từng cửa sổ 5 ô |
| **Xếp hình** | Xáo trộn bằng nước đi hợp lệ nên luôn giải được |
| **Rubik** | Nhận diện màu theo không gian màu HSV, kiểm tra khối hợp lệ, giải bằng `cuber`; mô hình 3D tự vẽ bằng `CustomPainter` |
| **Tính điểm** | `điểm = điểm gốc × hệ số × T / (T + giây)`, mỗi lỗi trừ 5%; chỉ dùng số nguyên để app và máy chủ ra cùng kết quả |

**Chạy nền (`compute` / isolate):** sinh đề Sudoku, AI Caro, nhận diện màu và giải Rubik chạy ở luồng riêng để giao diện không bị đơ.

## 5. Kiểm thử và công cụ

| Công cụ | Dùng để làm gì |
| --- | --- |
| `flutter test` | 71 bài kiểm tra tự động: luật trò chơi, AI, giao diện, đăng nhập |
| **PGlite** (Node.js) | PostgreSQL chạy ngay trong máy để kiểm thử database: 122 bài kiểm tra về phân quyền, gian lận, hết giờ, realtime |
| `api.mjs` (Node.js) | Kiểm thử end-to-end API thật: 61 bài kiểm tra đăng ký bằng mã, JWT, WebSocket, Caro online, chat |
| `flutter analyze` | Kiểm tra lỗi code tĩnh |
| **Android Emulator** | Máy ảo Pixel 7 để chạy thử |
| **Git + GitHub** | Quản lý mã nguồn: https://github.com/vidg179/LTDD_BaKhi |

## 6. Câu hỏi thường gặp

- **Backend ở đâu, ai viết?** Nhóm tự viết bằng ASP.NET Core (thư mục `backend/`), chạy bằng Docker trên VPS cùng PostgreSQL. App chỉ gọi API này qua HTTPS.
- **Đăng nhập an toàn thế nào?** Mật khẩu băm BCrypt; đăng nhập cấp JWT ký HS256 hết hạn sau 1 giờ, app tự gia hạn bằng refresh token (mỗi token dùng một lần). API giới hạn số lần gọi đăng nhập theo IP để chống dò mật khẩu.
- **Realtime làm thế nào?** PostgreSQL có trigger gọi `pg_notify` khi có thay đổi; API `LISTEN` kênh đó và đẩy dòng dữ liệu qua WebSocket tới đúng hai người liên quan. Mất mạng thì app tự kết nối lại và tải lại dữ liệu.
- **Chống gian lận điểm thế nào?** App không được ghi điểm thẳng vào database. Máy chủ tự bấm giờ từng ván; kết quả nhanh hoặc cao bất thường không được xếp hạng.
- **AI Caro hoạt động ra sao?** Máy thử trước 4 nước của cả hai bên bằng Negamax và cắt tỉa Alpha-Beta rồi chọn nước có lợi nhất. Trong 200 ván tự đánh, mức Khó thắng mức Vừa 71%.
- **Làm sao biết Sudoku chỉ có một đáp án?** Thuật toán quay lui đếm số lời giải và dừng khi gặp lời giải thứ hai; chỉ giữ đề có đúng 1.
- **Thông báo hoạt động thế nào?** App nhận sự kiện qua WebSocket rồi hiện thông báo bằng `flutter_local_notifications`. Tắt hẳn app thì không nhận được; muốn vậy phải dùng Firebase Cloud Messaging.
- **Dữ liệu lưu ở đâu?** Lịch sử chơi trên máy bằng `shared_preferences`; tài khoản, điểm online, tin nhắn, thách đấu trong PostgreSQL trên VPS của nhóm.
