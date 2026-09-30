# Thiết lập Supabase

## 1. Tạo database

Tạo project Supabase mới. Mở **SQL Editor**, sao chép toàn bộ `supabase/migrations/001_game_app.sql`, chạy một lần. Script tạo:

- `profiles`: tên hiển thị (email nằm ở Supabase Auth, không công khai cho người chơi khác).
- `game_results` và view `leaderboard`: kết quả chơi đơn, điểm tính ở database.
- `messages`: chat riêng; chỉ người gửi và người nhận đọc được.
- `challenges`, `challenge_puzzles`, `challenge_runs`: lời mời, đề riêng và kết quả.
- RPC tạo/chấp nhận/bắt đầu/nộp thách đấu. Client không được sửa trực tiếp thời gian hoặc kết quả thách đấu.
- Realtime publication cho `messages` và `challenges`.

Sau đó sao chép toàn bộ `supabase/migrations/002_caro_challenges.sql` sang SQL Editor và chạy một lần. Migration này thêm loại trò chơi vào lời mời, bàn Caro trực tuyến và kiểm tra lượt đi/thắng thua ở server.

Script có transaction và dành cho project mới; không chạy lặp sau khi đã tạo các bảng. Nếu trước đó đã tạo tài khoản, thêm profile tương ứng trong SQL Editor:

```sql
insert into public.profiles(id, display_name)
select id,
  case when char_length(trim(coalesce(raw_user_meta_data->>'display_name', ''))) >= 2
    then left(trim(raw_user_meta_data->>'display_name'), 40)
    else 'Người chơi' end
from auth.users
on conflict (id) do nothing;
```

## 2. Authentication

Bật provider **Email** cùng đăng ký mật khẩu. Ứng dụng yêu cầu mật khẩu ít nhất 8 ký tự khi đăng ký.

Trong **Authentication → URL Configuration → Redirect URLs**, thêm:

```text
io.bakhi.gameapp://login-callback/
```

Android manifest và iOS Info.plist đã khai báo URL scheme này; Supabase SDK nhận callback. Nếu bật Confirm email, mở link xác nhận trên cùng thiết bị đã đăng ký; sau đó có thể đăng nhập email/mật khẩu. Trong môi trường demo riêng của nhóm có thể tắt Confirm email nếu giảng viên không yêu cầu xác thực email. Khi gửi email thực tế, cấu hình SMTP phù hợp giới hạn dịch vụ của project.

## 3. Cấu hình Flutter

Copy `config/supabase.example.json` thành `config/supabase.json`:

```json
{
  "SUPABASE_URL": "https://YOUR_PROJECT.supabase.co",
  "SUPABASE_ANON_KEY": "YOUR_PUBLISHABLE_OR_ANON_KEY"
}
```

Dùng **publishable key** hoặc **anon key** của project. Không dùng secret/service_role key vì các khóa đó bỏ qua quyền của người chơi.

```sh
flutter run --dart-define-from-file=config/supabase.json
flutter build apk --debug --dart-define-from-file=config/supabase.json
```

Không đưa `config/supabase.json` vào Git. Giá trị cấu hình được đóng vào bản build; sau khi sửa cần chạy/build lại.

## 4. Kiểm thử hai tài khoản

1. Tạo tài khoản A và B. Có thể dùng hai emulator hoặc emulator và điện thoại, cùng một Supabase project.
2. A đăng nhập, chơi hoàn thành Sudoku. Tài khoản → Đồng bộ; kiểm tra có một hàng `game_results` và điểm trên xếp hạng.
3. Mất mạng rồi hoàn thành ván khác: vẫn lưu local. Có mạng lại, bấm Đồng bộ. Bấm nhiều lần không tạo hàng trùng.
4. A vào Cộng đồng → nút chat của B, gửi tin. B mở chat với A, kiểm tra tin cập nhật. Đăng nhập C không được đọc tin A/B qua API.
5. A mời B thách đấu Sudoku. B chấp nhận. Cả hai bấm Bắt đầu để nhận cùng đề và đồng hồ riêng.
6. Rời app rồi mở lại ván trên cùng thiết bị: tiến độ đã nhập khôi phục; đồng hồ không đặt lại. Giải xong, server kiểm tra đáp án và tính điểm. Khi cả hai nộp, trạng thái chuyển hoàn thành và có người thắng hoặc hòa.
7. Kiểm tra từ chối lời mời, mất mạng khi gửi tin/nộp kết quả và thử lại; không có tin hoặc lượt nộp trùng.
8. Đăng xuất: lịch sử khách hiện lại; kết quả tài khoản trước không chuyển sang tài khoản khác.
9. A gửi lời mời **Cờ Caro**, B chấp nhận. Mở ván trên cả hai thiết bị; A cầm X đi trước và mỗi nước đi phải tự xuất hiện trên thiết bị còn lại.

Kết quả thách đấu không đưa vào bảng xếp hạng chơi đơn; xem ở Cộng đồng → Xem kết quả.

## 5. Kiểm thử database không cần project online

```sh
npm ci --prefix tool/backend_test
npm test --prefix tool/backend_test
```

PGlite chạy PostgreSQL trong bộ nhớ, dựng fixture `auth.uid()` và áp dụng **chính migration của ứng dụng**. Không tạo project cloud hoặc gửi email/tin nhắn thật. Bài test xác minh chính sách đọc/ghi, tính điểm, cùng đề, đồng hồ không reset, đáp án hợp lệ, kết quả idempotent và quyền của người ngoài.

Các lệnh kiểm thử này không xác minh cấu hình SMTP, callback trên thiết bị hoặc kết nối Realtime của project thật.
