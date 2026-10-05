# Antigravity Switcher (macOS) - Bảng theo dõi

Ký hiệu: ⬜ chưa làm · 🟨 đang làm · ✅ xong · ❌ fail, cần đổi hướng

**Đang ở đâu?** Tìm task ⬜ đầu tiên trong các file `tasks.md` theo thứ tự thư mục.

| Phase | Thư mục | Nội dung | Ai làm | Ước lượng | Trạng thái |
|---|---|---|---|---|---|
| Spec | `00-spec/` | Mục tiêu, phạm vi, kiến trúc, **thiết kế dễ update** | - | - | ✅ (v2) |
| P0 | `01-setup-P0/` | Chuẩn bị máy, cài đặt, backup | Bạn | 0,5 ngày | ⬜ |
| An toàn | `02-safety-security/` | Quy tắc tránh hại máy, checklist bảo mật | Mọi người | - | ⬜ |
| P1 | `03-research-P1/` | Khảo sát thực tế trên máy (cổng quan trọng nhất) | Bạn + AI | 1-2 ngày | ⬜ |
| P2 | `04-core-cli-P2/` | Lõi CLI: đọc/ghi session, backup, rollback | Codex | 2-3 ngày | ⬜ |
| P3 | `05-process-P3/` | Quit, launch, xác minh, switch | Codex | 1-2 ngày | ✅ |
| P4 | `06-proxy-P4/` | Proxy forwarder theo account | Codex | 3-4 ngày | ⬜ |
| P5 | `07-ui-P5/` | Menu bar + cửa sổ quản lý | Codex | 2-3 ngày | 🟨 |
| P6 | `08-packaging-P6/` | Ký, notarize, DMG, kiểm thử cuối | Bạn + Codex | 1-2 ngày | ⬜ |
| Rủi ro | `09-risks-fallback/` | Rủi ro và phương án dự phòng | - | - | - |
| Prompt | `10-prompts/` | Prompt giao cho Codex (viết sau P1) | Claude | - | ⬜ |
| Bảo trì | `11-maintenance/` | Quy trình khi Antigravity update, ma trận tương thích | Bạn | 10-30 phút/lần | ⬜ |

## Thay đổi v2: dễ update khi Antigravity update
Path, key, tên process, cờ launch nằm trong **manifest JSON**, không nằm trong code. App có `doctor`, `calibrate` (tự học key), `selftest`. Khi IDE update: chạy theo `11-maintenance/update-runbook.md` (thường 10-30 phút, không cần build lại). Chi tiết: `00-spec/03-update-resilience.md`.

## Quy tắc cổng (gate)
Chưa qua gate của phase trước thì **không** sang phase sau. P1 là gate quan trọng nhất: nếu hoán đổi token không ổn định, đổi sang phương án B (xem `09-risks-fallback/`).

## Cách làm việc
1. Xong task: đổi ⬜ thành ✅, commit git `feat(Tx.y): ...`.
2. Xong phase: chạy checklist gate, ghi kết quả vào `NOTES.md`.
3. Gặp lỗi: dừng, dán log (đã xóa token) cho Claude.
