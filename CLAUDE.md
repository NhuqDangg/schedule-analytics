# CLAUDE.md — Nu_TKB (schedule-analytics)

Đọc file này trước mọi việc. Người dùng là Business Analyst, nền lập trình hạn chế.
Trả lời bằng tiếng Việt, câu ngắn. Sau mỗi bước, nói rõ: đã đổi gì, vì sao, kiểm chứng bằng gì.
Gắn nhãn [SUY LUẬN] / [DỰ ĐOÁN] / [CHƯA XÁC MINH] cho mọi điều chưa kiểm bằng dữ liệu thật.

## Dự án
- Dashboard phân tích thời khoá biểu EIU (đồ án MIS 443).
- Stack: PostgreSQL (Supabase) → PostgREST → `index.html` (vanilla JS + Chart.js 4.4.4) → GitHub Pages.
- Hiện có dữ liệu kỳ **251**. Đang mở rộng thêm 252, 253, 254, 261 (Giai đoạn 1 – đa học kỳ).
- Frontend gọi Supabase qua một hàm duy nhất `fetchView(viewName, query)` trong `index.html`.

## Cấu trúc thư mục (mục tiêu)
```
index.html, README.md          # đã có
CLAUDE.md                      # file này
db/schema/01_schema_dim_fact.sql      # bản thiết kế gốc (từ gói dự án)
db/schema/02_dashboard_views.sql      # bản thiết kế gốc (từ gói dự án)
db/live/                       # định nghĩa THẬT đọc từ Supabase (nguồn sự thật)
db/migrations/NNN_ten.sql      # mọi thay đổi schema/view, đánh số tăng dần
etl/                           # script Python nạp dữ liệu
data/                          # file Excel (KHÔNG commit — đưa vào .gitignore)
docs/                          # tài liệu dự án
```

## Quy tắc an toàn (bắt buộc)
1. **Không chạy lệnh ghi (INSERT/UPDATE/DELETE/ALTER/DROP/CREATE) lên Supabase production
   nếu người dùng chưa duyệt rõ ràng trong phiên.** Mọi migration chạy trên database THỬ trước.
2. Mọi thay đổi schema/view là một file `db/migrations/NNN_*.sql`, commit từng bước.
   Không chạy SQL ghi lẻ ngoài file.
3. Connection string / mật khẩu database chỉ nằm trong `.env` (có trong `.gitignore`).
   Không in ra màn hình, không commit. Anon key trong `index.html` là công khai, được phép.
4. Trước khi sửa một bảng/view: đọc định nghĩa THẬT từ database
   (`pg_get_viewdef`, `information_schema.columns`, `pg_constraint`, `pg_depend`).
   Không đoán tên cột, tên ràng buộc, view phụ thuộc. `db/schema/` có thể đã lệch so với live.
5. `CREATE OR REPLACE VIEW` chỉ được thêm cột vào CUỐI. Đổi thứ tự/tên cột → `DROP VIEW` rồi tạo lại,
   và phải tạo lại cả các view phụ thuộc. Giữ nguyên tên + thứ tự cột mà frontend đang dùng.
6. Không đổi tên cột hay giá trị mà frontend đang đọc (vd `loai = 'GV' | 'Phòng'`, `da_xac_nhan`,
   `key_id`, `key_name`, `nhan_hien_thi`) trừ khi sửa `index.html` trong cùng một commit.
7. PROD_DATABASE_URL luôn kết nối ở chế độ chỉ đọc.

## 4 quy tắc truy vấn — không được vi phạm
1. **Tổng giờ dạy** = `SUM(total_hours)` từ `fact_schedule_day`, hoặc `SUM(hours)` từ `fact_teaching_session`
   (ở `fact_teaching_session` cột giờ tên là `hours`, không phải `total_hours`).
   KHÔNG BAO GIỜ tính từ `fact_schedule`.
2. **Tổng tín chỉ** = `SUM(credit_alloc)` từ `fact_schedule`.
3. **Xung đột lịch** = cùng `session_date` + khung giờ chồng nhau. KHÔNG so "cùng thứ + cùng ca".
4. **Không bao giờ cộng `credit_alloc` sau khi JOIN `fact_schedule_day`/`fact_teaching_session`.**
   Cần TC theo GV thì gộp theo `schedule_id` trước rồi mới nối.

