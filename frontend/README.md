# Bá Khí — Game Hub

- **Frontend (Flutter):** thư mục này (`frontend/`). Chạy mọi lệnh `flutter …` bên dưới từ đây.
- **Backend:** [`backend/`](../backend/) — Web API ASP.NET Core + PostgreSQL do nhóm tự viết, chạy trên VPS tại https://game.42-96-2-9.sslip.io/swagger. App chỉ nói chuyện với API này.

Ứng dụng Flutter cho học phần Lập trình trên thiết bị di động.

## Chức năng

| Module | Đã triển khai |
| --- | --- |
| Tài khoản | Đăng ký email/mật khẩu (báo đúng khi email đã có tài khoản), xác nhận bằng mã 6 số gửi qua email, đăng nhập (JWT), quên mật khẩu (mã qua email → màn đặt mật khẩu mới), đăng xuất, giữ phiên trên máy và tự gia hạn bằng refresh token |
| Sudoku | Dễ/vừa/khó chấm theo kỹ thuật giải (single / khóa ứng viên, cặp, bộ ba / nâng cao), đề duy nhất một lời giải, ghi chú, kiểm tra lỗi, đồng hồ, tính điểm |
| Xếp hình | Puzzle ảnh trượt ô: dễ 3×3, vừa 4×4, khó 5×5; 3 ảnh có sẵn hoặc chọn ảnh từ thư viện; xem ảnh mẫu và kiểm tra hoàn thành |
| Caro | Bàn 15×15; máy dễ đi ngẫu nhiên gần quân, vừa đánh giá thế cờ, khó tìm kiếm negamax alpha-beta 4 lớp (thắng ~71% trước mức vừa); luật chặn hai đầu; kiểm tra thắng/thua/hòa |
| Rubik | Quét 6 mặt 3×3, sửa màu, bộ giải offline, mô hình 3D xoay từng lớp theo lời giải. Là công cụ gợi ý giải nên không tính giờ, không tính điểm, không có bảng xếp hạng |
| Điểm | Lưu lịch sử trên máy, đồng bộ kết quả của tài khoản khi có mạng, gửi lại không trùng bản ghi |
| Xếp hạng | Kỷ lục cá nhân; online lấy kết quả tốt nhất mỗi người theo game và độ khó, chỉ tính ván được server ghi giờ và qua kiểm tra hợp lý; bằng điểm, giây và lỗi thì ai đạt trước xếp trên; ngoài top 50 vẫn thấy “Hạng của bạn” |
| Thách đấu | Mời/chấp nhận/từ chối thách đấu, người gửi hủy được lời mời còn chờ; hỗ trợ Sudoku và Caro online, xác định người thắng/hòa, đầu hàng, lời mời hết hạn sau 24 giờ, hạn hoàn thành 24 giờ, Caro online 60 giây mỗi lượt, tái đấu Caro |
| Chat | Nhắn tin riêng, cập nhật tức thì qua WebSocket, thông báo tin nhắn và lời mời mới, hiển thị 100 tin nhắn gần nhất của cuộc hội thoại; giới hạn 2000 ký tự tính đúng như database, báo lỗi rõ khi quá dài; bàn phím giữ mở khi gửi |

Game chơi được ở chế độ khách không cần mạng. **Đăng ký/đăng nhập, chat, thách đấu và xếp hạng online cần kết nối tới BaKhi_API.** Không có tài khoản hoặc cuộc hội thoại giả lập.

## Chạy nhanh

```sh
flutter pub get
flutter devices
flutter run -d <device-id>
```

App mặc định gọi API trên VPS (`https://game.42-96-2-9.sslip.io`), không cần file cấu hình hay khóa bí mật nào. Muốn dùng API chạy trên máy (máy ảo Android gọi máy tính qua `10.0.2.2`):

```sh
flutter run --dart-define=API_URL=http://10.0.2.2:5080
```

Android API 24 trở lên; iOS theo cấu hình hiện tại của project (15 trở lên). Build iOS cần macOS/Xcode. Camera cần thử trên thiết bị thật.

```sh
flutter build apk --debug
```

APK: `build/app/outputs/flutter-apk/app-debug.apk`.

### Bản release

```sh
flutter build apk --release --split-per-abi
flutter build appbundle --release
```

