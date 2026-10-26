# Báo cáo QA đồ án “Bá Khí Game Hub”

Ngày rà soát: 25/10/2026. Người rà soát đóng vai Senior QA kiêm giảng viên chấm đồ án.

## 0. Phạm vi và cách kiểm chứng

| Hạng mục | Thông tin xác định từ source |
| --- | --- |
| Nền tảng | Android (minSdk 24, đã chạy trên máy thật theo README). iOS **ngoài phạm vi** (đề không yêu cầu nộp bản iOS). |
| State management | `ChangeNotifier` (`AppStore`) + `ListenableBuilder` + `setState`. |
| Backend | Supabase: Auth (email/mật khẩu, xác nhận email qua deep link), Postgres + RLS + RPC `security definer`, Realtime. Lịch sử local bằng `SharedPreferences`. |
| Thuật toán | Rubik: Kociemba (gói `cuber`), chạy trong `compute`. Sudoku: backtracking MRV + đục ô giữ nghiệm duy nhất. Caro: heuristic 1 lớp (Vừa) / “2 lớp” rút gọn (Khó), **không phải minimax/alpha-beta**. Xếp hình: puzzle ảnh trượt 3×3/4×4/5×5. |

Những gì **đã thực sự chạy**:

- `flutter analyze`: không có lỗi. `flutter test`: **36/36 pass**.
- Ba script probe chạy trực tiếp trên engine thật (không sửa source), lưu tại
  `C:\Users\davi\AppData\Local\Temp\claude\D--FlutterProjects-bakhi-gameapp\2de081ab-44dc-40e5-b5ec-1a8292131430\scratchpad\probe.dart`, `probe2.dart`, `probe3.dart`.
  Kết quả được trích ở mục 4.0.

Những gì **chưa kiểm chứng được** (đánh dấu “Cần bổ sung”): luồng Supabase thật qua mạng (Auth/Realtime/RLS trên project thật), chạy trên thiết bị sau các thay đổi gần nhất, camera.

### Thay đổi đã thực hiện sau vòng hỏi đáp

| Thay đổi | File | Kiểm chứng |
| --- | --- | --- |
| Caro dùng **luật Việt Nam chặn hai đầu**: ≥5 quân liên tiếp thắng, trừ khi bị quân đối phương chặn cả hai đầu; mép bàn không tính là chặn; 6 quân trở lên vẫn thắng nếu còn một đầu không bị chặn. AI không còn coi 5 quân bị chặn hai đầu là nước thắng/đe dọa. | `lib/games/caro_engine.dart` (`hasFive`, `_potential`) | 2 test mới trong `test/game_engines_test.dart`; `flutter test` 38/38 pass |
| Caro online áp dụng cùng luật ở server | `supabase/migrations/004_caro_vietnam_rule.sql` (mới, thay `play_caro_move`) | Thêm kịch bản chặn hai đầu vào `tool/backend_test/test.mjs`; 42 assertion pass |
| Cập nhật mô tả luật trong app và tài liệu | `caro_page.dart`, `online_caro_page.dart`, `README.md`, `docs/SUPABASE_SETUP.md` | `flutter analyze` sạch |
| **BUG-01 đã sửa:** rút quyền ghi thẳng vào `game_results`. Server mở phiên khi ván bắt đầu (`start_game_session`); kết quả gửi qua `submit_game_result` chỉ được xếp hạng khi có phiên hợp lệ, chưa dùng, đúng game; thời gian khai báo ≤ thời gian server đo + 30 giây và ≥ mức tối thiểu của game; đủ số nước. Ván chơi offline vẫn lưu, đồng bộ được nhưng không xếp hạng; lịch sử ghi “không xếp hạng”. | `supabase/migrations/005_verified_results.sql` (mới), `app_store.dart`, `game_models.dart`, `game_widgets.dart`, 4 màn chơi đơn, `profile_page.dart`, `leaderboard_page.dart` | 17 kịch bản mới trong backend test (insert trực tiếp, không phiên, khai giờ dài hơn server, dùng lại phiên, phiên của người khác, phiên sai game, quá nhanh, thiếu nước, Rubik bấm cho xong, anon); 59 assertion pass |
| **BUG-02 đã sửa:** mức Khó dùng negamax alpha-beta 4 lớp (12/10/8/6 nhánh) + kiểm tra nước thắng ở lá. Hàm lượng giá chấm từng cửa sổ 5 ô, hiểu luật chặn hai đầu, cập nhật cộng dồn. Mức Dễ, Vừa giữ nguyên. | `lib/games/caro_engine.dart` (`_Search`, `_window`, `_around`) | 200 ván: Khó thắng **142 (71%)**, Vừa thắng 27; Khó thắng Dễ 200/200. Thời gian nghĩ trên PC: trung bình 23 ms, p95 61 ms, tối đa 161 ms (chạy trong `compute`). 2 test mới; `flutter test` 40/40 pass |
| **BUG-05 đã sửa:** lời mời hết hạn sau 24 giờ; sau khi chấp nhận có 24 giờ (Sudoku: ai đã nộp thắng, không ai nộp hòa; Caro: ai không vào trận thua); Caro online 60 giây mỗi lượt khi cả hai đã vào trận, hết giờ thua; đầu hàng cho cả hai game; app hiện hạn, đếm ngược, lý do kết thúc, hỏi lại khi rời trận đang chơi. Sửa kèm BUG-16 (RPC Sudoku từ chối thử thách Caro). | `supabase/migrations/006_challenge_deadlines.sql` (mới), `app_store.dart`, `community_page.dart`, `sudoku_page.dart`, `online_caro_page.dart` | 23 assertion backend mới (hết hạn, nộp quá hạn, hòa khi không ai nộp, đầu hàng, đầu hàng sau khi nộp bị chặn, người ngoài bị chặn, đồng hồ chỉ chạy khi cả hai vào, nước đi quá giờ bị xử thua, không vào trận bị xử thua, anon bị chặn) → 85 assertion pass (gồm 3 assertion cho BUG-16); 4 widget test mới → `flutter test` 44/44 pass |
| **BUG-03 đã sửa:** độ khó chấm theo kỹ thuật bằng `gradeSudoku` (Dễ: naked/hidden single; Vừa: thêm pointing/claiming, naked pair/triple, hidden pair; Khó: các kỹ thuật đó không đủ). Bộ sinh đề chỉ nhận đề đúng bậc; lưới đáp án sinh ngẫu nhiên thay cho công thức mẫu cố định. Đề thách đấu: 18 đề đã chấm (6/mức), chọn ngẫu nhiên + hoán vị chữ số đầy đủ. Bộ đếm nghiệm chuyển sang mặt nạ bit, nhanh ~20 lần. | `lib/games/sudoku_engine.dart`, `supabase/migrations/007_graded_sudoku.sql` (mới), `sudoku_page.dart` | 1000 đề/mức: 0 đề sai bậc. Bộ giải độc lập chỉ dùng single giải được Dễ 100/100, Vừa **0/100** (trước 95), Khó **0/100** (trước 74). AI Escargot chấm Khó; 3 đề thách đấu cũ đều chấm Dễ. Thời gian tạo đề trên PC: Vừa tối đa 116 ms, Khó tối đa 62 ms. 3 test Dart mới (chấm lại chính file SQL) + 8 assertion backend → 46/46 và 93 pass |
| **BUG-06 đã sửa:** đăng ký email đã có tài khoản giờ báo “Email này đã được sử dụng. Hãy đăng nhập, hoặc bấm “Quên mật khẩu?”…”. Khi bật Confirm email, Supabase trả về một user giả không có `identities`; app nhận ra điều này qua `isExistingAccount`. | `lib/data/app_store.dart` | Unit test với user không/có identity |
| **BUG-07 đã sửa:** nút “Quên mật khẩu?” gửi email đặt lại; thông báo không tiết lộ email có tồn tại hay không. Mở link → sự kiện `passwordRecovery` → `AuthGate` hiện màn “Đặt mật khẩu mới” (≥8 ký tự, nhập lại, nút Để sau). Link hết hạn, đã dùng hoặc mở trên máy khác (PKCE) → form đăng nhập báo lỗi riêng. Thêm thông báo cho `same_password`. | `app_store.dart`, `profile_page.dart` (`NewPasswordPage`), `app_shell.dart` | 4 test mới (nhận diện lỗi link, quên mật khẩu, màn mật khẩu mới) → `flutter test` 50/50. **Chưa thử với email thật** |
| **BUG-08 đã sửa:** bỏ sàn 100 điểm. Công thức mới `gốc × hệ_số × T / (T + giây)`, mỗi lỗi −5% số điểm còn lại; T là thời gian chuẩn từng game/mức (Sudoku 10/15/25 phút, Xếp hình 1/4/10, Caro 2/4/6, Rubik 3). Chỉ dùng số nguyên nên app và database luôn ra cùng một số. Migration tính lại điểm đã lưu. | `lib/games/game_models.dart`, `supabase/migrations/008_score_formula.sql` (mới), lời giải thích điểm trong `app_shell.dart`, `sudoku_page.dart`, `puzzle_page.dart` | 5.000 bộ input ngẫu nhiên: **0 chỗ lệch** giữa Dart và SQL. Ví dụ BUG-08: 1000 giây 0 lỗi = 750, 990 giây 30 lỗi = 153 (trước: cùng 100). Test đơn điệu theo thời gian/lỗi cho mọi game/mức; 6 assertion backend mới → 50/50 và 99 pass |
| **Lượt sửa cuối (R3, BUG-09–12, 14, 17–20 + 2 lỗi mới):** Sudoku chỉ tô đỏ và tính lỗi khi trùng hàng/cột/khối, mỗi số tính một lần cho mỗi ô, báo khi bảng đầy mà chưa đúng (R3, BUG-11). Chat kiểm độ dài theo code point và báo lỗi (BUG-09), giữ bàn phím (BUG-10, BUG-22). Ảnh mẫu xếp hình cắt vuông như mảnh ghép (BUG-12). Xếp hạng: bằng điểm thì ai đạt trước xếp trên, có “Hạng của bạn” khi ngoài top 50 (BUG-14, 19), sửa luôn lỗi bảng online không hiện trên bản debug (BUG-21). Caro tô sáng 5 quân thắng (BUG-20). Email có dấu bị chặn ngay ở form, mật khẩu mới phải có chữ và số (BUG-18, TC-AUTH-07). Ghi rõ app chỉ có giao diện sáng (BUG-17). | `sudoku_page.dart`, `community_page.dart`, `puzzle_page.dart`, `leaderboard_page.dart`, `app_store.dart`, `caro_engine.dart`, `caro_page.dart`, `online_caro_page.dart`, `profile_page.dart`, `main.dart`, `supabase/migrations/010_leaderboard_rank.sql` (mới) | 8 test mới (Sudoku đếm lỗi, chat, ảnh mẫu, xếp hạng ×2, đường thắng, form đăng ký) + 6 assertion backend → `flutter test` 59/59, 114 assertion pass |
| **TC-CHL-08 đã sửa:** người gửi hủy được lời mời còn chờ (nút “Hủy lời mời”, có hỏi xác nhận). Lời mời giữ lại với trạng thái `cancelled` để cả hai máy cập nhật qua Realtime và hiện “Người gửi đã hủy”. Nếu người nhận bấm Chấp nhận cùng lúc, khóa dòng của Postgres đảm bảo chỉ một thao tác thành công. | `supabase/migrations/009_cancel_challenge.sql` (mới), `app_store.dart`, `community_page.dart` | 9 assertion backend mới (người nhận/người ngoài không hủy được, hủy rồi không chấp nhận được, đã chấp nhận thì không hủy được, anon bị chặn) → 108 pass; widget test mới `test/community_test.dart` → `flutter test` 52/52 |
| **BUG-04 đã sửa hết:** ngoài ngưỡng server ở migration 005, nút “Đã xoay xong” giờ mở sau ít nhất 2 giây mỗi bước. Thời gian đo trên đồng hồ ván, chính xác tới mili giây và không tính lúc tạm dừng, nên tổng thời gian luôn ≥ 2 giây × số bước = đúng ngưỡng `min_game_seconds`. “Bước trước” cũng bắt đầu lại 2 giây; sau khi đã ghi kết quả thì xem lại thoải mái. Sửa kèm **BUG-13**: khi tạm dừng nút ghi “Đang tạm dừng” và bị khóa. | `lib/rubik/solution_page.dart`, `GameClock.elapsed` trong `game_widgets.dart` | 1 widget test mới (khóa → mở sau 2 giây → khóa lại ở bước sau → tạm dừng) → `flutter test` 51/51. Lời giải 20 bước giờ nhanh nhất 40 giây = 818 điểm (trước: 10 giây = 947–980) |

**Việc bạn phải làm:** mở SQL Editor của project Supabase thật, chạy lần lượt `004_caro_vietnam_rule.sql`, `005_verified_results.sql`, `006_challenge_deadlines.sql`, `007_graded_sudoku.sql`, `008_score_formula.sql`, `009_cancel_challenge.sql`, `010_leaderboard_rank.sql`. Nếu chưa chạy 008, điểm trên bảng online (database tính) sẽ khác điểm hiện trong app. Nếu chưa chạy 007, đề thách đấu vẫn là 3 đề cũ (đều mức Dễ) và ván Sudoku Vừa/Khó ít ô gợi ý có thể bị server coi là "thiếu nước" khi xếp hạng. Nếu chưa chạy 006, nút Đầu hàng và đồng hồ lượt sẽ báo lỗi vì hàm chưa có. Nếu chưa chạy 004, Caro online vẫn dùng luật cũ trong khi Caro với máy đã dùng luật mới. Nếu chưa chạy 005, app bản mới sẽ **không đồng bộ được kết quả**, vì hàm `submit_game_result` chưa có. Sau khi chạy 005, các kết quả cũ không còn trên bảng xếp hạng (không xác minh được); hãy chơi lại vài ván để có dữ liệu demo. Phần đồng bộ mới phía app mới chỉ kiểm chứng qua backend test, **chưa chạy với Supabase thật**: hãy thử chơi 1 ván khi đăng nhập rồi xem bảng Online.

