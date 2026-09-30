# Bá Khí — Game Hub

Ứng dụng Flutter cho học phần Lập trình trên thiết bị di động.

## Chức năng

| Module | Đã triển khai |
| --- | --- |
| Tài khoản | Đăng ký email/mật khẩu, xác nhận email qua deep link, đăng nhập, đăng xuất, giữ phiên bằng Supabase Auth |
| Sudoku | Dễ/vừa/khó, đề duy nhất một lời giải, ghi chú, kiểm tra lỗi, đồng hồ, tính điểm |
| Xếp hình | Trượt ô 3×3 và 4×4; xáo trộn bằng nước hợp lệ, kiểm tra hoàn thành |
| Caro | Bàn 15×15; máy dễ đi ngẫu nhiên gần quân, vừa đánh giá thế cờ, khó xét phản công; kiểm tra thắng/thua/hòa |
| Rubik | Quét 6 mặt 3×3, sửa màu, bộ giải offline, hướng dẫn từng bước, thời gian và lỗi tự ghi nhận |
| Điểm | Lưu lịch sử trên máy, đồng bộ kết quả của tài khoản khi có mạng, gửi lại không trùng bản ghi |
| Xếp hạng | Kỷ lục cá nhân; online lấy kết quả tốt nhất mỗi người theo game và độ khó |
| Thách đấu | Mời người chơi giải cùng đề Sudoku, chấp nhận/từ chối, tính giờ server, kiểm tra đáp án, xác định người thắng |
| Chat | Nhắn tin riêng, cập nhật Realtime, hiển thị 100 tin nhắn gần nhất của cuộc hội thoại |

Game chơi được ở chế độ khách khi chưa cấu hình Supabase. **Đăng ký/đăng nhập, chat, thách đấu và xếp hạng online cần kết nối dự án Supabase thật.** Không có tài khoản hoặc cuộc hội thoại giả lập.

## Chạy nhanh

```sh
flutter pub get
flutter devices
flutter run -d <device-id>
```

Khi có `config/supabase.json`, lệnh `flutter run` và nút Run trong IDE sẽ tự đọc cấu hình này. `--dart-define-from-file` vẫn được ưu tiên nếu được truyền vào.

Android API 24 trở lên; iOS theo cấu hình hiện tại của project (15 trở lên). Build iOS cần macOS/Xcode. Camera cần thử trên thiết bị thật.

```sh
flutter build apk --debug
```

APK: `build/app/outputs/flutter-apk/app-debug.apk`.

## Kết nối Supabase

Xem chi tiết trong [docs/SUPABASE_SETUP.md](docs/SUPABASE_SETUP.md).

1. Tạo project Supabase, mở SQL Editor và chạy **một lần** `supabase/migrations/001_game_app.sql` trên project mới. Sau đó chạy `supabase/migrations/002_caro_challenges.sql` để bật thách đấu Caro.
2. Bật Email/Password trong Authentication. Thêm Redirect URL `io.bakhi.gameapp://login-callback/`.
3. Sao chép `config/supabase.example.json` thành `config/supabase.json`, điền project URL và publishable/anon key. File cấu hình thật đã được bỏ qua trong Git.
4. Chạy hoặc build với cấu hình:

```sh
flutter run --dart-define-from-file=config/supabase.json
flutter build apk --debug --dart-define-from-file=config/supabase.json
```

APK build không có tham số cấu hình chỉ chạy chế độ khách. Sau khi điền cấu hình phải build lại; hot reload không cập nhật dart-define.

## Điểm và luật chơi

`điểm = max(100, điểm_gốc × hệ_số − 2 × giây − 100 × lỗi)` cho ván hoàn thành/thắng.

- Điểm gốc: Sudoku 2000, Xếp hình 1500, Caro/Rubik 1000.
- Hệ số Dễ/Vừa/Khó: 1/2/3. Rubik có hướng dẫn chỉ dùng hệ số 1.
- Sudoku: nhập sai đáp án tính 1 lỗi. Nhập lại cùng giá trị không tính thêm; ghi chú không tính lỗi.
- Xếp hình: chạm ô không kề khoảng trống tính 1 lỗi. Dễ dùng 3×3; Vừa/Khó dùng 4×4 với số bước xáo khác nhau.
- Caro dùng luật freestyle: ít nhất 5 quân liên tiếp là thắng, kể cả chặn hai đầu. Không tính lỗi chiến thuật. Thua/hòa được 0 điểm.
- Rubik có hướng dẫn: tự ghi nhận lỗi; xác nhận từng bước trên khối thật. Khối đã giải sẵn không được điểm.
- Ván đơn dừng đồng hồ khi tạm dừng hoặc app xuống nền. Ván chưa hoàn thành không tính điểm; rời ván đơn sẽ mất tiến độ.
- Thách đấu tính giờ liên tục trên server. Tiến độ Sudoku thách đấu và số lỗi được lưu trên cùng thiết bị để tiếp tục; ghi chú chưa được lưu. Đổi thiết bị không mang theo bản nháp nhưng đồng hồ server vẫn chạy.
- Thách đấu so điểm, rồi thời gian, rồi số lỗi; giống cả ba là hòa. Kết quả nằm trong Cộng đồng, không trộn vào xếp hạng chơi đơn.
- Lịch sử khách và từng tài khoản tách riêng. Điểm khách không tự chuyển sang tài khoản sau đăng nhập. Lịch sử trên máy hiển thị 50 ván mới nhất; bảng kỷ lục hiển thị 30 ván và online 50 người.