## Nguyên tắc thiết kế
- Mỗi quy tắc nghiệp vụ nằm ở đúng 1 chỗ trong SQL; frontend chỉ hiển thị.
- `classify_room_building()` là nguồn duy nhất phân loại phòng.
- `v_conflicts` là nguồn duy nhất của logic xung đột; frontend không tự tính.
- Ngưỡng lấy từ dữ liệu (`percentile_cont(0.5)`), không hardcode.
- Nhân sự hỗ trợ (regex `^(LIB|OCE|AAO|AMC|BOM|OSA|OIL)`): hiện trong tab giảng viên (có nhãn),
  loại khỏi mọi xếp hạng và trung vị.
- PostgREST: khi dùng `limit` phải gửi kèm `order=...`; không dựa vào ORDER BY của view.

## 13 view frontend đang dùng (không được làm vỡ)
v_overview_kpi, v_hours_by_building, v_top_instructors, v_instructor_workload,
v_workload_thresholds_by_group, v_instructor_sessions, v_building_summary, v_room_detail,
v_offcampus_summary, v_week_summary, v_week_room_hours, v_week_instructor_hours, v_conflicts.
Ngoài ra có `mv_lecturer_workload` (materialized view, frontend không dùng, nhưng phụ thuộc bảng fact).

## Số kiểm chứng kỳ 251 (không được đổi sau bất kỳ migration nào)
| Chỉ số | Giá trị |
|---|---|
| `fact_schedule` | 2005 dòng |
| `fact_schedule_day` | 2096 dòng |
| `fact_teaching_session` | 10763 dòng |
| `ROUND(SUM(credit_alloc), 1)` | **1227.0** (giá trị thô 1226.9969 do `credit_alloc` lưu 4 chữ số thập phân) |
| Số tuần | 16 |

Lệch bất kỳ số nào → dừng, báo người dùng, không làm tiếp.
Kiểm chứng phải là truy vấn trả kết quả rõ ràng; lưu ý SELECT kiểm chứng KHÔNG tự chặn COMMIT.

## Mốc đối chiếu 5 kỳ (tính từ Excel gốc — HANDOFF_2026-10-21 mục 3)
Dùng để kiểm chứng sau khi nạp schema mới (phương án B).

| Kỳ  | Dòng  | Dòng-ngày | Buổi-tuần | Tổng giờ | Độ dài bitmask | Ngày bắt đầu (Thứ 2) |
|-----|-------|-----------|-----------|----------|----------------|----------------------|
| 251 | 2005  | 2095*     | 10763     | 30396    | 16             | 2025-09-08           |
| 252 | 1853  | 2044      | 9882      | 28400    | 14             | 2025-12-29           |
| 253 | 1924  | 1874      | 10329     | 29594    | 12             | 2026-04-06           |
| 254 | 1881  | 1971      | 8002      | 23980.5  | 14             | 2026-06-29           |
| 261 | 1845  | 2149      | 10899     | 29932    | 16             | 2026-09-07           |

- Cách tính: dòng-ngày = tổng số chữ thứ (bỏ `'U'`); buổi-tuần = thứ × số tuần (ký tự khác `'-'` trong bitmask);
  giờ = giờ/buổi × buổi-tuần. Chỉ tính dòng có giờ > 0, thứ > 0, tuần > 0.
- TC quy đổi 251: `ROUND(SUM(credit_alloc),1)` = 1227.0.
- \* 251: PROD có 2096 dòng-ngày, tính lại từ Excel ra 2095. Lệch 1 dòng, chưa giải thích
  (nghi 1 dòng ECE 110 có thứ nhưng không có tuần). **Việc cần kiểm khi nạp v2.**

## Schema thật (từ db/live, đọc ngày 2026-10-15)
`db/schema/` là bản thiết kế, đã lệch. Khi khác nhau, tin `db/live/`.
- `dim_section` có thêm `section_id` tự tăng (`nextval`, UNIQUE).
- `fact_schedule` nối `dim_section` qua `section_id` (khoá ngoại `fk_fs_section`).
- `dim_week` có CHECK `week_no` từ 1 đến 16.
- Độ dài cột: `instructor_id`, `course_id` = `varchar(20)`; `room_id` = `varchar(30)`; `combo_seq` = `varchar(10)`.
- `credits` là `smallint`; `credit_alloc` là `numeric(8,4)`.