Các test case ở mục 2 là kịch bản để bạn chạy; cột “Kết quả mong đợi” là chuẩn chấm, không phải kết quả đã chạy, trừ những dòng ghi rõ “(đã kiểm chứng)”.

---

## 1. Bước 1 – Ma trận truy vết yêu cầu (RTM)

| # | Yêu cầu đề bài | Chức năng trong app | File chính | Trạng thái | Ghi chú (có thể kiểm chứng) |
| --- | --- | --- | --- | --- | --- |
| 1 | Đăng ký / đăng nhập (2đ) | Đăng ký email + mật khẩu + tên, xác nhận email, đăng nhập, quên mật khẩu, đăng xuất, giữ phiên, chế độ khách | `lib/ui/profile_page.dart`, `lib/data/app_store.dart`, `lib/ui/app_shell.dart` | **Đạt** | BUG-06 và BUG-07 đã sửa. Còn: chính sách mật khẩu chỉ yêu cầu độ dài ≥8 (TC-AUTH-07), email có dấu bị báo lỗi chung chung (BUG-18). |
| 2a | Rubik: gợi ý giải (2đ) | Quét 6 mặt bằng camera / nhập tay, kiểm tra hợp lệ, giải Kociemba, xác minh lời giải, mô hình 3D từng bước | `lib/rubik/*` | **Đạt** | Đã kiểm chứng: lật cạnh, xoay góc, hoán vị lẻ, góc không tồn tại, sai số màu đều bị từ chối với `FormatException`; khối đã giải → 0 bước. BUG-04 đã sửa: mỗi bước tối thiểu 2 giây, không còn “bấm cho xong”. Lỗi xoay sai vẫn do người chơi tự khai. |
| 2b | Sudoku: chọn mức độ khó (2đ) | 3 mức chấm theo kỹ thuật giải, đề duy nhất 1 lời giải, ghi chú, đếm lỗi theo luật, đồng hồ | `lib/games/sudoku_engine.dart`, `sudoku_page.dart` | **Đạt** | BUG-03 đã sửa (độ khó theo kỹ thuật, thách đấu cùng thang). R3 + BUG-11 đã sửa: chỉ tô đỏ và tính lỗi khi trùng hàng/cột/khối, không còn lộ đáp án. |
| 2c | Xếp hình (1đ) | Puzzle ảnh trượt, 3 kích thước, ảnh có sẵn hoặc ảnh thư viện | `lib/games/puzzle_engine.dart`, `puzzle_page.dart` | **Đạt** | Xáo trộn bằng nước đi hợp lệ nên luôn giải được. BUG-12 đã sửa: ảnh mẫu cắt vuông như mảnh ghép. Chạm ô không kề tính lỗi là lựa chọn thiết kế (R16). |
| 2d | Caro với máy, chọn độ khó (1đ) | Bàn 15×15, luật Việt Nam chặn hai đầu (mới cài), 3 mức | `lib/games/caro_engine.dart`, `caro_page.dart` | **Đạt** | Điều kiện thắng 4 hướng, mép bàn và chặn hai đầu đều đúng. Sau khi sửa BUG-02: mức Khó (negamax alpha-beta) thắng 71% số ván trước mức Vừa, và khi cả hai bên có 3 mở thì máy đi nước tạo 4 mở để thắng. |
| 3 | Tính điểm theo thời gian và số lỗi (1đ) | `gốc × hệ_số × T / (T + giây)`, mỗi lỗi −5%; T theo game/mức; DB tính lại bằng cùng công thức | `lib/games/game_models.dart`, SQL `game_score` (migration 008) | **Đạt** | BUG-08 đã sửa: không còn sàn 100, client = DB trên 5.000 input. Đồng hồ dừng đúng khi tạm dừng/xuống nền. Còn: Caro không có lỗi tự nhiên (luôn 0); lỗi Rubik do người chơi tự khai. |
| 4 | Xem xếp hạng người chơi (2đ) | Kỷ lục cá nhân (local) + online top 50 theo game/độ khó, mỗi người 1 dòng tốt nhất, hạng của mình | `lib/ui/leaderboard_page.dart`, view `leaderboard`, `my_leaderboard_rank` | **Đạt** | BUG-01 (điểm giả), BUG-14 (bằng điểm), BUG-19 (hạng của mình), BUG-21 (bảng online không hiện trên bản debug) đã sửa. Số lỗi vẫn do client khai. |
| 5 | Thách đấu (bắt buộc, đề không ghi điểm) | Mời/chấp nhận/từ chối; Sudoku cùng đề (server tính giờ, kiểm đáp án); Caro online theo lượt, tái đấu | `lib/ui/community_page.dart`, `online_caro_page.dart`, SQL 001/002 | **Đạt** | BUG-05 đã sửa: lời mời hết hạn 24 giờ, hạn thi đấu 24 giờ, Caro 60 giây mỗi lượt, đầu hàng. Đã thêm hủy lời mời (TC-CHL-08). Còn: số lỗi Sudoku do client khai (BUG-15). |
| 6 | Chat với người khác (bắt buộc, đề không ghi điểm) | Chat 1-1 realtime, 100 tin gần nhất, gửi lại không trùng | `lib/ui/community_page.dart` (`ChatPage`) | **Đạt** | BUG-09, BUG-10, BUG-22 đã sửa. Chưa có thông báo đẩy, trạng thái đã đọc. |

### Điểm mơ hồ của đề và cách hiểu hợp lý nhất

| Điểm mơ hồ | Cách hiểu đề xuất | App đang làm |
| --- | --- | --- |
| Tổng điểm 1+2+3+4 = **11đ**, mục 5 và 6 **không có điểm** | Đã xác nhận: 5 và 6 là **yêu cầu bắt buộc**. Thiếu sót ở đây có thể bị trừ vào tổng hoặc làm mất điểm các mục liên quan (xếp hạng, tính điểm), nên phải coi như yêu cầu có điểm. | Làm đủ cả 6 mục. |
| “Giải các game” | Rubik: app **gợi ý** lời giải cho khối thật; các game còn lại: người chơi tự giải. | Đúng cách hiểu này. |
| “Xếp hình” | Nhóm xác nhận: puzzle ảnh trượt là đúng yêu cầu. | Puzzle ảnh trượt 3×3/4×4/5×5. |
| “Số lỗi phạm” với Caro và Rubik | Caro không có “lỗi” tự nhiên → nên dùng số nước đi làm tiêu chí thay thế. Rubik: lỗi = số lần làm sai (khó đo tự động). | Caro = 0 lỗi; Rubik = người chơi tự bấm “Ghi nhận lỗi”. |
| “Mức độ khó” Sudoku | Khác biệt về **kỹ thuật giải cần dùng**, không chỉ số ô gợi ý. | Chỉ số ô gợi ý (README đã thừa nhận). |
| Luật Caro (chặn hai đầu, 6 quân) | Đề không yêu cầu; nhóm chọn luật Việt Nam. | Đã chuyển sang chặn hai đầu (mép bàn không tính là chặn, 6+ quân vẫn thắng nếu còn một đầu mở), ghi rõ trên màn hình. |
| “Xếp hạng của người chơi” | Bảng giữa nhiều người, theo từng game và độ khó. | Có, online top 50. |

---

## 2. Bước 2 – Test case

Quy ước loại test: Positive, Negative, Boundary, Edge, Security, Concurrency, Performance, UI. Ưu tiên: Cao / TB / Thấp.

### 2.1 Đăng ký / đăng nhập

| Mã TC | Chức năng | Tiêu đề | Điều kiện tiên quyết | Các bước | Dữ liệu test | Kết quả mong đợi | Ưu tiên | Loại test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| TC-AUTH-01 | Đăng ký | Đăng ký hợp lệ | App có cấu hình Supabase, email chưa dùng | 1) Tab Đăng ký 2) Nhập đủ 4 trường 3) Bấm Tạo tài khoản | Tên “Nguyễn Văn An”, email mới, mật khẩu `Abc@12345` | Báo mở email xác nhận; email đến; bấm link mở app và đăng nhập được | Cao | Positive |
| TC-AUTH-02 | Đăng ký | Email sai định dạng | – | Nhập email rồi bấm Tạo tài khoản | `abc`, `abc@`, `a@b`, `a b@c.com`, `@c.com` | Lỗi “Email chưa hợp lệ.” ngay trên ô, không gửi request | Cao | Negative |
| TC-AUTH-03 | Đăng ký | Khoảng trắng đầu/cuối email | – | Nhập email có khoảng trắng | `  user@mail.com  ` | Email được trim, đăng ký/đăng nhập thành công | TB | Edge |
| TC-AUTH-04 | Đăng ký | Email tiếng Việt có dấu | – | Nhập email có dấu | `nguyễn@gmail.com` | Form báo “Email chưa hợp lệ (không dùng chữ có dấu…)”, không gửi request (đã sửa BUG-18, có widget test) | Thấp | Edge |
| TC-AUTH-05 | Đăng ký | Email đã tồn tại | Đã có tài khoản đã xác nhận | Đăng ký lại cùng email | email đã dùng | Báo “Email này đã được sử dụng. Hãy đăng nhập, hoặc bấm “Quên mật khẩu?”…”, không có email nào được gửi (đã sửa BUG-06; cần thử trên Supabase thật có bật Confirm email) | Cao | Negative |
| TC-AUTH-06 | Đăng ký | Biên độ dài mật khẩu | – | Nhập mật khẩu các độ dài | rỗng, 7 ký tự, 8 ký tự | Rỗng/7: “Mật khẩu cần ít nhất 8 ký tự.”; 8: chấp nhận | Cao | Boundary |
| TC-AUTH-07 | Đăng ký | Mật khẩu yếu | – | Đăng ký với mật khẩu chỉ có chữ hoặc chỉ có số | `abcdefgh`, `12345678` | Form báo “cần ít nhất 8 ký tự, gồm cả chữ và số” (có widget test). Nên bật thêm yêu cầu tương tự trong Supabase để chặn cả request gửi thẳng | TB | Negative |
| TC-AUTH-08 | Đăng ký | Nhập lại mật khẩu không khớp | – | Nhập 2 mật khẩu khác nhau | `Abc@12345` / `Abc@12346` | “Hai mật khẩu chưa giống nhau.” | TB | Negative |
| TC-AUTH-09 | Đăng ký | Biên tên hiển thị | – | Nhập tên các độ dài | 1 ký tự, 2, 40, 41, chỉ khoảng trắng, `Ánh 😀` | 1 ký tự/khoảng trắng: báo lỗi; 2–40: OK; 41: bị chặn nhập; tiếng Việt và emoji hiển thị đúng ở Cộng đồng/Xếp hạng | TB | Boundary |
| TC-AUTH-10 | Đăng nhập | Đăng nhập đúng | Tài khoản đã xác nhận | Nhập email, mật khẩu, bấm Đăng nhập | hợp lệ | Vào Hub, header hiện tên hiển thị | Cao | Positive |
| TC-AUTH-11 | Đăng nhập | Sai mật khẩu | Tài khoản tồn tại | Nhập sai mật khẩu | `sai12345` | “Email hoặc mật khẩu chưa đúng.”, không lộ email có tồn tại hay không | Cao | Negative |
| TC-AUTH-12 | Đăng nhập | Sai mật khẩu liên tục | – | Bấm Đăng nhập sai 30 lần | – | Sau ngưỡng: “Bạn thao tác quá nhanh…”, app không treo/crash | TB | Security |
| TC-AUTH-13 | Đăng nhập | Chưa xác nhận email | Vừa đăng ký, chưa bấm link | Đăng nhập | – | “Hãy xác nhận email trước khi đăng nhập.” + nút “Gửi lại email xác nhận” | TB | Negative |
| TC-AUTH-14 | Đăng nhập | Mật khẩu có khoảng trắng cuối | Mật khẩu thật `Abc@12345` | Nhập `Abc@12345 ` | – | Sai mật khẩu (mật khẩu không bị trim – đúng); thông báo rõ ràng | Thấp | Edge |
| TC-AUTH-15 | Phiên | Giữ phiên khi tắt mở app | Đã đăng nhập | Kill app (vuốt khỏi recent) rồi mở lại | – | Vào thẳng Hub, không hỏi đăng nhập | Cao | Positive |
| TC-AUTH-16 | Phiên | Back sau đăng xuất | Đã đăng nhập, ở tab Tài khoản | 1) Đăng xuất 2) Bấm Back hệ thống | – | Ở màn đăng nhập hoặc thoát app; **không** quay lại Hub/Cộng đồng | Cao | Security |
| TC-AUTH-17 | Đăng nhập | Mất mạng khi đăng nhập | Bật chế độ máy bay | Bấm Đăng nhập | – | ≤20 giây hiện “Không kết nối được máy chủ đăng nhập…”, nút bật lại | Cao | Negative |
| TC-AUTH-18 | Đăng nhập | Mạng rất chậm | Throttle 2G/100% loss | Bấm Đăng nhập | – | Timeout 20 giây → “Máy chủ phản hồi quá lâu…” | TB | Edge |
| TC-AUTH-19 | Đăng nhập | Bấm liên tục | – | Bấm Đăng nhập 5 lần thật nhanh | – | Chỉ 1 request (nút disable khi “Đang xử lý…”) | TB | Edge |
| TC-AUTH-20 | Quên mật khẩu | Gửi email đặt lại | Tài khoản tồn tại | 1) Nhập email ở form đăng nhập 2) Bấm “Quên mật khẩu?” | email đã đăng ký | Báo “Nếu email này đã đăng ký, thư đặt lại… sẽ đến”; email đến (đã sửa BUG-07) | Cao | Positive |
| TC-AUTH-20b | Quên mật khẩu | Chưa nhập email / email lạ | – | Bấm “Quên mật khẩu?” với ô Email trống, rồi với email chưa đăng ký | `''`, `khongco@example.com` | Ô trống: nhắc nhập email, không gửi request (có widget test). Email lạ: cùng câu trả lời như email thật, không lộ tài khoản | Cao | Security |
| TC-AUTH-20c | Quên mật khẩu | Mở link và đặt mật khẩu mới | Đã nhận email | Mở link trên cùng điện thoại → nhập mật khẩu mới 2 lần → Lưu → đăng xuất → đăng nhập bằng mật khẩu mới | `mat-khau-moi-1` | Mở link thì vào màn “Đặt mật khẩu mới”; sau khi lưu thì vào Hub; mật khẩu cũ không còn dùng được | Cao | Positive |
| TC-AUTH-20d | Quên mật khẩu | Mật khẩu mới không hợp lệ | Đang ở màn mật khẩu mới | Nhập 4 ký tự; nhập 2 mật khẩu khác nhau; nhập lại đúng mật khẩu cũ | – | Báo “ít nhất 8 ký tự” / “chưa giống nhau” (có widget test) / “phải khác mật khẩu cũ” | TB | Negative |
| TC-AUTH-20e | Quên mật khẩu | Link dùng không được | – | Mở link trên máy tính hoặc điện thoại khác; mở lại link đã dùng; mở link quá 1 giờ | – | App không treo; form đăng nhập báo “Link trong email đã hết hạn, đã được dùng, hoặc được mở trên thiết bị khác…” | TB | Edge |
| TC-AUTH-21 | Khách | Chế độ khách | Chưa đăng nhập | Bấm “Chơi thử không cần đăng nhập”, chơi 1 ván, rồi đăng nhập | – | Chơi được; Cộng đồng yêu cầu đăng nhập; điểm khách không lẫn vào tài khoản | TB | Edge |
| TC-AUTH-22 | Phiên | Phiên bị thu hồi | Đăng nhập trên 2 máy | Đổi mật khẩu/đăng xuất toàn bộ phiên ở máy kia | – | Máy này được đưa về màn đăng nhập ở lần gọi API kế tiếp, không crash | Thấp | Edge |