- Nên phát hành theo ABI (`--split-per-abi`, ~30 MB/APK) hoặc AAB thay vì APK gộp (~89 MB). Phần lớn dung lượng là bảng tra Kociemba của gói `cuber` được biên dịch vào mã Dart.
- Ký bản release: tạo keystore riêng rồi tạo `android/key.properties` (đã nằm trong `.gitignore`, không commit):

```properties
storeFile=../upload-keystore.jks
storePassword=...
keyAlias=upload
keyPassword=...
```

  `storeFile` tính từ thư mục `android/app`. Không có file này, bản release vẫn build được nhưng ký bằng khóa debug và chỉ dùng để thử.

## Kết nối backend

App không chứa khóa hay mật khẩu nào. Mọi dữ liệu online đi qua BaKhi_API ([`../backend/`](../backend/)):

- REST + JWT: đăng nhập trả về `access_token` (1 giờ) và `refresh_token` (30 ngày); `lib/data/api_client.dart` tự gia hạn khi token sắp hết hoặc bị từ chối, và lưu phiên trên máy.
- WebSocket `/ws`: nhận tin nhắn, lời mời và nước đi Caro ngay khi có thay đổi; mất kết nối thì tự nối lại (1, 2, 4 … 30 giây) và tải lại dữ liệu đang hiển thị.

## Điểm và luật chơi

`điểm = điểm_gốc × hệ_số × T / (T + giây)`, sau đó mỗi lỗi trừ 5% số điểm còn lại (× 19/20, làm tròn xuống); thắng tối thiểu 1 điểm, thua/hòa 0. T là thời gian chuẩn: giải đúng bằng T được một nửa điểm tối đa, chậm 3T được một phần tư. Công thức chỉ dùng số nguyên, giống hệt nhau ở `calculateScore` (app) và `game_score` (database, `backend/database/migrations/008_score_formula.sql`).

- Thời gian chuẩn T (Dễ/Vừa/Khó): Sudoku 600/900/1500 giây; Xếp hình 60/240/600 giây; Caro 120/240/360 giây.

- Điểm gốc: Sudoku 2000, Xếp hình 1500, Caro 1000.
- Hệ số Dễ/Vừa/Khó: 1/2/3.
- Sudoku: nhập số trùng với số đã có trong cùng hàng, cột hoặc khối 3×3 tính 1 lỗi và ô bị tô đỏ; mỗi số chỉ tính một lần cho mỗi ô, kể cả xóa rồi nhập lại; ghi chú không tính lỗi. App không so với đáp án nên không làm lộ đáp án; số sai nhưng chưa trùng chỉ lộ ra khi gây trùng về sau hoặc khi bảng đầy mà chưa đúng.
- Xếp hình: chạm ô không kề khoảng trống tính 1 lỗi. Dễ dùng 3×3, Vừa dùng 4×4, Khó dùng 5×5.
- Caro dùng luật Việt Nam: ít nhất 5 quân liên tiếp là thắng, trừ khi bị quân đối phương chặn cả hai đầu; mép bàn không tính là chặn. Áp dụng cho cả Caro với máy và Caro online (server kiểm tra). Không tính lỗi chiến thuật. Thua/hòa được 0 điểm.
- Rubik: là phần hướng dẫn giải khối thật (yêu cầu “gợi ý giải”), không phải thi đấu, nên không có đồng hồ, không tính lỗi, không tính điểm. Người dùng bấm “Đã xoay xong” theo tốc độ của mình.
- Ván đơn dừng đồng hồ khi tạm dừng hoặc app xuống nền. Ván chưa hoàn thành không tính điểm; rời ván đơn sẽ mất tiến độ.
- Lời mời chưa trả lời hết hạn sau 24 giờ. Sau khi chấp nhận có 24 giờ để thi đấu: Sudoku ai đã nộp thì thắng, chưa ai nộp thì hòa; Caro ai không vào trận thì thua. Caro online có 60 giây mỗi lượt (bắt đầu tính khi cả hai đã vào trận), hết giờ là thua. Hai bên đều có thể đầu hàng (Sudoku: trước khi nộp). Server chốt kết quả quá hạn mỗi khi người chơi thao tác; app của người đang chờ tự yêu cầu chốt khi đồng hồ lượt về 0.
- Thách đấu tính giờ liên tục trên server. Tiến độ Sudoku thách đấu và số lỗi được lưu trên cùng thiết bị để tiếp tục; ghi chú chưa được lưu. Đổi thiết bị không mang theo bản nháp nhưng đồng hồ server vẫn chạy.
- Thách đấu so điểm, rồi thời gian, rồi số lỗi; giống cả ba là hòa. Kết quả nằm trong Cộng đồng, không trộn vào xếp hạng chơi đơn.
- Lịch sử khách và từng tài khoản tách riêng. Điểm khách không tự chuyển sang tài khoản sau đăng nhập. Lịch sử trên máy hiển thị 50 ván mới nhất; bảng kỷ lục hiển thị 30 ván và online 50 người.

