# Báo cáo audit & tối ưu — 2026-10-17

Phạm vi: toàn bộ `lib/`, `test/`, `android/`, `ios/Runner/Info.plist`, `pubspec.yaml`, `supabase/migrations/`.
Môi trường: Flutter 3.47.4 stable, Dart 3.13.3, Android SDK 36, Windows 11. Thư mục dự án **không phải Git repo**; bản sao trước khi sửa được giữ ngoài dự án (thư mục tạm của phiên làm việc).

## Hiện trạng

Flutter app (Android/iOS) với Supabase (Auth, Postgres + RLS, Realtime). Kiến trúc gọn: `AppStore` (ChangeNotifier) giữ auth, lịch sử local (SharedPreferences) và API; engine game thuần Dart, có test; tính toán nặng (sinh Sudoku, AI Caro, nhận diện màu, giải Rubik) chạy trong `compute`. Backend kiểm tra quyền bằng RLS và RPC `security definer`, điểm tính ở DB. Trước khi sửa: `flutter analyze` sạch, 30/30 test pass.

## Lỗi theo mức độ

| Mức | Vấn đề | Trạng thái |
| --- | --- | --- |
| P0 | Không phát hiện lỗ hổng bảo mật hoặc lỗi mất dữ liệu nghiêm trọng. | — |
| P1 | Lịch sử local có 1 bản ghi hỏng thì toàn bộ lịch sử bị bỏ qua, lần lưu ván kế tiếp **ghi đè mất** dữ liệu cũ. | Đã sửa |
| P1 | Caro online tạo stream Realtime mới mỗi lần `setState` (mỗi lần bấm ô): đăng ký lại kênh, bàn cờ nháy về loading. | Đã sửa |
| P1 | Caro online: `start_caro_challenge` lỗi thì màn hình quay vòng mãi, không hiện lỗi hoặc nút thử lại. | Đã sửa |
| P1 | Không có timeout cho request mạng: mạng chập chờn làm nút "Đang xử lý…" và trạng thái `syncing` kẹt vô hạn. | Đã sửa (20 s) |
| P2 | Kết quả lưu khi đang đồng bộ bị bỏ qua tới lần kích hoạt sau; xóa lịch sử trong lúc sync gây `RangeError`. | Đã sửa |
| P2 | Ảnh puzzle PNG 3 × ~3 MB (9.4 MB) trong APK; thumbnail 56–64 px giải mã ảnh 1254 px. | Đã sửa |
| P2 | `results` lọc + sắp xếp lại ở mỗi lần đọc (nhiều lần mỗi lần build). | Đã cache |
| P2 | Mỗi lần refresh token đều kích hoạt sync và rebuild toàn app dù không có gì cần đồng bộ. | Đã sửa |
| P2 | Dependency `google_fonts` không dùng tới. | Đã gỡ |
| P2 | Release ký bằng khóa debug, không có đường cấu hình khóa thật. | Đã thêm `key.properties` |
| P2 | APK gộp 96.5 MB, chủ yếu do bảng tra của `cuber` (~18 MB `libapp.so`/ABI). | Đã ghi tài liệu split-per-abi/AAB |
| P3 | Sudoku hỏi "Rời ván?" khi đề còn đang tạo. | Đã sửa |
| P3 | Chữ cái avatar cắt đôi tên bắt đầu bằng emoji. | Đã sửa |
| P3 | Nút hiện/ẩn mật khẩu thiếu nhãn cho screen reader. | Đã sửa |
| P3 | Chưa có dark mode; nhiều màu hard-code ngoài `AppColors`. | Chưa làm (cần quyết định thiết kế) |
| P3 | `applicationId`/namespace còn `com.example.bakhi_gameapp`. | Chưa đổi (cần quyết định; đổi sau khi phát hành sẽ thành app khác) |
| P3 | `allowBackup` mặc định bật: Android backup gồm cả lịch sử và phiên Supabase. | Chưa đổi (đánh đổi tính năng/bảo mật) |
| P3 | 28–36 gói có bản mới hơn ngoài ràng buộc hiện tại. | Không nâng cấp (theo nguyên tắc không nâng major khi chưa đánh giá) |

## File đã sửa

