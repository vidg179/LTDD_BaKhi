# Thiết lập Supabase

## Đã thiết lập từ trước? Kiểm tra migration còn thiếu

Mở **SQL Editor**, dán toàn bộ `supabase/check_migrations.sql` và bấm Run. File này chỉ đọc, không thay đổi gì. Kết quả có 10 dòng, mỗi migration một dòng, ghi “✅ đã chạy” hoặc “❌ CHƯA CHẠY”.

- Tất cả ✅: không cần làm gì.
- Có ❌: chạy lần lượt các file trong `supabase/migrations/` **từ file ❌ đầu tiên đến hết 010**, kể cả những file đã ✅ nằm sau nó, rồi chạy lại file kiểm tra để chắc chắn tất cả đã ✅. Các file từ 004 đến 010 chạy lại nhiều lần đều an toàn, nhưng chạy riêng một file cũ sẽ ghi đè hàm của file mới hơn. Câu kiểm tra phát hiện được trường hợp đó và cũng báo ❌.
- 001–003 bị ❌ nghĩa là project chưa được tạo theo hướng dẫn bên dưới. Không chạy lại 001 trên project đã có dữ liệu, vì file này tạo bảng mới.


## 1. Tạo database

Tạo project Supabase mới. Mở **SQL Editor**, sao chép toàn bộ `supabase/migrations/001_game_app.sql`, chạy một lần. Script tạo:

- `profiles`: tên hiển thị (email nằm ở Supabase Auth, không công khai cho người chơi khác).
- `game_results` và view `leaderboard`: kết quả chơi đơn, điểm tính ở database.
- `messages`: chat riêng; chỉ người gửi và người nhận đọc được.
- `challenges`, `challenge_puzzles`, `challenge_runs`: lời mời, đề riêng và kết quả.
- RPC tạo/chấp nhận/bắt đầu/nộp thách đấu. Client không được sửa trực tiếp thời gian hoặc kết quả thách đấu.
- Realtime publication cho `messages` và `challenges`.

Sau đó sao chép toàn bộ `supabase/migrations/002_caro_challenges.sql` sang SQL Editor và chạy một lần. Migration này thêm loại trò chơi vào lời mời, bàn Caro trực tuyến và kiểm tra lượt đi/thắng thua ở server.

Cuối cùng chạy `supabase/migrations/003_revoke_anon.sql`. Supabase mặc định cấp quyền cho người chưa đăng nhập (`anon`) trên hàm và bảng mới; migration này rút quyền đó khỏi các hàm thách đấu và bảng `caro_matches`. Có thể chạy lại nhiều lần.

Sau đó chạy `supabase/migrations/004_caro_vietnam_rule.sql`. Migration này thay hàm `play_caro_move` để Caro online dùng luật Việt Nam: 5 quân bị quân đối phương chặn cả hai đầu không được tính thắng (mép bàn không tính là chặn). Có thể chạy lại nhiều lần; quyền đã cấp/rút ở 002–003 được giữ nguyên.

Cuối cùng chạy `supabase/migrations/005_verified_results.sql`. Migration này rút quyền ghi trực tiếp vào `game_results`; app gửi kết quả qua RPC `submit_game_result`, và chỉ kết quả có phiên do server mở (`start_game_session`) cùng thời gian/số nước hợp lý mới lên bảng xếp hạng. **Các kết quả có sẵn trước migration không xác minh được nên sẽ không còn trên bảng xếp hạng** (vẫn nằm trong bảng `game_results`). Có thể chạy lại nhiều lần.

Sau cùng chạy `supabase/migrations/006_challenge_deadlines.sql`. Migration này thêm hạn trả lời lời mời (24 giờ), hạn thi đấu sau khi chấp nhận (24 giờ), đồng hồ 60 giây mỗi lượt cho Caro online và RPC `resign_challenge`, `check_challenge_timeout`. Không cần cron: kết quả quá hạn được chốt khi người chơi gọi bất kỳ hàm thách đấu nào. Các thách đấu đang diễn ra lúc chạy migration được cấp hạn mới 24 giờ. Có thể chạy lại nhiều lần.

Cuối cùng chạy `supabase/migrations/007_graded_sudoku.sql`. Migration này thay 3 đề Sudoku thách đấu cũ (cả ba thực ra chỉ ở mức Dễ) bằng 18 đề, 6 đề mỗi mức, đã chấm bằng cùng thang với chơi đơn; mỗi lời mời chọn ngẫu nhiên một đề và hoán vị chữ số. Migration cũng cập nhật số nước tối thiểu của Sudoku trong kiểm tra xếp hạng cho khớp bộ sinh đề mới. Thách đấu đã tạo trước đó giữ nguyên đề cũ. Có thể chạy lại nhiều lần.

Sau cùng chạy `supabase/migrations/008_score_formula.sql`. Migration này thay hàm `game_score` bằng công thức mới (thời gian chuẩn theo từng game/mức, mỗi lỗi −5%, không còn sàn 100 điểm) và tính lại điểm của mọi kết quả đã lưu, nên bảng xếp hạng đổi ngay. Điểm của các lượt thách đấu đã kết thúc giữ nguyên, để không làm lệch người thắng đã công bố. Có thể chạy lại nhiều lần.

Cuối cùng chạy `supabase/migrations/009_cancel_challenge.sql`. Migration này thêm trạng thái `cancelled` và RPC `cancel_challenge`: người gửi hủy được lời mời khi còn chờ; lời mời đã hủy vẫn hiện ở cả hai máy (“Người gửi đã hủy”) và không chấp nhận được nữa. Có thể chạy lại nhiều lần.

Sau cùng chạy `supabase/migrations/010_leaderboard_rank.sql`. Migration này thêm cột `achieved_at` vào view `leaderboard` (khi bằng điểm, giây và lỗi thì ai đạt trước xếp trên) và hàm `my_leaderboard_rank` để người chơi ngoài top 50 thấy hạng của mình. Có thể chạy lại nhiều lần.

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

Android manifest và iOS Info.plist đã khai báo URL scheme này; Supabase SDK nhận callback. Nếu bật Confirm email, mở link xác nhận trên cùng thiết bị đã đăng ký; sau đó có thể đăng nhập email/mật khẩu. Link **đặt lại mật khẩu** (nút “Quên mật khẩu?”) dùng cùng Redirect URL và cũng phải mở trên chính điện thoại đã bấm gửi: SDK dùng PKCE, mã xác minh chỉ lưu trên thiết bị yêu cầu. Mở link đúng thiết bị thì app chuyển sang màn “Đặt mật khẩu mới”; mở trên máy khác hoặc link đã hết hạn/đã dùng thì form đăng nhập báo lỗi và hướng dẫn gửi lại. Mẫu email “Reset Password” mặc định của Supabase dùng được, không cần sửa. Trong môi trường demo riêng của nhóm có thể tắt Confirm email nếu giảng viên không yêu cầu xác thực email. Khi gửi email thực tế, cấu hình SMTP phù hợp giới hạn dịch vụ của project.

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