## Quét Rubik

### Làm theo hướng dẫn 3D

Sau khi quét và xác nhận đủ sáu mặt, mở lời giải để xem khối 3D theo đúng màu đã nhập. Giữ khối thật theo màu tâm trước/trên được ghi trên màn hình.

- Bấm **Xem cách xoay** để minh họa nước hiện tại; có thể tạm dừng, xem lại và chọn tốc độ chậm/thường.
- Kéo khối 3D để xem các mặt. **Góc ban đầu** đưa góc nhìn và hình minh họa về trước nước xoay.
- Xoay khối thật rồi bấm **Đã xoay xong** để chuyển bước. Xem minh họa không tự tăng bước hoặc điểm.
- **Bước trước** lùi hướng dẫn; nếu đã thực hiện trên khối thật thì phải tự hoàn tác nước đó.
- Khi hệ thống bật giảm chuyển động, nút xem chuyển trực tiếp giữa trước/sau nước xoay.

Mô hình được vẽ bằng Flutter CustomPainter với tọa độ 3D, không cần tải mô hình hoặc thêm gói pub.dev. Chuyển động 18 nước U/R/F/D/L/B, nước ngược và nước kép được kiểm thử đối chiếu với `cuber`. Bản 3D mới cần được thử thêm với khối thật; kiểm thử camera trước đây không thay thế kiểm thử luồng 3D này.

### Chụp sáu mặt

1. Cầm tâm xanh lá ở trước và tâm trắng ở trên; tâm đỏ bên phải, cam bên trái, xanh dương phía sau và vàng ở dưới.
2. Quét lần lượt theo màu tâm: **Trắng, Đỏ, Xanh lá, Vàng, Cam, Xanh dương**. Chỉ xoay cả khối, không vặn tầng trong lúc quét.
3. Cạnh trên ảnh phải giáp màu tâm: **Trắng→Xanh dương, Đỏ→Trắng, Xanh lá→Trắng, Vàng→Xanh lá, Cam→Trắng, Xanh dương→Trắng**.
4. Đặt mặt khối thẳng camera và vừa khung trắng. Kiểm tra/sửa cả 9 ô, kể cả tâm; có nút xoay lưới.
5. Khi giải, cầm lại tâm xanh lá ở trước, tâm trắng ở trên. Ký hiệu U/R/F/D/L/B chỉ dùng trong công thức; chiều xoay tính khi nhìn thẳng vào mặt đang xoay.

Nhận diện màu dùng HSV và trung vị vùng giữa ô, chưa tự tìm góc hoặc hiệu chỉnh phối cảnh. Cần đủ sáng và tránh phản chiếu. Bộ giải Kociemba (`cuber`) có giới hạn tìm kiếm 20 giây/24 bước và xác minh lời giải bằng cách áp lại các nước đi. Ảnh không gửi lên server.

## Cấu trúc

```text
lib/
  main.dart              # Khởi tạo ApiClient và AppStore
  data/api_client.dart   # Gọi BaKhi_API: REST + JWT, WebSocket realtime
  data/app_store.dart    # Tài khoản, dữ liệu local, đồng bộ, cộng đồng
  data/chat_notifier.dart # Thông báo tin nhắn và lời mời
  games/                 # Logic thuần Dart, màn hình và đồng hồ game
  rubik/                 # Camera, nhận diện và giải Rubik
  ui/                    # Hub, tài khoản, xếp hạng, cộng đồng và chat
assets/images/           # Ảnh puzzle JPEG được đóng gói
design/puzzle_source/    # Ảnh PNG gốc (không đóng gói)
test/                    # Unit/widget tests
```