### 2.2 Rubik

| Mã TC | Chức năng | Tiêu đề | Điều kiện tiên quyết | Các bước | Dữ liệu test | Kết quả mong đợi | Ưu tiên | Loại test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| TC-RBK-01 | Gợi ý giải | Khối đã giải sẵn | – | Nhập tay 6 mặt đúng màu tâm, bấm Tìm hướng giải | 54 ô đúng màu | “Khối đã được giải!”, 0 bước, không có đồng hồ, không lưu điểm (đã kiểm chứng engine) | Cao | Boundary |
| TC-RBK-02 | Gợi ý giải | Lời giải thật sự giải được khối | Khối thật đã xáo bằng scramble đã biết | 1) Quét 6 mặt 2) Làm theo từng bước | Scramble `R U R' U' F2 D L' B` | Sau bước cuối, khối thật về trạng thái giải | Cao | Positive |
| TC-RBK-03 | Gợi ý giải | Kiểm chứng tự động lời giải | – | Unit test: sinh N scramble, áp lời giải, kiểm `isSolved` | ≥100 scramble ngẫu nhiên | 100% về trạng thái giải (đã có `test/cube_service_test.dart` + bước verify trong `solveCube`) | Cao | Positive |
| TC-RBK-04 | Hợp lệ | Sai số lượng màu | – | Nhập 10 ô trắng, 8 ô đỏ | – | “Trắng có 10 ô, cần đúng 9 ô…” (đã kiểm chứng) | Cao | Negative |
| TC-RBK-05 | Hợp lệ | Tâm trùng màu | – | Sửa ô tâm mặt Đỏ thành Trắng | – | Nút “Xác nhận 9 ô màu” bị khóa | TB | Negative |
| TC-RBK-06 | Hợp lệ | Lật 1 cạnh | – | Đổi 2 sticker của cạnh UF | – | “Trạng thái Rubik không hợp lệ…”, không treo (đã kiểm chứng, <1 ms) | Cao | Negative |
| TC-RBK-07 | Hợp lệ | Xoay 1 góc | – | Xoay vòng 3 sticker góc URF | – | Báo không hợp lệ (đã kiểm chứng) | Cao | Negative |
| TC-RBK-08 | Hợp lệ | Hoán vị lẻ | – | Đổi chỗ 2 cạnh UF và UR | – | Báo không hợp lệ (đã kiểm chứng) | Cao | Negative |
| TC-RBK-09 | Hợp lệ | Góc không tồn tại | – | Góc có 2 màu đối diện, tổng mỗi màu vẫn 9 | – | Báo không hợp lệ (đã kiểm chứng) | TB | Negative |
| TC-RBK-10 | Quét | Mặt bị chụp xoay 90° | – | Chụp mặt Đỏ sai hướng cạnh trên | – | Solver báo lỗi; dùng “Xoay lưới 90°” sửa được và giải được | TB | Edge |
| TC-RBK-11 | Hiệu năng | Thời gian tìm lời giải | Máy Android tầm trung | Bấm Tìm hướng giải, bấm giờ | khối xáo 20 nước | ≤5 giây; spinner quay mượt, không ANR | TB | Performance |
| TC-RBK-12 | Gợi ý giải | Số bước hợp lý | – | Giải 10 khối xáo khác nhau | – | Mỗi lời giải ≤24 nước (giới hạn `maxDepth: 24`) | TB | Boundary |
| TC-RBK-13 | Hiển thị | Ký hiệu trùng hình minh họa | – | Với từng nước R, R', R2, U, U', … xem mô hình 3D | 18 nước | Mặt xoay và chiều xoay đúng ký hiệu (nhìn thẳng vào mặt đó) | Cao | Positive |
| TC-RBK-14 | Điều hướng | Bấm nhanh bước cuối | Đang ở bước N-1 | Bấm “Đã xoay xong” 5 lần liên tục | – | Kết quả chỉ lưu 1 lần, không crash | TB | Edge |
| TC-RBK-15 | Điều hướng | Tạm dừng rồi bấm “Đã xoay xong” | Đang có đồng hồ | Bấm tạm dừng, nhìn nút “Đã xoay xong” | – | Nút ghi “Đang tạm dừng” và bị khóa (đã sửa BUG-13, có widget test) | Thấp | Edge |
| TC-RBK-16 | Quyền | Từ chối quyền camera | – | Mở camera, chọn Từ chối | – | Thông báo rõ ràng, vẫn nhập tay được | TB | Negative |
| TC-RBK-17 | Điểm | Bấm cho xong để lấy điểm | Lời giải 20 bước | Bấm “Đã xoay xong” liên tục trong 10 giây | – | Nút chỉ mở sau 2 giây mỗi bước (hiện “Đã xoay xong (2)”, “(1)”); 20 bước mất ít nhất 40 giây → tối đa 818 điểm, đủ ngưỡng xếp hạng của server (đã sửa BUG-04, có widget test) | TB | Security |
| TC-RBK-17b | Điểm | Tạm dừng không rút ngắn được bước | Đang ở bước chờ 2 giây | Bấm tạm dừng 5 giây, tiếp tục, bấm ngay | – | Vẫn phải chờ đủ 2 giây chạy đồng hồ; thời gian tạm dừng không được tính | TB | Edge |

### 2.3 Sudoku

| Mã TC | Chức năng | Tiêu đề | Điều kiện tiên quyết | Các bước | Dữ liệu test | Kết quả mong đợi | Ưu tiên | Loại test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| TC-SDK-01 | Sinh đề | Mỗi đề đúng một lời giải | – | Sinh ≥40 đề/mức, chạy `countSolutions(limit: 2)` | seed 0–39 | Tất cả = 1 (đã kiểm chứng 120/120) | Cao | Positive |
| TC-SDK-02 | Độ khó | Số ô gợi ý theo mức | – | Đếm ô gợi ý | 1000 đề/mức | Dễ luôn 38; Vừa 21–41; Khó 22–44. Số ô không còn là thước đo độ khó (đã kiểm chứng) | Thấp | Boundary |
| TC-SDK-03 | Độ khó | Khác biệt thật về kỹ thuật | – | Giải bằng bộ giải chỉ dùng naked + hidden single | 100 đề/mức | Dễ giải được hết; Vừa và Khó **không** giải được chỉ bằng single (đã sửa: 100/0/0, trước 100/95/74) | Cao | Positive |
| TC-SDK-03b | Độ khó | Vừa khác Khó | – | Giải bằng bộ giải có pair/triple/khóa ứng viên | 1000 đề/mức | Đề Vừa giải hết; đề Khó không giải được (đã kiểm chứng: 0 đề sai bậc) | Cao | Positive |
| TC-SDK-03c | Thách đấu | Đề thách đấu cùng thang | Đã chạy migration 007 | Tạo thách đấu mỗi mức, chấm đề nhận được | – | Đề là một trong 6 đề cùng mức đã hoán vị chữ số (đã có backend test và test Dart chấm lại file SQL) | Cao | Positive |
| TC-SDK-04 | Nhập | Ô đề cho sẵn không sửa được | – | Chọn ô gợi ý, bấm số, bấm Xóa | – | Giá trị không đổi, không tính lượt/lỗi | Cao | Negative |
| TC-SDK-05 | Kiểm tra | Trùng hàng / cột / ô 3×3 | – | Nhập số đã có trong hàng, rồi cột, rồi khối | – | Ô trùng tô đỏ, lỗi +1 mỗi lần (có widget test) | Cao | Negative |
| TC-SDK-05b | Kiểm tra | Không lộ đáp án | – | Nhập một số sai nhưng chưa trùng với số nào | – | Không tô đỏ, “Lỗi” không tăng (đã sửa R3, có widget test) | Cao | Security |
| TC-SDK-06 | Đếm lỗi | Nhập lại cùng số trùng | – | Nhập 5 (trùng) → nhập 5 lần nữa → nhập 6 (trùng) | – | Lỗi lần lượt 1 → 1 → 2 | TB | Boundary |
| TC-SDK-07 | Đếm lỗi | Xóa rồi nhập lại cùng số trùng | – | Nhập 5 (trùng) → Xóa → nhập 5 | – | Vẫn 1 lỗi (đã sửa BUG-11, có widget test) | Thấp | Edge |
| TC-SDK-08 | Ghi chú | Ghi chú không tính lỗi | – | Bật Ghi chú, thêm/bỏ 1–9, tắt Ghi chú, nhập số | – | Ghi chú không đổi lượt/lỗi; nhập số xóa ghi chú ô đó | TB | Positive |
| TC-SDK-09 | Thắng | Hoàn thành đúng | Còn 1 ô trống | Nhập đáp án đúng | – | Dialog “Hoàn thành!” ngay, đồng hồ dừng, lưu 1 kết quả | Cao | Positive |
| TC-SDK-10 | Thắng | Điền đủ nhưng sai | – | Điền 81 ô, 1 ô sai | – | Không thắng; ô trùng tô đỏ; dòng “Bảng đã đầy nhưng chưa đúng…” hiện ra | Cao | Negative |
| TC-SDK-11 | Đồng hồ | Tạm dừng | – | Bấm tạm dừng 30 giây | – | Bàn cờ bị che, không nhập được, đồng hồ đứng yên | TB | Positive |
| TC-SDK-12 | Đồng hồ | Xuống nền | – | Về Home 60 giây, quay lại | – | Đồng hồ không tăng 60 giây | Cao | Positive |
| TC-SDK-13 | Điều hướng | Back khi đang chơi | – | Bấm Back | – | Hỏi “Rời ván đang chơi?”; khi đề còn đang tạo thì thoát ngay | TB | Edge |
| TC-SDK-14 | Nhập | Nhập khi chưa chọn ô | Vừa vào ván | Bấm số 5 | – | Không có gì xảy ra, không crash | Thấp | Negative |
| TC-SDK-15 | Hiệu năng | Thời gian tạo đề | Máy tầm trung | Mở Sudoku Vừa và Khó 5 lần mỗi mức | – | ≤1 giây, UI không đơ (PC: Vừa trung vị 15 ms, tối đa 116 ms; Khó tối đa 62 ms; chạy trong `compute`) | TB | Performance |
| TC-SDK-16 | Giao diện | Màn hình nhỏ, chữ lớn | 320×568 dp, font 1.3× | Mở ván | – | Không overflow (sọc vàng đen), số vẫn đọc được | TB | UI |

### 2.4 Xếp hình (puzzle trượt)

