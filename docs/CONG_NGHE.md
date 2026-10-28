# Công nghệ sử dụng trong Bá Khí Game Hub

Tài liệu ôn tập cho buổi bảo vệ đồ án: dùng công nghệ gì, để làm gì, và trả lời khi được hỏi.

## 1. Nền tảng chính

| Công nghệ | Dùng để làm gì | Vì sao chọn |
| --- | --- | --- |
| **Flutter 3.47** (ngôn ngữ **Dart 3.13**) | Viết toàn bộ app: giao diện, luật 4 trò chơi | Một mã nguồn cho cả Android và iOS, giao diện mượt, hot reload giúp sửa nhanh |
| **Android** (Android 7 / API 24 trở lên) | Nền tảng chạy và kiểm thử chính | Đã chạy trên điện thoại thật và máy ảo; iOS có cấu hình nhưng chưa chạy thử (cần máy Mac) |
| **Supabase** | Máy chủ (backend) | Backend mã nguồn mở dựa trên PostgreSQL, có sẵn đăng nhập, cơ sở dữ liệu và dữ liệu thời gian thực, không phải tự dựng server |

## 2. Các phần của Supabase

| Phần | Dùng để làm gì |
| --- | --- |
| **Supabase Auth** | Đăng ký, đăng nhập, xác nhận bằng mã gửi qua email (OTP), quên mật khẩu, giữ phiên |
| **PostgreSQL** | Lưu tài khoản, kết quả chơi, tin nhắn, thách đấu, bàn cờ Caro online |
| **Row Level Security (RLS)** | Phân quyền ngay trong database, ví dụ chỉ hai người trong cuộc mới đọc được tin nhắn |
| **Hàm SQL / RPC** (`plpgsql`) | Luật chạy trên máy chủ: kiểm tra nước đi Caro, đáp án Sudoku, tính điểm, hết giờ, đầu hàng. App chỉ gửi yêu cầu, máy chủ quyết định |
| **Supabase Realtime** | Gửi dữ liệu tức thì giữa hai máy: tin nhắn, lời mời, nước đi Caro online, thông báo |
| **SMTP Gmail** | Gửi email chứa mã xác nhận |
| **Migration** (`supabase/migrations/001`–`010`) | File SQL tạo và cập nhật cấu trúc database theo từng bước |

## 3. Thư viện Flutter

| Package | Dùng ở đâu |
| --- | --- |
| `supabase_flutter` | Kết nối Supabase: đăng nhập, database, Realtime |
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
| `flutter test` | 64 bài kiểm tra tự động: luật trò chơi, AI, giao diện, đăng nhập |
| **PGlite** (Node.js) | PostgreSQL chạy ngay trong máy để kiểm thử backend: 114 bài kiểm tra về phân quyền, gian lận, hết giờ |
| `flutter analyze` | Kiểm tra lỗi code tĩnh |
| **Android Emulator** | Máy ảo Pixel 7 để chạy thử |
| **Git + GitHub** | Quản lý mã nguồn: https://github.com/vidg179/LTDD_BaKhi |

## 6. Câu hỏi thường gặp

- **Sao không dùng Firebase?** Supabase dùng SQL nên viết luật kiểm tra ở máy chủ dễ hơn, phân quyền bằng RLS rõ ràng, và kiểm thử backend được ngay trên máy.
- **Chống gian lận điểm thế nào?** App không được ghi điểm thẳng vào database. Máy chủ tự bấm giờ từng ván; kết quả nhanh hoặc cao bất thường không được xếp hạng.
- **AI Caro hoạt động ra sao?** Máy thử trước 4 nước của cả hai bên bằng Negamax và cắt tỉa Alpha-Beta rồi chọn nước có lợi nhất. Trong 200 ván tự đánh, mức Khó thắng mức Vừa 71%.
- **Làm sao biết Sudoku chỉ có một đáp án?** Thuật toán quay lui đếm số lời giải và dừng khi gặp lời giải thứ hai; chỉ giữ đề có đúng 1.
- **Thông báo hoạt động thế nào?** App nghe Realtime của Supabase rồi hiện thông báo bằng `flutter_local_notifications`. Tắt hẳn app thì không nhận được; muốn vậy phải dùng Firebase Cloud Messaging.
- **Dữ liệu lưu ở đâu?** Lịch sử chơi trên máy bằng `shared_preferences`; tài khoản, điểm online, tin nhắn, thách đấu trên Supabase.