| File | Lý do |
| --- | --- |
| `lib/data/app_store.dart` | Đọc lịch sử từng bản ghi + giữ bản gốc hỏng (`game_results_v1_unreadable_backup`); cache `results`; sync chạy thêm lượt khi có kết quả mới, bỏ qua khi không có gì; timeout 20 s cho mọi request; thông báo riêng cho timeout. |
| `lib/games/online_caro_page.dart` | Giữ một stream duy nhất; màn lỗi có nút thử lại. |
| `lib/games/sudoku_page.dart` | Không chặn thoát khi đề chưa tạo xong. |
| `lib/games/puzzle_page.dart`, `lib/ui/app_shell.dart` | Dùng ảnh JPEG; giải mã thumbnail theo kích thước hiển thị. |
| `lib/rubik/rubik_page.dart` | Ảnh xem lại khi sửa màu giải mã ở 180 px. |
| `lib/ui/community_page.dart` | Lấy ký tự đầu theo grapheme. |
| `lib/ui/profile_page.dart` | Tooltip cho nút hiện/ẩn mật khẩu. |
| `pubspec.yaml` | Gỡ `google_fonts`. |
| `assets/images/*.jpg` | Thay PNG bằng JPEG q88 cùng độ phân giải 1254×1254. PNG gốc chuyển sang `design/puzzle_source/` (không đóng gói, không xóa). |
| `android/app/build.gradle.kts` | Ký release từ `android/key.properties` nếu có, nếu không dùng khóa debug. |
| `test/regression_test.dart` | 6 test hồi quy mới. |
| `README.md` | Hướng dẫn build release, ký app, lưu ý anon key. |

## Kiểm thử

| Lệnh | Kết quả |
| --- | --- |
| `flutter doctor -v` | Đạt mọi mục. |
| `flutter pub get` | OK. |
| `dart format lib test` | 3 file được định dạng lại. |
| `flutter analyze` | Không có vấn đề (trước và sau). |
| `flutter test` | Trước: 30/30. Sau: **36/36**. 6 test mới đều fail khi chạy trên code gốc. |
| `npm test --prefix tool/backend_test` | Migration và 32 assertion pass (PGlite). |
| `flutter build apk --release` | Thành công. |
| `flutter build apk --release --split-per-abi` | Thành công: armeabi-v7a 29.7 MB, arm64-v8a 31.8 MB, x86_64 33.3 MB. |

Chưa làm: chạy trên thiết bị thật/máy ảo sau khi sửa, kiểm thử Supabase thật (Auth/Realtime qua mạng), build iOS (cần macOS).

## Trước / sau (đo thực tế)

| Chỉ số | Trước | Sau |
| --- | --- | --- |
| APK release gộp | 96.5 MB | 88.7 MB |
| Assets trong APK | 9.71 MB | 1.94 MB |
| Ảnh puzzle | 9.46 MB PNG | 1.70 MB JPEG |
| Bộ nhớ giải mã thumbnail thẻ game (DPR 3) | ~6.3 MB (1254² RGBA) | ~0.15 MB (192² RGBA, tính toán) |

## Cần người dùng cung cấp/phê duyệt

1. Keystore phát hành và `android/key.properties`.
2. `applicationId` chính thức (ví dụ `io.bakhi.gameapp`), phải chốt trước lần phát hành đầu tiên.
3. Có tắt `android:allowBackup` không (an toàn hơn cho phiên đăng nhập, nhưng mất lịch sử khi chuyển máy).
4. Có làm dark mode không: cần gom các màu hard-code vào `AppColors`/`ColorScheme` trước.
5. Thử các luồng online với dự án Supabase thật trên 2 thiết bị (chat, thách đấu Sudoku/Caro, đồng bộ điểm khi mất mạng).

## Bước tiếp theo

- [ ] Chạy thử trên Android thật: Caro online (không còn nháy khi đi), mất mạng khi đăng nhập/đồng bộ (báo lỗi sau ≤20 s).
- [ ] Cấu hình keystore, đổi `applicationId`, build `appbundle`.
- [ ] Đánh giá nâng cấp các gói minor (`supabase_flutter` 2.18.x, `image` 4.12, `camera`) và chạy lại toàn bộ test.
- [ ] Cân nhắc dark mode và gom design tokens.
- [ ] Thông báo đẩy cho lời mời thách đấu/chat (README đã ghi là chưa có).