| Mã TC | Chức năng | Tiêu đề | Điều kiện tiên quyết | Các bước | Dữ liệu test | Kết quả mong đợi | Ưu tiên | Loại test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| TC-PZL-01 | Xáo trộn | Luôn giải được | – | Sinh ≥100 seed mỗi kích thước, kiểm parity (số nghịch thế + hàng ô trống) | 3×3, 4×4, 5×5 | 100% giải được (xáo bằng nước hợp lệ; có test parity) | Cao | Positive |
| TC-PZL-02 | Xáo trộn | Không sinh trạng thái đã giải | – | Sinh nhiều seed | – | Không có bàn nào đã giải ngay từ đầu | TB | Edge |
| TC-PZL-03 | Di chuyển | Chạm ô kề ô trống | – | Chạm ô bên cạnh ô trống | – | Ô trượt vào chỗ trống, Lượt +1 | Cao | Positive |
| TC-PZL-04 | Di chuyển | Chạm ô không kề | – | Chạm ô cách ô trống 2 ô hoặc chéo | – | Không di chuyển; Lỗi +1 | Cao | Negative |
| TC-PZL-05 | Di chuyển | Chạm ô trống | – | Chạm ô trống | – | Không làm gì, không tính lỗi | Thấp | Edge |
| TC-PZL-06 | Di chuyển | Ô ở góc và mép | Ô trống ở góc | Chạm các ô chỉ số 0, n−1, n²−1 | – | Chỉ ô kề mới trượt; không lỗi chỉ số | TB | Boundary |
| TC-PZL-07 | Hoàn thành | Nhận diện xong | Còn 1 nước | Thực hiện nước cuối | – | Dialog ngay, đồng hồ dừng, “Bạn đã ghép hoàn chỉnh…” | Cao | Positive |
| TC-PZL-08 | Di chuyển | Bấm nhanh hai ô | – | Double-tap/tap 2 ô gần như đồng thời | – | Trạng thái nhất quán, không mất mảnh | TB | Edge |
| TC-PZL-09 | Ảnh | Đổi ảnh giữa ván | Đã đi 10 nước | Đổi sang ảnh khác | – | Vị trí mảnh giữ nguyên, đồng hồ không reset | Thấp | Edge |
| TC-PZL-10 | Ảnh | Ảnh thư viện không vuông | – | Chọn ảnh 16:9, mở “Xem ảnh hoàn chỉnh” | ảnh 1920×1080 | Ảnh mẫu vuông, đúng phần đang ghép (đã sửa BUG-12, có widget test ở màn 360 và 800 px) | Thấp | Edge |
| TC-PZL-11 | Ảnh | Từ chối quyền / ảnh hỏng | – | Từ chối quyền thư viện hoặc chọn file hỏng | – | SnackBar báo lỗi, ván vẫn chơi được | TB | Negative |
| TC-PZL-12 | Độ khó | Độ xáo trộn đủ sâu | – | Đo khoảng cách Manhattan | 50 seed/mức | Tăng dần theo mức (đo được trung vị 13 / 28 / 56) | Thấp | Boundary |

### 2.5 Caro với máy

| Mã TC | Chức năng | Tiêu đề | Điều kiện tiên quyết | Các bước | Dữ liệu test | Kết quả mong đợi | Ưu tiên | Loại test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| TC-CAR-01 | Thắng | 5 ngang giữa bàn | – | Tạo 5 X liên tiếp hàng 7 | (7,3)…(7,7) | Thắng ngay khi đặt quân thứ 5 | Cao | Positive |
| TC-CAR-02 | Thắng | 5 dọc | – | Tạo 5 X cột 7 | (3,7)…(7,7) | Thắng | Cao | Positive |
| TC-CAR-03 | Thắng | 5 chéo chính | – | Tạo 5 X chéo chính | (3,3)…(7,7) | Thắng | Cao | Positive |
| TC-CAR-04 | Thắng | 5 chéo phụ ở góc | – | Tạo 5 X từ góc trên phải | (0,14)…(4,10) | Thắng (đã kiểm chứng) | Cao | Boundary |
| TC-CAR-05 | Thắng | Không “tràn hàng” ở mép | – | Đặt X ở (0,12),(0,13),(0,14),(1,0),(1,1) | – | **Không** thắng (đã kiểm chứng) | Cao | Boundary |
| TC-CAR-06 | Luật | 6 quân liên tiếp | – | Tạo 6 X liên tiếp, một đầu bị O chặn; rồi chặn cả hai đầu | `O X X X X X X _` và `O X X X X X X O` | Trường hợp đầu thắng, trường hợp sau không thắng (đã có test) | TB | Edge |
| TC-CAR-07 | Luật | 5 quân bị chặn hai đầu | – | Bày `O X X X X X O` theo hàng ngang và đường chéo | – | **Không** thắng, ván tiếp tục (đã có test, cả ván với máy lẫn online) | Cao | Edge |
| TC-CAR-07b | Luật | 5 quân sát mép bàn | – | 5 X ở hàng 0, cột 0–4; O ở cột 5 | – | Thắng: mép bàn không tính là chặn (đã có test) | TB | Boundary |
| TC-CAR-07c | AI | Thế chết không bị coi là đe dọa | – | Người có `O X X _ X X O` | – | Máy không phí nước chặn ô trống giữa, vì lấp ô đó không thắng (đã có test) | TB | Edge |
| TC-CAR-08 | Nhập | Đánh vào ô đã có quân | – | Chạm ô có X hoặc O | – | Không thay đổi, không tính lượt | Cao | Negative |
| TC-CAR-09 | Nhập | Bấm liên tục khi máy nghĩ | – | Chạm 5 ô khác nhau ngay sau nước của mình | – | Chỉ nước đầu được ghi nhận | Cao | Edge |
| TC-CAR-10 | AI | Chặn 3 mở `_XXX_` | Mức Vừa/Khó | Tạo 3 mở | hàng 7 cột 6–8 | Máy chặn một đầu (đã kiểm chứng) | Cao | Positive |
| TC-CAR-11 | AI | Chặn 3 gãy `X_XX` | Mức Vừa/Khó | Tạo 3 gãy | – | Máy chặn ô trống giữa (đã kiểm chứng) | Cao | Positive |
| TC-CAR-12 | AI | Chặn 4 / thắng khi có 4 | Mức Vừa/Khó | Tạo 4 một đầu; cho máy có 4 | – | Máy chặn; máy có 4 thì đi thắng ngay | Cao | Positive |
| TC-CAR-13 | AI | Ưu tiên tấn công | Mức Khó | Máy có 3 mở, người có 3 mở, đến lượt máy | – | Máy tạo 4 mở để thắng (đã sửa: Khó đi (3,4); có unit test) | Cao | Positive |
| TC-CAR-14 | AI | Mức độ khác biệt thật | – | Cho Khó đấu Vừa 200 ván, khai cuộc ngẫu nhiên | – | Khó thắng nhiều hơn rõ rệt (đã sửa: Khó 142, Vừa 27; unit test 20 ván yêu cầu Khó ≥12, Vừa ≤3) | Cao | Positive |
| TC-CAR-14b | AI | Thời gian nghĩ mức Khó trên điện thoại | Máy Android tầm trung, bản release | Chơi 1 ván dài 60+ nước, quan sát chữ “Máy đang suy nghĩ…” | – | Mỗi nước <1 giây, không giật (PC: tối đa 161 ms) | TB | Performance |
| TC-CAR-15 | AI | Mức Dễ | – | Tạo 3 mở 200 lần | – | Dễ hiếm khi chặn (đo được 21/200) | Thấp | Positive |
| TC-CAR-16 | Kết thúc | Hòa khi đầy bàn | Bàn còn 1 ô, không ai có 5 | Đi nước cuối | – | “Ván đấu hòa”, 0 điểm | TB | Boundary |
| TC-CAR-17 | Hiệu năng | Máy nghĩ ở mức Khó | Bàn 80 quân | Đo thời gian | – | <1 giây, UI không đơ (engine 0,1 ms; chạy trong `compute`) | TB | Performance |
| TC-CAR-18 | Đồng hồ | Tạm dừng khi máy đang nghĩ | – | Đi 1 nước rồi bấm tạm dừng ngay | – | Không mất/đè nước; tiếp tục thì bàn cờ đúng | Thấp | Edge |
| TC-CAR-19 | Kết thúc | Thua máy | – | Để máy thắng | – | 5 quân thắng được tô vàng ~1 giây rồi mới hiện “Máy thắng ván này”; 0 điểm, có trong lịch sử, không lên xếp hạng (đã sửa BUG-20) | TB | Positive |

### 2.6 Tính điểm

| Mã TC | Chức năng | Tiêu đề | Điều kiện tiên quyết | Các bước | Dữ liệu test | Kết quả mong đợi | Ưu tiên | Loại test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| TC-SCR-01 | Đồng hồ | Bắt đầu đúng lúc | – | Mở Sudoku Khó, quan sát đồng hồ khi còn loading | – | Đồng hồ chỉ chạy khi bàn cờ hiện ra | TB | Positive |
| TC-SCR-02 | Đồng hồ | Dừng đúng lúc | – | Hoàn thành ván, đợi 10 giây ở dialog | – | Thời gian trong dialog = lúc hoàn thành, không tăng | Cao | Positive |
| TC-SCR-03 | Đồng hồ | Tạm dừng | – | Tạm dừng 30 giây rồi tiếp tục | – | Không cộng 30 giây | Cao | Positive |
| TC-SCR-04 | Đồng hồ | Xuống nền / cuộc gọi | Ván đơn | Về Home 60 giây; nhận cuộc gọi; kéo thanh thông báo | – | Không cộng thời gian | Cao | Positive |
| TC-SCR-05 | Đồng hồ | Thách đấu không dừng | Sudoku thách đấu | Về Home 60 giây | – | Đồng hồ server vẫn tính 60 giây (theo thiết kế) | TB | Positive |
| TC-SCR-06 | Công thức | Tính đúng | – | Sudoku Khó, 300 giây, 2 lỗi | – | 6000 × 1500 / 1800 = 5000 → 4750 → **4512**; client = DB (đã kiểm chứng) | Cao | Positive |
| TC-SCR-07 | Công thức | Không âm, không chạm sàn | – | Sudoku Dễ, 3600 giây, 50 lỗi | – | **14** (> 0, vẫn phân biệt được với ván tốt hơn); thua/hòa = 0 (đã kiểm chứng) | TB | Boundary |
| TC-SCR-08 | Công thức | Không còn hòa ở sàn | – | A: 1000 giây, 0 lỗi; B: 990 giây, 30 lỗi (Sudoku Dễ) | – | A **750** > B **153** nên A xếp trên (đã sửa BUG-08; trước: cùng 100, B xếp trên) | TB | Edge |
| TC-SCR-08b | Công thức | Client và database khớp nhau | Đã chạy migration 008 | Chơi 1 ván online, so điểm trong lịch sử máy với bảng Online | – | Hai con số bằng nhau (đã kiểm chứng trên 5.000 input bằng PGlite) | Cao | Positive |
| TC-SCR-09 | Công thức | Rubik bấm cho xong | Lời giải 20 bước | Bấm “Đã xoay xong” 20 lần trong 10 giây | – | Không làm được: mỗi bước khóa 2 giây, nhanh nhất 40 giây = 818 điểm (đã sửa BUG-04) | TB | Security |
| TC-SCR-15 | Xếp hạng | Ván chơi offline | Đã đăng nhập, bật máy bay trước khi vào ván | Chơi xong, tắt máy bay, đồng bộ | – | Đồng bộ thành công; lịch sử ghi “Đã đồng bộ, không xếp hạng”; không có trên bảng Online | TB | Edge |
| TC-SCR-16 | Xếp hạng | Ván chơi online | Đã đăng nhập, có mạng | Chơi xong 1 ván Sudoku Dễ sau ≥60 giây | – | Lịch sử ghi “Đã đồng bộ”; bảng Online có điểm mới | Cao | Positive |
| TC-SCR-10 | Bỏ giữa chừng | Không tính điểm | – | Chơi 1 phút, bấm Back → Rời ván | – | Không có bản ghi mới | TB | Positive |
| TC-SCR-11 | Chơi lại | Không ghi đè | Có kỷ lục 5000 | Chơi lại được 4000 | – | Lịch sử có 2 ván; kỷ lục và online vẫn 5000 | TB | Positive |
| TC-SCR-12 | Kết quả | Thua/hòa | – | Thua máy Caro | – | 0 điểm, không lên bảng | TB | Positive |
| TC-SCR-13 | Lưu | Kill app khi đang lưu | – | Kill app ngay khi dialog hiện | – | Mở lại: hoặc có đúng 1 bản ghi hoặc không có; không hỏng lịch sử | Thấp | Edge |
| TC-SCR-14 | Đồng bộ | Offline rồi online | Đã đăng nhập, bật máy bay | Chơi 3 ván, tắt máy bay, bấm Đồng bộ | – | 3 ván lên server, bấm lại không tạo trùng | Cao | Positive |

### 2.7 Xếp hạng