Backend (Web API, SQL của database, test) nằm ở [`../backend/`](../backend/).

## Kiểm tra

```sh
flutter analyze
flutter test
flutter build apk --debug
npm ci --prefix ../backend/database/tests
npm test --prefix ../backend/database/tests
```

Backend test thực thi migration trên PostgreSQL nhúng (PGlite), kiểm tra RLS, quyền gửi/đọc chat, điểm sinh ở database, chặn ghi điểm trực tiếp và điểm phi lý, trạng thái thách đấu, gửi lại kết quả và thông báo realtime. `backend/database/tests/api.mjs` kiểm thử end-to-end API đang chạy (đăng ký bằng mã, JWT, WebSocket, Caro online, chat), xem [`../backend/README.md`](../backend/README.md).

### Đã kiểm thử thực tế

- Quét Rubik bằng camera trên điện thoại Android thật: hoạt động.
- Chat realtime giữa một điện thoại Android thật và một máy ảo Android: gửi và nhận tin nhắn thành công (bản dùng Supabase trước đây; bản WebSocket mới đã kiểm thử end-to-end và trên máy ảo).

## Giới hạn cần biết khi báo cáo

- Chưa kiểm thử bản build iOS trên iPhone thật; cần macOS/Xcode để build và cài lên iOS.
- Điểm chơi đơn: client không ghi thẳng vào bảng được. Server ghi giờ bắt đầu ván (`start_game_session`) và chỉ xếp hạng kết quả có phiên hợp lệ, thời gian không dài hơn thời gian server đo, không nhanh hơn mức tối thiểu của từng game (Sudoku 60/90/120 giây, xếp hình 5/15/30 giây, Caro 5 giây, Rubik 2 giây/bước) và đủ số nước. Ván chơi khi offline hoặc khách vẫn lưu trên máy nhưng không lên bảng online. Số lỗi vẫn do client báo, nên đây là chặn điểm phi lý chứ không phải chống gian lận tuyệt đối. Với thách đấu, server kiểm tra đề/đáp án và thời gian, còn số lỗi do client báo.
- Độ khó Sudoku chấm bằng `gradeSudoku` (giải như người): Dễ chỉ cần naked/hidden single; Vừa cần thêm khóa ứng viên (pointing/claiming), naked pair/triple, hidden pair; Khó là khi các kỹ thuật đó không đủ (cần X-wing, chuỗi hoặc thử sai). Đề Dễ giữ 38 ô gợi ý; đề Vừa/Khó dừng đục ô ngay khi đạt đúng bậc nên số ô gợi ý không quyết định độ khó. Thách đấu chọn ngẫu nhiên 1 trong 6 đề cùng mức (chấm bằng cùng thang, xem `007_graded_sudoku.sql`) rồi hoán vị chữ số ngẫu nhiên. Chưa có kỹ thuật cao hơn trong bộ chấm, nên mức Khó gộp mọi đề từ X-wing trở lên.
- Giao diện cố ý chỉ có chế độ sáng (`themeMode: ThemeMode.light`): bàn cờ, ô Sudoku, sticker Rubik dùng màu cố định cho nền sáng. Bật dark mode của hệ thống không làm đổi giao diện.
- Thông báo chỉ đến khi app đang mở hoặc chạy nền (chưa có push khi app bị tắt hẳn); chat chưa có trạng thái đã đọc hoặc tệp đính kèm. Danh sách cộng đồng hiện lấy tối đa 100 người.
- Dữ liệu local dùng SharedPreferences, không phải kho dữ liệu quan trọng có bảo đảm giao dịch. Phiên quét Rubik không lưu khi đóng app.
- Chưa cấu hình khóa ký phát hành; APK debug dùng cho kiểm thử học phần.

Tham khảo chính thức: [http](https://pub.dev/packages/http), [web_socket_channel](https://pub.dev/packages/web_socket_channel), [PostgreSQL RLS](https://www.postgresql.org/docs/current/ddl-rowsecurity.html), [Camera](https://pub.dev/packages/camera), [Cuber](https://pub.dev/packages/cuber).
