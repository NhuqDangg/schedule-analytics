# Nu_TKB — Hệ thống Phân tích Học vụ & Điều phối Phòng học (EIU)

Dự án môn MIS 443. Chủ: Oriana (Business Analyst, đang chuyển hướng sang Production Planning).
Tài liệu này tóm tắt TOÀN BỘ quyết định kỹ thuật và lịch sử sửa lỗi của dự án, để một
cuộc trò chuyện Claude mới có thể tiếp tục đúng mạch mà không cần giải thích lại từ đầu.

## 1. Bộ dữ liệu gốc

- File: `tkb__251.xlsx`, 2.005 dòng, 29 cột, học kỳ 251 (Sep-Dec 2025), 4 khoa.
- `SEMESTER_START = 2025-09-08` (Thứ 2, tuần nội bộ 1).
- 533 nhóm lớp thật (không phải 901 — "Nhóm" gốc gộp cả tổ thực hành, phải tách).

## 2. 8 lỗi dữ liệu/thiết kế gốc đã sửa (trước khi vào database)

| # | Lỗi | Sửa |
|---|---|---|
| 1 | `schedule_id` không phải PK thật | Gán PK trước khi explode |
| 2 | Bridge gây fanout khi join | Bridge trỏ `fact_schedule` có PK duy nhất |
| 3 | `reg_count` bị đếm trùng | Giữ ở grain gốc trong `fact_schedule` |
| 4 | `group_no` không chuẩn hoá ('01 02','g15'...) | Tách `group_code` + `combo_code`, 901→533 nhóm lớp |
| 5 | FK lệch kiểu ('1.0' vs '1') | Đọc `dtype=str`, `faculty_id` là VARCHAR |
| 6 | `dim_week` cũ = 65 dòng (khoảng ngày+bitmask), không phải tuần thật | `dim_week` mới 16 dòng + `fact_teaching_session` |
| 7 | 'U' bị coi là 1 thứ trong tuần | `is_scheduled = giờ×ngày×tuần > 0`, 'U' không sinh dòng |
| 8 | Fact không có đơn vị workload | Thêm `credits`, `credit_alloc` vào `fact_schedule` |

**Công thức TC quy đổi:** `credit_alloc = credits × (giờ dòng này / tổng giờ cả nhóm lớp)`.
Đã verify: tổng TC quy đổi = 1227.0, khớp đúng tổng TC các nhóm lớp có xếp lịch.

## 3. Schema cuối cùng — 12 bảng (xem file `01_schema_dim_fact.sql`)

Dimension: `dim_instructor`(230), `dim_course`(307), `dim_faculty`(5), `dim_major`(12),
`dim_room`(129), `dim_class`(101), `dim_week`(16), `dim_section`(533).
Fact: `fact_schedule`(2005, grain=1 dòng gốc), `fact_schedule_day`(2096, grain=dòng×thứ),
`fact_teaching_session`(10763, grain=dòng×thứ×tuần, có `session_date` thật).
Bridge: `bridge_class_schedule`(8924).

**Quy tắc truy vấn bắt buộc:**
- Tổng giờ dạy → `SUM` trên `fact_schedule_day` hoặc `fact_teaching_session`, KHÔNG BAO GIỜ trên `fact_schedule` (sẽ sai vì đó là grain theo dòng gốc, chưa nhân ngày/tuần).
- Tổng TC → `SUM(credit_alloc)` trên `fact_schedule`.
- Đếm số nhóm lớp/sĩ số/reg_count → chỉ trên `fact_schedule` (join `fact_schedule_day` sẽ nhân bản sai).
- Muốn theo tuần/ngày thật cụ thể → `fact_teaching_session`.

## 4. Kiến trúc dashboard

**Lý do chọn:** Oriana là BA, không rành code, cần kiến trúc gần như no-code.
- **Backend:** Supabase (PostgreSQL có sẵn REST API tự sinh qua PostgREST) — không cần tự viết server.
- **Frontend:** 1 file HTML/CSS/JS tĩnh (`index.html`, ~1100 dòng), gọi thẳng Supabase REST API bằng `fetch()`.
- **Hosting:** GitHub Pages, repo `NhuqDangg/schedule-analytics`, URL `https://nhuqdangg.github.io/schedule-analytics/`.
- **Deploy:** xoá `index.html` cũ trên GitHub → Add file → Upload files → file mới. Không dùng git CLI.