| Mã TC | Chức năng | Tiêu đề | Điều kiện tiên quyết | Các bước | Dữ liệu test | Kết quả mong đợi | Ưu tiên | Loại test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| TC-RNK-01 | Sắp xếp | Theo điểm giảm dần | ≥5 người có điểm | Mở Xếp hạng → Online | – | Điểm giảm dần, hạng 1–3 có màu huy chương | Cao | Positive |
| TC-RNK-02 | Lọc | Theo game và độ khó | – | Đổi game/độ khó | – | Chỉ hiện đúng mục; Rubik chỉ có “Có hướng dẫn” | Cao | Positive |
| TC-RNK-03 | Bằng điểm | Tiêu chí phụ | 2 người cùng điểm | – | 5000 điểm, 300 giây vs 310 giây | Ít giây hơn xếp trên; bằng giây thì ít lỗi hơn | TB | Boundary |
| TC-RNK-04 | Bằng điểm | Ai đạt trước | 2 người bằng điểm, giây, lỗi | – | – | Người đạt trước xếp trên (đã sửa BUG-14, có backend test) | Thấp | Edge |
| TC-RNK-05 | Gộp | Mỗi người 1 dòng | 1 người chơi 3 ván | – | – | Chỉ hiện ván tốt nhất | Cao | Positive |
| TC-RNK-06 | Cập nhật | Sau khi chơi xong | Đã đăng nhập, online | Chơi xong, mở Xếp hạng → Online | – | Thấy điểm mới (có thể phải bấm Tải lại khi đồng bộ chưa xong) | Cao | Positive |
| TC-RNK-07 | Danh sách dài | >50 người | 60 tài khoản có điểm | Xem bảng bằng tài khoản hạng 51+ | – | Top 50 + thẻ “Hạng của bạn: #N” (đã sửa BUG-19, có backend test và widget test) | TB | Boundary |
| TC-RNK-08 | Giao diện | Tên dài / emoji | Tên 40 ký tự | Xem bảng | – | Không overflow | Thấp | UI |
| TC-RNK-09 | Bảo mật | Gửi điểm giả qua REST | Có token của tài khoản mình | `POST /rest/v1/game_results` với `seconds:0, mistakes:0, outcome:'win', difficulty:'hard'` | – | Bị từ chối với `42501 permission denied` (đã sửa BUG-01, có backend test). Gọi `submit_game_result` không có phiên hoặc với phiên giả thì kết quả không được xếp hạng | Cao | Security |
| TC-RNK-10 | Bảo mật | Ghi điểm cho người khác | Token tài khoản A | Insert với `user_id` của B | – | Bị RLS chặn | Cao | Security |
| TC-RNK-11 | Bảo mật | Sửa/xóa điểm | Token tài khoản A | PATCH/DELETE `game_results` | – | Bị chặn (không có grant) | Cao | Security |
| TC-RNK-12 | Bảo mật | Chỉ dùng anon key | Không đăng nhập | GET `/rest/v1/leaderboard` | – | Bị từ chối/rỗng | TB | Security |
| TC-RNK-13 | Mạng | Mất mạng khi xem online | – | Bật máy bay, chọn Online | – | Thông báo lỗi + nút Thử lại | TB | Negative |
| TC-RNK-14 | Tài khoản | Đổi tài khoản | 2 tài khoản trên 1 máy | Đăng xuất A, đăng nhập B | – | Kỷ lục cá nhân của B không lẫn ván của A | TB | Edge |

### 2.8 Thách đấu

| Mã TC | Chức năng | Tiêu đề | Điều kiện tiên quyết | Các bước | Dữ liệu test | Kết quả mong đợi | Ưu tiên | Loại test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| TC-CHL-01 | Mời | Gửi lời mời Sudoku | A, B đã đăng nhập | A → Cộng đồng → Thách đấu B → Sudoku Vừa | – | SnackBar “Đã gửi…”; thẻ “Chờ chấp nhận” | Cao | Positive |
| TC-CHL-02 | Mời | Chấp nhận realtime | B mở Cộng đồng | B bấm Chấp nhận | – | Cả hai máy thấy “Đang thi đấu” không cần tải lại | Cao | Positive |
| TC-CHL-03 | Mời | Từ chối | – | B bấm Từ chối | – | “Đã từ chối” ở cả hai máy | Cao | Positive |
| TC-CHL-04 | Bảo mật | Người gửi tự chấp nhận | Token của A | A gọi RPC `respond_challenge` cho lời mời mình gửi | – | Bị từ chối | TB | Security |
| TC-CHL-05 | Mời | Tự thách đấu chính mình | – | Gọi `create_game_challenge` với `opponent_id` = chính mình | – | “Người nhận không hợp lệ.” | TB | Negative |
| TC-CHL-06 | Mời | Giới hạn lời mời chờ | A có 20 lời mời chờ | Gửi lời mời thứ 21 | – | “Bạn đang có quá nhiều lời mời…” | Thấp | Boundary |
| TC-CHL-07 | Mời | Lời mời hết hạn | Lời mời chờ 24 giờ | Đợi quá hạn | – | Hiện “Đã hết hạn”, mất nút Chấp nhận/Từ chối; gọi RPC thì bị từ chối “Lời mời đã hết hạn.” (đã sửa, có backend test) | TB | Edge |
| TC-CHL-08 | Mời | Hủy lời mời đã gửi | A đã gửi lời mời, B chưa trả lời | A bấm “Hủy lời mời” → xác nhận | – | Cả hai máy thấy “Người gửi đã hủy”; B không còn nút Chấp nhận, gọi RPC cũng bị từ chối (đã sửa, có backend test và widget test) | TB | Positive |
| TC-CHL-08b | Mời | Người nhận/người ngoài không hủy được | Lời mời A gửi B | B, rồi C gọi `cancel_challenge` | – | Bị từ chối; B chỉ thấy Chấp nhận/Từ chối, không có nút Hủy (đã có test) | TB | Security |
| TC-CHL-08c | Đồng thời | Hủy và chấp nhận cùng lúc | Lời mời đang chờ | A bấm Hủy và B bấm Chấp nhận gần như cùng lúc | – | Chỉ một thao tác thành công, người kia nhận thông báo lỗi; trạng thái cuối nhất quán trên hai máy | Thấp | Concurrency |
| TC-CHL-09 | Thi đấu | Cùng một đề | – | A và B bấm Bắt đầu | – | 81 ô gợi ý giống hệt trên hai máy | Cao | Positive |
| TC-CHL-10 | Kết quả | Xác định người thắng | Cả hai đã nộp | Xem kết quả | A 5000, B 4800 | A thắng; bằng điểm thì xét thời gian, rồi lỗi; bằng cả ba → hòa | Cao | Positive |
| TC-CHL-11 | Đồng thời | Nộp cùng lúc | Cả hai còn 1 ô | Hai người nhập ô cuối cùng một giây | – | Chỉ một lần chuyển `completed`, người thắng đúng (có `FOR UPDATE`) | TB | Concurrency |
| TC-CHL-12 | Bỏ cuộc | Một bên không bao giờ nộp | A đã nộp | B gỡ app | – | Sau 24 giờ kể từ khi chấp nhận, A thắng (hết giờ); B nộp muộn thì không được tính (đã sửa, có backend test) | Cao | Edge |
| TC-CHL-12b | Đầu hàng | Đầu hàng Sudoku | Thách đấu đang diễn ra | B bấm Đầu hàng → xác nhận | – | A thắng, ghi “(đầu hàng)”; nếu B đã nộp bài thì không được đầu hàng (đã có backend test) | TB | Positive |
| TC-CHL-13 | Mạng | Mất mạng khi nộp | Ván vừa xong | Bật máy bay rồi hoàn thành | – | Báo lỗi + nút “Nộp lại”; nộp lại không tạo trùng | Cao | Negative |
| TC-CHL-14 | Vòng đời | Kill app giữa thách đấu | Đã điền 30 ô | Kill app, mở lại, Bắt đầu / tiếp tục | – | Khôi phục bàn và số lỗi; đồng hồ tính cả thời gian tắt app | TB | Edge |
| TC-CHL-15 | Bảo mật | Khai 0 lỗi | Token của A | Gọi `submit_challenge` với đáp án đúng và `error_count: 0` | – | Server không tin số lỗi từ client (hiện tại chấp nhận → BUG-15) | TB | Security |
| TC-CHL-16 | Caro online | Đi theo lượt | Lời mời Caro đã chấp nhận | A (X) đi, rồi B (O) đi | – | Realtime ≤2 giây; đúng lượt | Cao | Positive |
| TC-CHL-17 | Caro online | Đi sai lượt | Lượt của A | B gọi RPC `play_caro_move` | – | “Chưa đến lượt của bạn.” | Cao | Security |
| TC-CHL-18 | Caro online | Hai người bấm cùng lúc | – | Cả hai chạm ô cùng lúc | – | Chỉ nước của người đúng lượt được nhận | TB | Concurrency |
| TC-CHL-19 | Caro online | Một bên thoát/mất mạng | Ván đang chơi | B thoát hẳn | – | Đến lượt B mà quá 60 giây: app của A tự yêu cầu chốt, A thắng “(hết giờ)”. B mở lại trận hoặc đi muộn thì cũng bị xử thua (đã sửa, có backend test + widget test) | Cao | Edge |
| TC-CHL-19b | Caro online | Đồng hồ lượt | Cả hai đã vào trận | Quan sát dòng đếm ngược khi đến lượt mình và lượt đối thủ | – | “Bạn còn N giây để đi” (đỏ khi ≤10 giây) / “Đối thủ còn N giây”; trước khi đối thủ vào trận thì ghi đồng hồ chưa chạy | TB | UI |
| TC-CHL-19c | Caro online | Rời trận đang chơi | Ván đang chơi | Bấm Back | – | Hỏi “Rời trận đang chơi?”; chọn Ở lại thì vẫn ở trận (đã có widget test) | TB | Edge |
| TC-CHL-19d | Caro online | Không ai vào trận | Đã chấp nhận, chỉ B mở trận | Chờ quá 24 giờ | – | B thắng; nếu không ai mở thì hòa (đã có backend test) | Thấp | Edge |
| TC-CHL-20 | Caro online | Tái đấu | Ván kết thúc | Bấm Tái đấu | – | Lời mời mới đến đối thủ | TB | Positive |
| TC-CHL-21 | Bảo mật | Nộp Sudoku vào thử thách Caro | Thử thách Caro đang diễn ra | Gọi `start_challenge` rồi `submit_challenge` với id của thử thách Caro | 1 lưới Sudoku hợp lệ bất kỳ | Bị từ chối (đã sửa ở migration 006) | Thấp | Security |

### 2.9 Chat

| Mã TC | Chức năng | Tiêu đề | Điều kiện tiên quyết | Các bước | Dữ liệu test | Kết quả mong đợi | Ưu tiên | Loại test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| TC-CHT-01 | Gửi/nhận | Realtime | 2 máy, A và B mở chat với nhau | A gửi “xin chào” | – | B nhận ≤2 giây, không cần tải lại | Cao | Positive |
| TC-CHT-02 | Gửi/nhận | Thứ tự | – | A gửi 10 tin liên tiếp 1…10 | – | Hiển thị đúng 1…10 trên cả hai máy | Cao | Positive |
| TC-CHT-03 | Hiển thị | Thời gian | – | Gửi tin lúc 23:59 | – | Giờ theo múi giờ máy; tin ngày khác hiển thị đúng ngày | TB | Positive |
| TC-CHT-04 | Nhập | Tin rỗng | – | Bấm Gửi khi ô trống | – | Không gửi | Cao | Negative |
| TC-CHT-05 | Nhập | Chỉ khoảng trắng / xuống dòng | – | Nhập `   \n  ` | – | Không gửi | TB | Negative |
| TC-CHT-06 | Nhập | Biên 2000 ký tự | – | Dán 2000 và 2001 ký tự ASCII | – | 2000 gửi được; 2001 bị chặn bởi bộ đếm | TB | Boundary |
| TC-CHT-07 | Nhập | Rất nhiều emoji | – | Dán 1500 lá cờ 🇻🇳 (3000 code point) | – | Báo “Tin nhắn quá dài (3000/2000…)”, không gửi (đã sửa BUG-09, có widget test) | TB | Edge |
| TC-CHT-08 | Nhập | Tiếng Việt có dấu, emoji | – | `Chào bạn 👋, đánh cờ không?` | – | Hiển thị đúng ở cả hai máy | TB | Edge |
| TC-CHT-09 | Mạng | Mất mạng khi gửi | – | Bật máy bay, gửi; tắt máy bay, gửi lại | – | Báo lỗi, giữ nội dung; gửi lại chỉ tạo **1** tin | Cao | Negative |
| TC-CHT-10 | Lịch sử | Mở lại app | Có 20 tin | Kill app, mở chat | – | Còn 20 tin, đúng thứ tự | Cao | Positive |
| TC-CHT-11 | Lịch sử | >100 tin | 150 tin | Mở chat | – | 100 tin gần nhất (không có tải thêm – ghi nhận giới hạn) | Thấp | Boundary |
| TC-CHT-12 | Tài nguyên | Hủy listener khi thoát | DevTools/Realtime Inspector | Mở/đóng chat 20 lần | – | Số channel realtime và bộ nhớ không tăng dần | TB | Performance |
| TC-CHT-13 | Bảo mật | Người thứ ba đọc tin | Token của C | GET `messages?room_key=eq.<A:B>` | – | Rỗng (RLS) | Cao | Security |
| TC-CHT-14 | Bảo mật | Giả mạo người gửi | Token của A | Insert với `sender_id` = B | – | Bị RLS chặn | Cao | Security |
| TC-CHT-15 | UX | Gửi liên tiếp, cả khi có lỗi | – | Gửi 3 tin liên tục; gửi một tin quá dài rồi gửi tin thường | – | Bàn phím không đóng (đã sửa BUG-10, BUG-22, có widget test) | Thấp | UI |
| TC-CHT-16 | Bảo mật | Nội dung HTML/script | – | Gửi `<b>x</b><script>` | – | Hiển thị nguyên văn | Thấp | Security |