## Sự thật về 4 kỳ mới (ETL chạy khô 2026-10-15)
- Số tuần: 251=16, 252=14, 253=12, 254=14, 261=16 → `dim_week` khoá `(hoc_ky, week_no)`, 72 dòng.
- 522/886 cặp `(course_id, group_code)` lặp giữa các kỳ → `dim_section` khoá `(hoc_ky, course_id, group_code)`.
- `fact_schedule.week_pattern` đang là `CHAR(16)` → đệm khoảng trắng với kỳ < 16 tuần. Đổi `VARCHAR`.
- `tkb_254.xlsx` tên cột không dấu → ETL đọc theo VỊ TRÍ cột (0..27), không theo tên.
- Cột Tổng số SV / Tiết BĐ / Số tiết / Thứ / Ghi chú: 100% NULL mọi kỳ. Thứ học nằm ở cột Buổi.
- `time_slot='-'` luôn đi với `day_pattern='U'` (chưa xếp lịch).
- 4 dòng có thứ học nhưng thiếu bitmask tuần (2 ở 252, 2 ở 254) → ETL phải log, không bỏ im lặng.
- Kỳ 254 (đến 03/10/2026) và 261 (từ 07/09/2026) chồng 26 ngày → `v_conflicts` KHÔNG lọc theo kỳ.
- Kỳ 261: ~40% dòng chưa có giảng viên (lịch tạm).
- `group_no` có dạng E1, V01, HNRS, CNTT, QTKD... — quy tắc cũ "tách theo khoảng trắng → group_code + combo" vẫn đúng.

## Hướng đa học kỳ ĐÃ CHỐT (2026-10-21)
- **Phương án B**: schema mới, nạp lại 5 kỳ từ Excel, dashboard cũ chạy song song.
- **Không sửa tại chỗ bảng hiện có.** Bản migration nháp 15/10 (thêm `hoc_ky` vào bảng cũ) đã bỏ.
- Các mục "Sự thật về 4 kỳ mới" và "Quy ước mã kỳ" bên dưới áp dụng cho schema mới.

## Lỗi đang tồn tại (chưa sửa)
- `v_instructor_workload` và `mv_lecturer_workload` nhân bản TC ~1,6 lần
  (vi phạm quy tắc truy vấn 4; chi tiết: HANDOFF_2026-10-21 mục 4.1).

## Quy ước mã kỳ (đã chốt 2026-10-21)
- Mã kỳ toàn hệ thống = chuỗi 3 ký tự theo tên file: `'251'`, `'252'`, `'253'`, `'254'`, `'261'`.
  Mọi cột `hoc_ky` (bảng, view, ETL) dùng mã này. Không dùng `'HK1_2025-2026'` cho dữ liệu mới.
- Tên kỳ cho người đọc nằm ở `dim_semester.ten_hien_thi` — nguồn duy nhất. Frontend chỉ hiển thị cột này,
  không tự ghép chuỗi từ mã kỳ.
- `dim_semester` CHƯA có trên live (kiểm 2026-10-21). Tạo trong schema mới bằng migration, khoá chính `hoc_ky`.
  Giá trị `ten_hien_thi` của từng kỳ: hỏi người dùng, không tự suy từ mã.
- Bảng/view hiện có (dashboard cũ) GIỮ NGUYÊN mã cũ, không chuyển đổi (phương án B):
  - `hoc_ky_week_map` có 16 dòng `hoc_ky = 'HK1_2025-2026'`; `v_week_summary` gắn cứng mã này trong JOIN.
    Không đổi sang `'251'` — đổi một bên mà quên bên kia thì cột `nhan_hien_thi` ra NULL.
  - Nhãn tuần cho 5 kỳ nằm trong schema mới, khoá `(hoc_ky, week_no)` với mã `'251'`...
  - Khi dashboard cũ ngừng chạy thì bỏ cả hai cùng lúc.

## Lỗi đã biết trong frontend (chưa sửa)
- Tab Theo tuần in xung đột từng dòng, không gộp cặp A/B như tab Xung đột (`groupConflictRows`).
- Dữ liệu chèn vào `innerHTML` không escape.