**Thông tin kết nối Supabase (đã nhúng sẵn trong `index.html`, là anon key công khai,
không phải secret):**
```
SUPABASE_URL = "https://turtugkqxwgxljvjkgbe.supabase.co"
SUPABASE_ANON_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InR1cnR1Z2txeHdneGxqdmprZ2JlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTAyMzY3MjgsImV4cCI6MjEwNTgxMjcyOH0.OVWg2Ct3mNFSEcF9x-n2mcBk4wGsYyAKwn1utYZl5l8"
```

## 5. Nguyên tắc thiết kế xuyên suốt (áp dụng khi sửa/thêm bất cứ gì)

1. **1 quy tắc nghiệp vụ = 1 nơi duy nhất trong SQL**, frontend chỉ hiển thị, không tự tính
   lại. Đã từng vi phạm 2 lần (logic trùng lịch, phân loại tòa nhà) và phải gộp lại.
2. **Ngưỡng/phân loại phải tính từ phân vị dữ liệu thật**, không hardcode số cố định, và
   phải ghi rõ trên UI đây là thống kê chứ không phải quy định chính thức.
3. **So sánh công bằng:** dùng trung bình/tỷ lệ, không dùng tổng thô, khi các nhóm so sánh
   có quy mô khác nhau (số phòng, số người) — bài học từ việc bản gốc so sai lệch 12.2 lần.
4. **Luôn kiểm tra bằng dữ liệu thật trước khi kết luận** — nhiều "lỗi" hoá ra là dữ liệu
   đúng (ví dụ ca NURFT032 tưởng trùng lịch nhưng thực ra 2 môn học ở 2 khoảng tuần khác nhau).
5. **Loại support staff / địa điểm đặc biệt khỏi mọi bảng xếp hạng GV/phòng**, nhưng vẫn
   hiển thị minh bạch (không âm thầm xoá) — xem mục 7 và 8 bên dưới.

## 6. Lịch sử lỗi đã phát hiện & sửa trong lúc build dashboard (theo thời gian)

1. **Chart.js không load qua CDN cdnjs** → đổi sang `cdn.jsdelivr.net`, thêm kiểm tra
   `typeof Chart === 'undefined'` trước khi dùng.
2. **File index.html không hiện tab Workload dù không lỗi console** → do
   `target.style.display = ""` không đủ mạnh ghi đè luật CSS `display:none` có sẵn trong
   stylesheet (inline rỗng không override được rule ngoài) → sửa thành
   `target.style.display = "block"`.
3. **"Nguyễn Phan Thanh Xuân" (0 giờ) đứng đầu Top 8 giảng viên** → do gọi API
   `v_top_instructors` chỉ có `limit=8` mà thiếu `order=total_hours.desc` tường minh;
   PostgREST không đảm bảo giữ `ORDER BY` trong view khi có `LIMIT` từ REST.
4. **Trùng lịch báo giả (NURFT032, BSC 205 ∩ SNG 421)** → logic cũ so theo "cùng thứ +
   giờ", không kiểm tra 2 môn có thật sự cùng tuần/cùng ngày không → sửa thành so theo
   `session_date` thật. Một ca khác (CITFT022, CSW 306 ∩ ICPC 200, 9 lần) xác nhận là trùng thật.
3b. Ca NURFT032 mới nhất sau sửa lại phát hiện 1 cặp khác thật sự trùng (BSC 205 ∩ SNG 421,
   26/11/2025) — khác với ca cũ (cũng NURFT032 nhưng khác cặp cụ thể) đã xác nhận không trùng.
5. **Xung đột phòng báo giả (BIH, FABLAB, 200.B03)** → thực chất là dùng chung có chủ đích
   (thực tập chung bệnh viện, chung thiết bị lab, gộp lớp định hướng) → tạo bảng
   `room_share_confirmed` để xác nhận thủ công 1 lần, hệ thống nhớ mãi về sau.