---

## 3. Bước 3 – Kiểm thử phi chức năng

| Mã | Hạng mục | Kịch bản | Kết quả mong đợi | Nhận định từ code |
| --- | --- | --- | --- | --- |
| NF-01 | Màn hình nhỏ/lớn | 320×568, 360×800, tablet 800×1280, font 1.3× và 2× | Không overflow, lưới game vuông | Có `ConstrainedBox` + `AspectRatio`; có test màn nhỏ/chữ lớn. Cần chạy thật. |
| NF-02 | Xoay màn hình | Xoay ngang | Giữ dọc | `main.dart` khóa `portraitUp` → không xoay. Ghi rõ trong báo cáo, không phải lỗi. |
| NF-03 | Dark mode | Bật dark mode hệ thống | App giữ giao diện sáng, đọc rõ | Cố ý chỉ hỗ trợ giao diện sáng (`themeMode: ThemeMode.light`, ghi trong README) vì màu bàn cờ/sticker cố định (BUG-17) |
| NF-04 | Xuống nền | Home trong lúc chơi | Đồng hồ dừng (ván đơn) | `GameClock` dừng khi lifecycle khác `resumed`; có test. |
| NF-05 | Cuộc gọi đến | Gọi vào máy khi đang chơi Sudoku | Đồng hồ dừng, không mất trạng thái | Như NF-04. Cần chạy thật. |
| NF-06 | Kill app khi đang chơi | Kill giữa ván đơn | Mất tiến độ (theo thiết kế, README có ghi) | Nên ghi rõ trong báo cáo; thách đấu Sudoku có bản nháp. |
| NF-07 | Main thread | AI Caro Khó, giải Rubik, sinh Sudoku, nhận diện màu | Không giật | Cả 4 đều chạy trong `compute`. AI Caro chỉ mất ~0,1 ms nên chi phí tạo isolate lớn hơn phần tính. |
| NF-08 | Mạng chậm | Throttle 3G/2G | Có loading, timeout 20 giây | Mọi request có `.timeout(networkTimeout)`. |
| NF-09 | Mất mạng | Máy bay khi đồng bộ/chat/xếp hạng | Thông báo thân thiện, không crash | Có `friendlyError`; stream realtime báo lỗi nhưng không tự kết nối lại → phải bấm Tải lại. |
| NF-10 | Wi-Fi ↔ 4G | Đổi mạng trong ván Caro online | Realtime nối lại, bàn cờ đúng | **Cần bổ sung:** chạy thật. Nếu stream lỗi thì chỉ có nút Thử lại. |
| NF-11 | Dung lượng | APK | ~30 MB/ABI | Đã đo trong `docs/AUDIT_REPORT.md`. |
| NF-12 | Accessibility | TalkBack trên Sudoku, Puzzle, Rubik | Đọc được vị trí ô | Có `Semantics` cho ô Sudoku/Puzzle/Rubik; ô Caro chưa có nhãn. |

---

## 4. Bước 4 – Rà soát code

### 4.0 Bằng chứng từ script probe

| Kiểm tra | Kết quả đo |
| --- | --- |
| Sudoku: nghiệm duy nhất | 120/120 đề (40/mức) có đúng 1 nghiệm |
| Sudoku: số ô gợi ý | Trước khi sửa: Dễ 42, Vừa 34, Khó 28. Sau khi sửa (1000 đề/mức): Dễ 38, Vừa 21–41, Khó 22–44; 0 đề sai bậc |
| Sudoku: giải chỉ bằng single | Trước khi sửa: Dễ 100/100, Vừa 95/100, **Khó 74/100**. Sau khi sửa: 100 / **0** / **0** |
| Đề thách đấu (server) | Trước khi sửa: 3 đề (36/30/17 ô), chấm lại đều là **Dễ**. Sau khi sửa: 18 đề đã chấm, 6 đề mỗi mức |
| Caro: điều kiện thắng | 4 hướng, góc, 6 quân đều đúng; không tràn hàng; luật chặn hai đầu đúng (sau khi sửa) |
| Caro: chặn 3 mở, 3 gãy, 4 mở, chặn điểm giao | Vừa và Khó đều đạt |
| Caro: cả hai có 3 mở, lượt máy | Trước khi sửa: Vừa và Khó đều **chặn** thay vì tạo 4 mở để thắng. Sau khi sửa: Khó đi (3,4) → thắng; Vừa vẫn chặn |
| Caro: 200 ván Khó vs Vừa (khai cuộc ngẫu nhiên) | Trước khi sửa: luật cũ Khó 23 – Vừa 28; luật chặn hai đầu Khó 16 – Vừa 25. **Sau khi sửa: Khó 142 – Vừa 27 – hòa 31**; Khó thắng Dễ 200/200 |
| Caro: thời gian nghĩ mức Khó (sau khi sửa) | 7484 nước: trung bình 23 ms, p95 61 ms, tối đa 161 ms (PC, Dart JIT) |
| Caro: Dễ chặn 3 mở | 21/200 |
| Puzzle: Manhattan trung vị | 3×3: 13; 4×4: 28; 5×5: 56 |
| Rubik: trạng thái lỗi | Lật cạnh, xoay góc, hoán vị lẻ, góc không tồn tại, sai số màu: đều `FormatException`, <1 ms |
| Điểm | Trước khi sửa: Rubik 20 bước bấm trong 10 giây = 980; Sudoku Dễ 1000 giây = 100 (sàn). Sau khi sửa: Rubik 20 bước nhanh nhất 40 giây = 818 (mỗi bước khóa 2 giây); Sudoku Dễ 10 phút = 1000, 30 phút = 500; không còn sàn |

### 4.1 Lỗi logic theo file

**R1. AI Caro Khó không mạnh hơn Vừa** – **ĐÃ SỬA** (xem mục 0; code mới ở `_Search` trong [caro_engine.dart](lib/games/caro_engine.dart)). Phân tích bên dưới mô tả code cũ.

```dart
int rank(int i) =>
    _potential(board, i, 2) + _potential(board, i, 1) * 11 ~/ 10;   // phòng thủ luôn nặng hơn 10%
...
for (final i in candidates.take(12)) {
  ...
  final score = attack - danger * 2;   // chỉ xét nước trả lời tốt nhất của người, không xét nước tiếp theo của máy
```

Nguyên nhân: (a) trọng số phòng thủ 1.1 làm máy chặn 3 mở của người thay vì tạo 4 mở thắng chắc; (b) “2 lớp” chỉ trừ điểm theo nước trả lời mạnh nhất, không đệ quy, không alpha-beta, nên không thấy đòn kép 4-3, 3-3; (c) `_potential` không phân biệt 3 bị chặn một đầu với 3 mở (chỉ nhân với `open`).

Hướng sửa: (1) xếp hạng mối đe dọa theo thứ tự: máy thắng ngay > chặn người thắng ngay > máy tạo 4 mở/4-3 > chặn 4 mở/4-3 của người > máy tạo 3 mở > chặn 3 mở; (2) dùng negamax alpha-beta, độ sâu 2 (Vừa) và 4 (Khó), chỉ xét 10–15 ứng viên tốt nhất mỗi nút, có giới hạn thời gian trong isolate:

```dart
int _negamax(List<int> b, int depth, int alpha, int beta, int me) {
  final opp = 3 - me;
  if (depth == 0) return _evaluate(b, me) - _evaluate(b, opp);
  final moves = _candidates(b)
    ..sort((x, y) => (_potential(b, y, me) + _potential(b, y, opp))
        .compareTo(_potential(b, x, me) + _potential(b, x, opp)));
  var best = -1 << 40;
  for (final m in moves.take(12)) {
    b[m] = me;
    final score = hasFive(b, m, me)
        ? (1 << 30) + depth            // thắng sớm tốt hơn thắng muộn
        : -_negamax(b, depth - 1, -beta, -alpha, opp);
    b[m] = 0;
    if (score > best) best = score;
    if (best > alpha) alpha = best;
    if (alpha >= beta) break;          // cắt tỉa beta
  }
  return best;
}
```

Tiêu chí nghiệm thu: thêm test cho Khó đấu Vừa 100 ván, khai cuộc ngẫu nhiên, Khó phải thắng ≥70%.

**R2. Độ khó Sudoku chỉ là số ô gợi ý; lưới gốc là một mẫu cố định** – **ĐÃ SỬA** (`gradeSudoku`, `_LogicSolver`, `_randomGrid` trong [sudoku_engine.dart](lib/games/sudoku_engine.dart); đề thách đấu ở [007_graded_sudoku.sql](supabase/migrations/007_graded_sudoku.sql)). Phân tích bên dưới mô tả code cũ, số dòng cũ: [sudoku_engine.dart:24](lib/games/sudoku_engine.dart:24), [sudoku_engine.dart:28](lib/games/sudoku_engine.dart:28)

```dart
for (final c in cols) digits[(r * 3 + r ~/ 3 + c) % 9],   // mọi lưới đều là hoán vị của 1 lưới mẫu
final target = [42, 34, 28][difficulty.index];             // khác biệt duy nhất giữa các mức
```

Hướng sửa: viết `grade(givens)` bằng bộ giải kỹ thuật: chỉ cần single → Dễ; cần thêm naked/hidden pair, pointing → Vừa; phải đoán/backtrack → Khó. Sinh lại (tối đa ~30 lần trong isolate) cho đến khi `grade` đúng mức yêu cầu. Lưới gốc nên sinh bằng backtracking với thứ tự số ngẫu nhiên, thêm phép chuyển vị, thay cho công thức mẫu. Đồng bộ ba đề thách đấu trong SQL với cùng thang.

**R3. Màn Sudoku tô đỏ ô sai theo đáp án** – **ĐÃ SỬA** (tô đỏ và tính lỗi theo luật trùng; phân tích bên dưới mô tả code cũ) – [sudoku_page.dart:237](lib/games/sudoku_page.dart:237)

```dart
final wrong = _board[i] != 0 && _board[i] != _puzzle!.solution[i];
```

Hệ quả: người chơi dò được đáp án (thử từng số đến khi hết đỏ, mỗi lần −100 điểm). Với thách đấu, đáp án có sẵn trong bộ nhớ client. Hướng sửa: chỉ tô đỏ khi **xung đột theo luật** (dùng `canPlace`), hoặc thêm tùy chọn “Kiểm tra tự động” kèm phạt nặng hơn. Đếm lỗi vẫn có thể giữ theo đáp án.

**R4. Đếm lỗi Sudoku không nhất quán sau khi Xóa** – **ĐÃ SỬA** (tập `_counted`, lưu cả trong bản nháp thách đấu) – [sudoku_page.dart:101-105](lib/games/sudoku_page.dart:101), [sudoku_page.dart:349](lib/games/sudoku_page.dart:349)

`if (_board[_selected] == value) return;` chỉ chống trùng khi giá trị đang nằm trên ô. Xóa rồi nhập lại cùng số sai thì tính thêm 1 lỗi. Sửa:

```dart
final Map<int, Set<int>> _wrongTried = {};
...
if (value != _puzzle!.solution[_selected] &&
    _wrongTried.putIfAbsent(_selected, () => {}).add(value)) {
  _mistakes++;
}
```

**R5. Điểm có sàn 100 làm sai thứ tự xếp hạng** – **ĐÃ SỬA** bằng công thức số nguyên dùng chung ([game_models.dart](lib/games/game_models.dart), [008_score_formula.sql](supabase/migrations/008_score_formula.sql)); khác đề xuất bên dưới ở chỗ dùng chia nguyên thay vì số thực để client và DB không lệch khi làm tròn – [game_models.dart:24](lib/games/game_models.dart:24), SQL `game_score` ([001_game_app.sql:19-24](supabase/migrations/001_game_app.sql:19))

`max(100, …)` khiến mọi ván chậm đều 100 điểm; khi đó bảng xếp theo giây và bỏ qua số lỗi (TC-SCR-08). Ngoài ra hệ số 2 điểm/giây áp dụng chung cho mọi game: Sudoku Dễ chạm sàn sau 950 giây (~16 phút, mức bình thường của người mới). Sửa: thời gian chuẩn theo từng game và độ khó, giảm mượt, không chạm sàn sớm. Ví dụ:

```dart
final ref = refSeconds[game]![difficulty]!;  // vd Sudoku Dễ 600, Vừa 900, Khó 1500
final raw = base * (difficulty.index + 1) * ref / (ref + seconds) - mistakes * 100;
return max(1, raw.round());
```

Sửa đồng thời hàm SQL `game_score` để client và DB cho cùng kết quả.

**R6. Điểm Rubik “bấm cho xong”** – **ĐÃ SỬA** (khóa 2 giây/bước theo đồng hồ ván + ngưỡng server; phân tích bên dưới mô tả code cũ) – [solution_page.dart:48](lib/rubik/solution_page.dart:48), [solution_page.dart:172](lib/rubik/solution_page.dart:172)

Thời gian = thời gian bấm nút; lỗi = người chơi tự bấm “Ghi nhận”. Bấm liên tục 20 lần được 980 điểm. Hướng sửa tối thiểu: thời gian tối thiểu mỗi bước (ví dụ 1,5 giây, nhanh hơn thì không chuyển bước), hoặc cuối ván yêu cầu quét lại 1–2 mặt để xác nhận khối đã giải; ghi rõ “Rubik có hướng dẫn” là điểm luyện tập, không đưa lên bảng online. Khi `paused` thì khóa nút hoặc phủ `PauseCover` để người chơi biết vì sao bấm không có tác dụng.