## Quét Rubik

1. Cầm tâm xanh lá ở trước và tâm trắng ở trên; tâm đỏ bên phải, cam bên trái, xanh dương phía sau và vàng ở dưới.
2. Quét lần lượt theo màu tâm: **Trắng, Đỏ, Xanh lá, Vàng, Cam, Xanh dương**. Chỉ xoay cả khối, không vặn tầng trong lúc quét.
3. Cạnh trên ảnh phải giáp màu tâm: **Trắng→Xanh dương, Đỏ→Trắng, Xanh lá→Trắng, Vàng→Xanh lá, Cam→Trắng, Xanh dương→Trắng**.
4. Đặt mặt khối thẳng camera và vừa khung trắng. Kiểm tra/sửa cả 9 ô, kể cả tâm; có nút xoay lưới.
5. Khi giải, cầm lại tâm xanh lá ở trước, tâm trắng ở trên. Ký hiệu U/R/F/D/L/B chỉ dùng trong công thức; chiều xoay tính khi nhìn thẳng vào mặt đang xoay.

Nhận diện màu dùng HSV và trung vị vùng giữa ô, chưa tự tìm góc hoặc hiệu chỉnh phối cảnh. Cần đủ sáng và tránh phản chiếu. Bộ giải Kociemba (`cuber`) có giới hạn tìm kiếm 20 giây/24 bước và xác minh lời giải bằng cách áp lại các nước đi. Ảnh không gửi lên server.

## Cấu trúc

```text
lib/
  main.dart              # Khởi tạo cấu hình và Supabase
  data/app_store.dart    # Auth, dữ liệu local, đồng bộ, API cộng đồng
  games/                 # Logic thuần Dart, màn hình và đồng hồ game
  rubik/                 # Camera, nhận diện và giải Rubik
  ui/                    # Hub, tài khoản, xếp hạng, cộng đồng và chat
supabase/migrations/     # Schema, RLS, RPC và cấu hình Realtime
config/                  # Mẫu cấu hình build
 test/                   # Unit/widget tests
 tool/backend_test/      # Kiểm tra SQL trong PostgreSQL nhúng
```

## Kiểm tra

```sh
flutter analyze
flutter test
flutter build apk --debug
npm ci --prefix tool/backend_test
npm test --prefix tool/backend_test
```

Backend test thực thi migration trên PostgreSQL nhúng (PGlite), kiểm tra RLS, quyền gửi/đọc chat, điểm sinh ở database, trạng thái thách đấu và gửi lại kết quả. Đây không phải kiểm thử Supabase Auth/email/Realtime qua mạng.

## Giới hạn cần biết khi báo cáo

- Chưa kiểm thử camera trên điện thoại thật hoặc đăng nhập/chat hai thiết bị với project Supabase thật.
- Điểm chơi đơn và số lỗi vẫn do client báo; database tính lại điểm nhưng chưa có hệ thống chống gian lận cho giải đấu. Với thách đấu, server kiểm tra đề/đáp án và thời gian, còn số lỗi do client báo.
- Độ khó Sudoku được phân theo số ô gợi ý, không chấm theo kỹ thuật giải của con người. Thách đấu dùng 3 đề chuẩn, hoán vị chữ số để hai người nhận cùng đề hợp lệ.
- Chat chưa có thông báo đẩy, trạng thái đã đọc hoặc tệp đính kèm. Danh sách cộng đồng hiện lấy tối đa 100 người.
- Dữ liệu local dùng SharedPreferences, không phải kho dữ liệu quan trọng có bảo đảm giao dịch. Phiên quét Rubik không lưu khi đóng app.
- Chưa cấu hình khóa ký phát hành; APK debug dùng cho kiểm thử học phần.

Tham khảo chính thức: [Supabase Flutter](https://supabase.com/docs/guides/getting-started/quickstarts/flutter), [RLS](https://supabase.com/docs/guides/database/postgres/row-level-security), [Camera](https://pub.dev/packages/camera), [Cuber](https://pub.dev/packages/cuber).