6. **Donut "Ngoài phòng học" gộp nhầm phòng thật** → RAINTREE/BAMBOO/SYCAMORE là phòng
   thật thuộc Tòa B08 (gần 900 giờ dạy thật), không phải "khác". Xác nhận thủ công toàn bộ
   12 địa điểm đặc biệt với người quản lý, viết thành hàm `classify_room_building()`.
7. **Thư viện (LIB) đứng đầu "tòa còn dư chỗ nhất"** → sai vì LIB chỉ phục vụ đúng 1 môn
   (FEXP 2 - làm quen thư viện), không phải phòng học linh hoạt → tách riêng khỏi so sánh
   5 tòa, dù vẫn trong khuôn viên trường (khác nhóm "ngoài trường").
8. **Thủ thư (LIB001) đứng #1 "Top giảng viên" tuần 2** → `v_week_instructor_hours` không
   loại 12 mã nhân viên hỗ trợ → thêm điều kiện loại trừ, áp dụng luôn cho `v_week_summary.so_gv`.
   Tương tự `v_week_room_hours` từng để lọt BIH (bệnh viện) vào "Top phòng" → lọc theo
   `classify_room_building(...) LIKE 'Tòa %'`.
9. **Tuần 1-4 hiển thị sai** → đối chiếu lịch chính thức "Kế hoạch giảng dạy 2025-2026" của
   trường: tuần nội bộ 1-4 = Ori 1-4 (sinh hoạt định hướng), tuần nội bộ 5-16 = Tuần học
   1-12 của Học kỳ 1 (Tuần 11-12 là tuần thi). Ban đầu sửa nhãn ở JS, sau đó theo yêu cầu
   của Oriana (mục tiêu dự án là có database chuẩn, không phải vá ở hiển thị) đã chuyển
   hẳn sang bảng `hoc_ky_week_map` trong SQL — JS giờ chỉ đọc `nhan_hien_thi` có sẵn.
10. **Modal lịch cá nhân tự tính lại trùng lịch bằng JS** (bản sao của `v_conflicts`) →
    gộp lại, modal giờ gọi thẳng `v_conflicts?loai=eq.GV&key_id=eq.<id>`.

## 7. Nhân sự đặc biệt — 12 mã nhân viên hỗ trợ (KHÔNG phải giảng viên)