**R7. Đăng ký email trùng bị báo như đăng ký mới** – **ĐÃ SỬA**, xem `isExistingAccount` trong [app_store.dart](lib/data/app_store.dart). Phân tích bên dưới mô tả code cũ – [app_store.dart:204-213](lib/data/app_store.dart:204)

Khi bật xác nhận email, Supabase **không** trả lỗi cho email đã tồn tại mà trả `user` có `identities` rỗng (chống dò email). Code chỉ xét `response.session`. Sửa:

```dart
final user = response.user;
if (user != null && (user.identities?.isEmpty ?? false)) {
  throw const AuthException('Email đã tồn tại', code: 'user_already_exists');
}
return response.session != null;
```

(Nếu muốn giữ chống dò email thì đổi câu thông báo thành “Nếu email chưa đăng ký, bạn sẽ nhận được thư xác nhận; nếu đã có tài khoản, hãy đăng nhập hoặc đặt lại mật khẩu.”)

**R8. Thiếu quên mật khẩu** – **ĐÃ SỬA** (`requestPasswordReset`, `updatePassword`, `NewPasswordPage`; phần còn lại mô tả đề xuất ban đầu) – `lib/ui/profile_page.dart`, `lib/data/app_store.dart`

```dart
Future<void> resetPassword(String email) => client!.auth
    .resetPasswordForEmail(email.trim(), redirectTo: 'io.bakhi.gameapp://login-callback/')
    .timeout(networkTimeout);
```

Trong listener `onAuthStateChange`, khi `event.event == AuthChangeEvent.passwordRecovery` thì mở màn “Đặt mật khẩu mới” gọi `auth.updateUser(UserAttributes(password: …))`.

**R9. Chat: kiểm độ dài sai đơn vị và chặn im lặng** – **ĐÃ SỬA** – [community_page.dart:471](lib/ui/community_page.dart:471)

```dart
if (body.isEmpty || body.length > 2000 || _sending) return;
```

`String.length` đếm UTF-16; bộ đếm `maxLength` của `TextField` đếm grapheme; Postgres `char_length` đếm code point. 1500 emoji = 1500 grapheme (qua bộ đếm) = 3000 UTF-16 → nút Gửi không làm gì, không có thông báo. Sửa: dùng `body.runes.length` (khớp `char_length`) và báo lỗi thay vì `return` im lặng.

**R10. Chat: bàn phím đóng sau mỗi lần gửi** – **ĐÃ SỬA** (thêm key cho ô nhập, vì dòng lỗi chèn phía trên cũng làm mất focus) – [community_page.dart:575](lib/ui/community_page.dart:575)

`enabled: !_sending` làm `TextField` mất focus. Đổi thành `readOnly: _sending` (giữ focus) hoặc giữ `enabled: true` và chỉ khóa nút Gửi.

**R11. Ghi điểm thẳng vào bảng** – [001_game_app.sql:99](supabase/migrations/001_game_app.sql:99) – **ĐÃ SỬA** bằng [005_verified_results.sql](supabase/migrations/005_verified_results.sql)

```sql
create policy results_insert on public.game_results for insert to authenticated
  with check (user_id = (select auth.uid()));
```

Chỉ kiểm chủ sở hữu, không kiểm tính hợp lý. Xem BUG-01 để biết hướng sửa.

**R12. Thách đấu không có hết hạn, đầu hàng, hết giờ** – **ĐÃ SỬA** bằng [006_challenge_deadlines.sql](supabase/migrations/006_challenge_deadlines.sql). Bản cài đặt dùng chung một hàm nội bộ `settle_challenge_deadline` để chốt kết quả quá hạn, được gọi ở đầu mọi RPC thách đấu thay vì cron. Phân tích bên dưới mô tả code cũ.

Trạng thái chỉ có `pending/accepted/declined/completed`. Sửa:

```sql
alter table public.challenges add column expires_at timestamptz not null default now() + interval '24 hours';
alter table public.caro_matches add column turn_deadline timestamptz;
-- respond_challenge: thêm điều kiện "and c.expires_at > now()"
-- play_caro_move: mỗi nước đặt turn_deadline = clock_timestamp() + interval '2 minutes'
create function public.claim_caro_timeout(challenge_id uuid) returns void ... -- người còn lại nhận thắng khi quá turn_deadline
create function public.resign_caro(challenge_id uuid) returns void ...        -- đầu hàng
-- Sudoku: quá 24 giờ sau khi chấp nhận, ai đã nộp thì thắng; không ai nộp thì hòa.
```

Ở client hiển thị trạng thái “Hết hạn” và nút “Đầu hàng” trong `OnlineCaroPage`, cùng `PopScope` hỏi trước khi rời ván đang chơi.

**R13. RPC Sudoku không kiểm loại game** – [001_game_app.sql:146](supabase/migrations/001_game_app.sql:146), [001_game_app.sql:163](supabase/migrations/001_game_app.sql:163)

`start_challenge` và `submit_challenge` không kiểm `c.game = 'sudoku'`. Với thử thách Caro, `puzzle` là `NULL`, vòng kiểm ô gợi ý `puzzle[i] <> 0` cho ra `NULL` nên bị bỏ qua, và mọi lưới Sudoku hợp lệ đều được nhận. Thêm `or c.game <> 'sudoku'` vào điều kiện báo lỗi của cả hai hàm.

**R14. Thứ tự khi bằng điểm** – **ĐÃ SỬA** (migration 010) – [app_store.dart:246](lib/data/app_store.dart:246)

`.order('user_id')` là tiêu chí cuối, không có nghĩa nghiệp vụ. Thêm `r.created_at as achieved_at` vào view `leaderboard` và đổi thành `.order('achieved_at')`.

**R15. Ảnh mẫu không khớp ảnh ghép khi ảnh không vuông** – **ĐÃ SỬA** – [puzzle_page.dart:80](lib/games/puzzle_page.dart:80)

Mảnh ghép cắt phần giữa hình vuông (`BoxFit.cover` trong `OverflowBox`), còn dialog hiện cả ảnh. Bọc ảnh mẫu trong `AspectRatio(aspectRatio: 1, child: Image(..., fit: BoxFit.cover))`.

**R16. Puzzle tính lỗi khi chạm nhầm** – [puzzle_page.dart:55](lib/games/puzzle_page.dart:55)

Mỗi lần chạm ô không kề ô trống là −100 điểm; chạm nhầm trên màn nhỏ rất dễ xảy ra. Đây là lựa chọn thiết kế hợp lệ nhưng nên giải thích rõ trong báo cáo, hoặc đổi “lỗi” thành số nước vượt quá lời giải tối ưu (tính bằng A* cho 3×3 và 4×4).

**Async / stream:** không tìm thấy `setState` sau `dispose` nào (mọi nhánh `await` đều kiểm `mounted`). `StreamBuilder` tự hủy subscription khi rời màn; `OnlineCaroPage` giữ một stream duy nhất. `AppStore.dispose` hủy `_authSubscription`. Cần xác nhận bằng DevTools rằng channel realtime được gỡ khi thoát chat (TC-CHT-12).

---

## 5. Bước 5 – Báo cáo lỗi

| Mã bug | Tiêu đề | Mức độ | Chức năng | Các bước tái hiện | Kết quả thực tế | Kết quả mong đợi | Nguyên nhân dự đoán | Hướng sửa |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| BUG-01 | **[ĐÃ SỬA – migration 005]** Người dùng gửi được điểm giả lên bảng xếp hạng | **Critical** | Xếp hạng / Bảo mật | 1) Đăng nhập lấy access token 2) `POST {SUPABASE_URL}/rest/v1/game_results` với header `apikey` + `Authorization: Bearer <token>`, body `{"id":"<uuid>","user_id":"<uid mình>","game":"sudoku","difficulty":"hard","seconds":0,"mistakes":0,"moves":0,"outcome":"win","played_at":"<now>"}` | Bản ghi 6000 điểm, đứng hạng 1. Có thể gửi không giới hạn số lần | Bị từ chối hoặc bị loại vì không hợp lý | Policy `results_insert` chỉ kiểm `user_id`; client tự khai thời gian/lỗi/kết quả | Thu hồi `insert` trực tiếp; thêm RPC `start_solo_game(game, level)` lưu `started_at` ở server và `finish_solo_game(session_id, mistakes, moves, proof)` tự tính thời gian; đặt thời gian tối thiểu theo game/mức; giới hạn số lần gửi mỗi phút. Với Sudoku có thể dùng lại cơ chế thách đấu (server giữ đề, kiểm đáp án) |
| BUG-02 | **[ĐÃ SỬA – negamax alpha-beta]** AI Caro mức Khó không mạnh hơn mức Vừa; không biết tấn công khi cả hai có 3 mở | **Major** | Caro | 1) Chạy `probe2.dart` (200 ván Khó vs Vừa) 2) Hoặc bày thế: máy có 3 mở hàng 3, người có 3 mở hàng 10, đến lượt máy | Khó thắng 16, Vừa thắng 25 (luật chặn hai đầu); máy chặn ở (10,4) thay vì đi (3,4)/(3,8) để có 4 mở | Khó thắng Vừa ≥70%; máy tạo 4 mở để thắng | Trọng số phòng thủ 1.1, “2 lớp” không đệ quy, đánh giá không phân biệt thế mở/bị chặn | Negamax alpha-beta (mục R1), thứ tự ưu tiên mối đe dọa, test đối đầu tự động |
| BUG-03 | **[ĐÃ SỬA – chấm theo kỹ thuật, migration 007]** Mức độ khó Sudoku chỉ khác số ô gợi ý | **Major** | Sudoku | Chạy `probe3.dart`: giải 100 đề mỗi mức chỉ bằng single | 74/100 đề Khó giải được chỉ bằng single; đề Khó thách đấu có 17 ô còn đề Khó chơi đơn có 28 ô | Mỗi mức đòi hỏi kỹ thuật khác nhau; cùng một thang cho chơi đơn và thách đấu | Chỉ đục ô tới số ô đích; ba đề thách đấu chọn tay | Hàm `grade()` theo kỹ thuật (mục R2); thay đề thách đấu bằng đề có cùng `grade` |
| BUG-04 | **[ĐÃ SỬA – khóa 2 giây/bước + ngưỡng server]** Điểm Rubik đạt ~980 chỉ bằng bấm nút liên tục | Minor (trước đây Major) | Rubik / Tính điểm | 1) Giải 1 khối 20 bước 2) Bấm “Đã xoay xong” 20 lần trong 10 giây | 980 điểm trong lịch sử máy và tổng điểm header; **không còn lên bảng online** (server đòi ≥2 giây/bước) | Không cho điểm cao khi chưa thật sự xoay | Thời gian = thời gian bấm; lỗi tự khai | Thời gian tối thiểu mỗi bước, quét xác nhận cuối ván, hoặc không đưa Rubik lên bảng online (mục R6) |
| BUG-05 | **[ĐÃ SỬA – migration 006]** Thách đấu không hết hạn, không đầu hàng; ván treo khi một bên bỏ đi | **Major** | Thách đấu | 1) A thách đấu Caro B, B chấp nhận 2) A đi 1 nước 3) B gỡ app | A thấy “Đang chờ B đi…” vĩnh viễn; lời mời chờ không bao giờ hết hạn; Sudoku một bên không nộp thì không bao giờ `completed` | Có hạn trả lời lời mời, hạn mỗi lượt, nút Đầu hàng; người còn lại được xử thắng | Schema không có `expires_at`/`turn_deadline`, không có RPC đầu hàng | Mục R12 |
| BUG-06 | **[ĐÃ SỬA]** Đăng ký email đã tồn tại báo “Hãy mở email xác nhận” | **Major** | Đăng ký | Đăng ký lại bằng email đã có tài khoản đã xác nhận | Thông báo như đăng ký mới; không có email nào đến | “Email này đã được sử dụng” hoặc thông báo trung lập kèm gợi ý đăng nhập/đặt lại mật khẩu | Supabase trả `identities: []` thay vì lỗi khi bật xác nhận email | Mục R7 |
| BUG-07 | **[ĐÃ SỬA]** Không có chức năng quên mật khẩu | **Major** (khi chấm) | Đăng nhập | Tìm “Quên mật khẩu” ở màn đăng nhập | Không có | Gửi email đặt lại và đặt mật khẩu mới | Chưa làm | Mục R8 |
| BUG-08 | **[ĐÃ SỬA – migration 008]** Sàn 100 điểm làm sai thứ tự xếp hạng | Minor | Tính điểm | Sudoku Dễ: A 1000 giây 0 lỗi; B 990 giây 30 lỗi | Cả hai 100 điểm; B xếp trên A | A xếp trên B | `max(100, …)` cộng 2 điểm/giây chung cho mọi game | Thời gian chuẩn theo game/mức, giảm mượt (mục R5) |
| BUG-09 | **[ĐÃ SỬA]** Tin nhắn nhiều emoji bị chặn im lặng | Minor | Chat | Dán 1500 emoji 😀, bấm Gửi | Không gửi, không có thông báo | Gửi được (≤2000 code point) hoặc báo rõ lý do | So sánh `String.length` (UTF-16) với giới hạn tính theo ký tự | `body.runes.length > 2000` + hiện lỗi (mục R9) |
| BUG-10 | **[ĐÃ SỬA]** Bàn phím đóng sau mỗi tin nhắn | Minor | Chat | Gửi một tin | Bàn phím đóng, phải chạm lại ô nhập | Bàn phím vẫn mở | `enabled: !_sending` làm mất focus | `readOnly: _sending` (mục R10) |
| BUG-11 | **[ĐÃ SỬA]** Xóa rồi nhập lại cùng số sai bị tính thêm lỗi | Minor | Sudoku | Ô trống: nhập 5 (sai) → Xóa → nhập 5 | Lỗi = 2 | Lỗi = 1 (giống khi nhập lại mà không xóa) | Chỉ so với giá trị đang có trên ô | Lưu tập số sai đã thử theo ô (mục R4) |
| BUG-12 | **[ĐÃ SỬA]** Ảnh mẫu không khớp ảnh ghép khi ảnh không vuông | Minor | Xếp hình | Chọn ảnh 16:9 từ thư viện → Xem ảnh hoàn chỉnh | Ảnh mẫu là ảnh đầy đủ 16:9; mảnh ghép chỉ là phần giữa hình vuông | Ảnh mẫu là đúng phần vuông được ghép | Mẫu và mảnh dùng hai cách cắt khác nhau | Mục R15 |
| BUG-13 | **[ĐÃ SỬA]** Rubik: đang tạm dừng thì nút “Đã xoay xong” không phản hồi | Minor | Rubik | Mở lời giải → Tạm dừng → bấm “Đã xoay xong” | Không có gì xảy ra, không giải thích | Nút bị khóa kèm chữ “Đang tạm dừng”, hoặc phủ màn tạm dừng | `_next` `return` im lặng khi `paused` | `onPressed: done or paused ? null : _next` + nhãn trạng thái |
| BUG-14 | **[ĐÃ SỬA]** Bằng điểm xếp theo `user_id` thay vì ai đạt trước | Minor | Xếp hạng | Hai tài khoản cùng điểm, giây, lỗi | Thứ tự phụ thuộc UUID | Người đạt trước xếp trên | Tiêu chí cuối `.order('user_id')` | Mục R14 |
| BUG-15 | **[CHẤP NHẬN RỦI RO – không sửa]** Người chơi giải Sudoku trên chính điện thoại của mình, nên ai sửa được app để khai 0 lỗi cũng chạy được bộ giải tự động và nhập đúng ngay từ đầu (0 lỗi thật). Đếm lỗi ở server sẽ thêm một request mỗi lần nhập mà không chặn được kiểu gian lận đó; thời gian vẫn do server đo. Thách đấu Sudoku tin số lỗi từ client | Minor | Thách đấu | Gọi `submit_challenge` với đáp án đúng, `error_count: 0` sau nhiều lần nhập sai | Được tính 0 lỗi | Server tự ghi nhận lỗi | Lỗi chỉ được đếm ở client | RPC `challenge_move(challenge_id, cell, value)` ghi từng nước; server tự đếm lỗi |
| BUG-16 | **[ĐÃ SỬA – migration 006]** `start_challenge`/`submit_challenge` nhận cả thử thách Caro | Minor | Thách đấu / Bảo mật | Gọi hai RPC với id của thử thách Caro đang diễn ra | Tạo `challenge_runs` cho thử thách Caro | Bị từ chối | Không kiểm `c.game` | Mục R13 |
| BUG-17 | **[ĐÃ XỬ LÝ – ghi rõ chỉ hỗ trợ giao diện sáng]** Không hỗ trợ dark mode | Minor | Giao diện | Bật dark mode hệ thống | App vẫn sáng; màu hard-code | Có `darkTheme` hoặc ghi rõ là cố ý chỉ hỗ trợ giao diện sáng | Chỉ có `AppTheme.light` | Thêm `darkTheme`, chuyển màu hard-code vào `AppColors`/`ColorScheme` |
| BUG-18 | **[ĐÃ SỬA]** Email tiếng Việt có dấu báo lỗi chung chung | Trivial | Đăng ký | Đăng ký `nguyễn@gmail.com` | “Không thực hiện được yêu cầu tài khoản…” | “Email chưa hợp lệ.” ngay ở form | Regex client quá lỏng; mã lỗi server không được ánh xạ | Regex chỉ nhận ASCII cho phần tên; ánh xạ `email_address_invalid`/`validation_failed` |
| BUG-19 | **[ĐÃ SỬA]** Xếp hạng không hiện hạng của mình khi ngoài top 50 | Trivial | Xếp hạng | Tài khoản hạng 51+ mở bảng online | Không thấy mình | Dòng “Hạng của bạn: #N” | `.limit(50)`, không có truy vấn hạng | RPC `my_rank(game, level)` dùng `rank() over (...)` |
| BUG-20 | **[ĐÃ SỬA]** Không đánh dấu 5 quân thắng ở Caro | Trivial | Caro | Thua máy | Dialog hiện ngay, không thấy đường thắng | Tô sáng 5 quân thắng trước khi hiện dialog | Không lưu dãy thắng | `hasFive` trả về danh sách ô; tô màu rồi hiện dialog |
| BUG-21 | **[ĐÃ SỬA – tìm thấy khi viết test]** Bảng xếp hạng online không hiện trên bản debug | Major | Xếp hạng | Bản debug: Xếp hạng → bấm “Người chơi online” | Console báo “setState() callback argument returned a Future”, màn hình không vẽ lại nên không hiện danh sách | Danh sách hiện ra | `_reload` dùng `setState(() => _request = …)`; arrow trả về `Future` nên Flutter ném lỗi ở chế độ debug và bỏ qua lần vẽ lại (bản release không bị) | Thân hàm dạng khối `{ … }`; widget test mới bắt được lỗi này |
| BUG-22 | **[ĐÃ SỬA – tìm thấy khi viết test]** Chat đóng bàn phím mỗi khi hiện dòng lỗi | Minor | Chat | Gửi tin khi mất mạng hoặc tin quá dài | Dòng lỗi hiện ra, ô nhập mất focus, bàn phím đóng | Bàn phím vẫn mở | Dòng lỗi chèn vào `Column` phía trên ô nhập cùng kiểu `Padding`, Flutter dùng lại element và tạo ô nhập mới | Gắn `ValueKey('chat-input')` cho vùng nhập |