Tiền tố: `LIB, OCE, AAO, AMC, BOM, OSA, OIL` (ví dụ LIB001 = thủ thư Nguyễn Hồng Vũ).
Nguyên tắc: **vẫn hiển thị** trong tab Đánh giá giảng viên (đánh dấu riêng "Nhân viên hỗ
trợ", không xếp vào 4 nhóm phân loại workload), nhưng **loại khỏi** mọi bảng xếp hạng
"Top giảng viên" và khỏi tính trung vị workload của giảng viên thật.

Phân biệt loại hợp đồng (đã xác nhận bằng dữ liệu thật, mẫu đủ lớn để so sánh công bằng):
- Cơ hữu (FT): 183 người — trung vị 3 nhóm lớp / 80 giờ / 8 TC
- Thỉnh giảng (PT): 35 người — trung vị 1 nhóm lớp / 60 giờ / 5.87 TC
→ Ngưỡng phân loại workload tính RIÊNG cho từng nhóm, không dùng 1 ngưỡng chung.

## 8. Địa điểm đặc biệt — đã xác nhận thủ công với người quản lý (không phải suy đoán)

| Địa điểm | Phân loại | Thuộc khuôn viên? |
|---|---|---|
| RAINTREE, BAMBOO, SYCAMORE | Phòng thật, thuộc Tòa B08 | Có |
| LIB (thư viện) | Phòng chức năng đặc biệt, chỉ phục vụ môn FEXP 2 | Có (nhưng tách khỏi so sánh "Tòa") |
| AMC.A / A102 / A106 | Khu nhà xưởng nghiên cứu sản xuất tiên tiến | **Không** |
| BKB 1, BMT 1, TEN 1, VLB 1, FB 1 | Khu thể thao thành phố mới (bóng rổ/cầu lông/tennis/bóng chuyền/bóng đá) | **Không** |
| BIH, BV BINHDUONG | 2 bệnh viện thực tập lâm sàng | **Không** |
| ONLINE1/2/3 | Lớp học online | Không áp dụng (không có giới hạn vật lý) |

5 tòa thật dùng để so sánh: **B03, B04 không tính (xem trên), B06, B08, B10, B11** →
thực chất chỉ còn **B03, B06, B08, B10, B11** (5 tòa).

## 9. Lịch học chính thức EIU năm học 2025-2026 (đã xác nhận bằng ảnh lịch gốc)

- Ori 1-4: 08/09 - 04/10/2025 (sinh hoạt định hướng) = tuần nội bộ 1-4.
- Học kỳ 1 (= Học kỳ 251 của dự án), Tuần học 1-12: bắt đầu 06/10/2025 = tuần nội bộ 5-16.
- Tuần học 11-12 (tuần nội bộ 15-16) = Tuần thi.
- Đã verify bằng dữ liệu: 251/264 môn học kỳ chính bắt đầu đúng tuần nội bộ 5; giờ dạy
  tuần nội bộ 15-16 giảm mạnh còn 80 và 40 giờ, khớp đúng giai đoạn thi.
- Nhãn lưu trong bảng `hoc_ky_week_map`, khoá theo `hoc_ky = 'HK1_2025-2026'`.

## 10. Việc còn mở / để làm sau (chưa cần làm ngay, chỉ ghi nhớ)

- **Đa học kỳ:** hiện schema KHÔNG có cột phân biệt học kỳ trong các bảng fact — nếu
  thêm dữ liệu HK2, `week_no=5` của HK1 và HK2 sẽ lẫn vào nhau. Cần thêm cột `hoc_ky`
  vào `fact_schedule`/`fact_schedule_day`/`fact_teaching_session`/`dim_section`, biến khoá
  chính `week_no` thành khoá kép `(hoc_ky, week_no)`. **Phải làm đúng 1 lần khi có dữ liệu
  HK2 thật**, không nên làm trước khi có dữ liệu để tránh đoán sai cấu trúc.
- **Xung đột phòng trong tab Theo tuần:** hiện tab "Theo tuần" (chi tiết theo 1 tuần cụ
  thể) chỉ hiện xung đột GV, chưa hiện xung đột phòng (dù `v_conflicts` đã có sẵn, chỉ cần
  thêm 1 danh sách nhỏ nữa trong phần chi tiết tuần).
- **12 mã nhân viên hỗ trợ:** đã xử lý xong ở Workload + Theo tuần, nhưng CHƯA kiểm tra họ
  có bị lẫn vào `v_top_instructors` (Top 8 ở tab Tổng quan) hay không — nên rà soát.
- **`Số cho đk` (reg_limit) và `combo_code`/`combo_seq`:** ý nghĩa chính xác (sĩ số tối đa
  hay chỗ còn trống?) chưa được xác nhận từ đầu dự án, vẫn còn treo.

## 11. File đính kèm trong gói này

- `01_schema_dim_fact.sql` — DDL 12 bảng gốc (dimension/fact/bridge), tái tạo theo đúng
  thiết kế đã chốt. Đã test chạy sạch trên Postgres trắng.
- `02_dashboard_views.sql` — toàn bộ view/function/bảng phục vụ dashboard, đúng bản ĐANG
  CHẠY THẬT trên Supabase, đúng thứ tự phụ thuộc. Đã test chạy sạch trên Postgres trắng
  (trừ dòng GRANT cuối cần role `anon`/`authenticated` chỉ có trên Supabase).
- `index.html` — file dashboard hoàn chỉnh, 5 tab, đang chạy thật tại
  `https://nhuqdangg.github.io/schedule-analytics/`.

## 12. Cách dùng gói này trong cuộc trò chuyện mới

Upload cả 3 file, nói rõ: "đây là tiếp nối dự án Nu_TKB, đọc PROJECT_CONTEXT.md trước
rồi giúp tôi [việc cần làm]". Claude mới sẽ có đủ ngữ cảnh để không hỏi lại từ đầu, không
đề xuất lại các hướng đã thử và loại bỏ, và tiếp tục đúng theo các nguyên tắc ở mục 5.