---

## 6. Bước 6 – Đánh giá tổng kết

### 6.1 Điểm dự kiến

| Mục | Điểm tối đa | Dự kiến | Lý do trừ điểm |
| --- | --- | --- | --- |
| 1. Đăng ký/đăng nhập | 2 | **2,0** | Sau khi sửa BUG-06, 07, 18 và quy tắc mật khẩu (lúc đầu: 1,5). Rủi ro: luồng email thật chưa được thử trên thiết bị. |
| 2a. Rubik | 2 | **2,0** | Sau khi sửa BUG-04 (trước khi sửa: 1,75): bộ giải đúng, có xác minh, báo lỗi đúng mọi loại trạng thái không hợp lệ, 3D từng bước, điểm không còn bấm cho xong được. Rủi ro nhỏ: lỗi xoay sai vẫn tự khai. |
| 2b. Sudoku | 2 | **2,0** | Sau khi sửa BUG-03, R3, BUG-11 (lúc đầu: 1,5): độ khó theo kỹ thuật, không lộ đáp án, đếm lỗi nhất quán. |
| 2c. Xếp hình | 1 | **1,0** | Sau khi sửa BUG-12 (lúc đầu: 0,75). Còn tranh luận được: chạm nhầm ô không kề tính lỗi (lựa chọn thiết kế, nên giải thích trong báo cáo đồ án). |
| 2d. Caro | 1 | **1,0** | Sau khi sửa: 3 mức khác biệt đo được (Khó thắng Vừa 71%, thắng Dễ 100%), negamax alpha-beta, luật chặn hai đầu, điều kiện thắng đúng. Trước khi sửa: 0,5. |
| 3. Tính điểm | 1 | **1,0** | Sau khi sửa BUG-08 (trước khi sửa: 0,75): thời gian chuẩn từng game/mức, không sàn, client = DB. Rủi ro nhỏ còn lại: Caro không có lỗi, lỗi Rubik tự khai. |
| 4. Xếp hạng | 2 | **2,0** | Sau khi sửa BUG-01, 14, 19, 21 (lúc đầu: 1,25). |
| 5. Thách đấu | bắt buộc | Đạt | Sau khi sửa BUG-05: có hết hạn, đầu hàng, đồng hồ lượt; cùng đề, server tính giờ, khóa khi nộp đồng thời. Đã thêm hủy lời mời. Còn nhỏ: số lỗi do client khai. |
| 6. Chat | bắt buộc | Đạt | Realtime, RLS đúng, gửi lại không trùng, giới hạn độ dài đúng, giữ bàn phím. |
| **Tổng** | **11** | **11 / 11** về mặt code (lúc bắt đầu rà soát: 8,0) | Đây là điểm *nếu demo chạy đúng như test*. Rủi ro còn lại không nằm ở code mà ở môi trường: migration 004–010 phải được chạy trên Supabase thật, và các luồng mạng (email, Realtime, hai máy) chưa được thử trên thiết bị sau các lần sửa. Xem mục 6.2. |

### 6.2 Việc còn lại trước khi nộp

Mọi bug trong bảng ở mục 5 đã được sửa, trừ BUG-15 (chấp nhận rủi ro, lý do ghi ngay trong dòng bug) và BUG-17 (cố ý chỉ hỗ trợ giao diện sáng). Phần còn lại là **kiểm chứng trên môi trường thật**, vì test tự động không thay được:

1. **Chạy migration 004 → 010** theo thứ tự trên project Supabase thật (xem `docs/SUPABASE_SETUP.md`). Thiếu file nào thì chức năng tương ứng sẽ báo lỗi.
2. **Hai điện thoại thật:** chat realtime; thách đấu Sudoku (cùng đề, nộp, xem người thắng); Caro online (đồng hồ 60 giây, đầu hàng, hết giờ, hủy lời mời).
3. **Email thật:** đăng ký, đăng ký trùng email, quên mật khẩu → mở link trên cùng điện thoại → đặt mật khẩu mới.
4. **Bảng xếp hạng online:** chơi 1 ván khi đăng nhập và có mạng → điểm trong lịch sử trùng với điểm trên bảng; ván chơi offline ghi “không xếp hạng”.
5. **Rubik bằng camera** trên máy thật, làm theo lời giải với khối thật.

Những điểm nên giải thích trong báo cáo đồ án (lựa chọn thiết kế, không phải lỗi): luật Caro chặn hai đầu, lỗi Sudoku tính theo luật trùng, chạm ô không kề ở xếp hình tính lỗi, Caro không có khái niệm lỗi, lỗi Rubik do người chơi tự khai, giao diện chỉ có chế độ sáng.

### 6.3 Gợi ý để đạt điểm tối đa

- Thêm test tự động cho các tiêu chí ở mục 4.0 (Khó thắng Vừa, `grade()` đúng mức, số đề nghiệm duy nhất) để giảng viên thấy kiểm chứng định lượng thay vì khẳng định.
- Viết trong báo cáo đồ án một bảng “Quyết định thiết kế”: luật Caro chặn hai đầu (mép bàn không tính), puzzle trượt là cách hiểu “xếp hình”, Rubik là gợi ý cho khối thật, điểm Rubik là luyện tập.
- Quay video demo hai máy (chat realtime, Caro online, nộp thách đấu cùng lúc) vì giảng viên khó dựng lại backend.
- Đổi `applicationId` khỏi `com.example.*`, thêm dark mode hoặc ghi rõ chỉ hỗ trợ giao diện sáng.
- Chạy `tool/backend_test` với các test bảo mật mới (BUG-01, BUG-15, BUG-16) để chứng minh đã vá.

### 6.4 Đã xác nhận và còn cần bổ sung

| Câu hỏi | Trả lời | Ảnh hưởng |
| --- | --- | --- |
| Mục 5, 6 có trong yêu cầu không | Có, bắt buộc | BUG-05 và hủy lời mời (TC-CHL-08) đã sửa |
| Cấu hình Supabase Auth | Chưa biết | Xem cách kiểm tra bên dưới |
| Luật chặn hai đầu | Không bắt buộc, nhóm chọn làm theo cách chơi Việt Nam | Đã cài (xem mục 0) |
| “Xếp hình” là gì | Puzzle ảnh trượt, nhóm xác nhận đúng yêu cầu | Không còn rủi ro cách hiểu |
| Bản iOS | Không cần | Bỏ khỏi phạm vi |

**Cách tự kiểm tra cấu hình Supabase** (ảnh hưởng tới TC-AUTH-05, 07, 12 và BUG-06):

1. Dashboard → **Authentication → Sign In / Providers → Email**: xem công tắc **Confirm email**. Nếu bật, Supabase trả user giả cho email trùng; bản sửa BUG-06 xử lý đúng trường hợp này. Nếu tắt, Supabase trả lỗi `user_already_exists`; app cũng báo đúng. Nếu tắt, Supabase trả lỗi `user_already_exists` và app báo đúng “Email này đã được sử dụng”.
2. Cùng trang đó: **Minimum password length** (mặc định 6; nên đặt 8 cho khớp form) và **Password requirements** (nên yêu cầu chữ + số).
3. Dashboard → **Authentication → Rate Limits**: ngưỡng đăng nhập sai để chạy TC-AUTH-12.
4. Dashboard → **SQL Editor**: chạy `select proname from pg_proc where proname in ('play_caro_move','create_game_challenge');` để chắc chắn đã chạy 002, sau đó chạy `004_caro_vietnam_rule.sql`.
