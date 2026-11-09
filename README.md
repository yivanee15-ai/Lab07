# Lab07 – NTT (n = 128, Q = 12289) with CDC (Handshake + FIFO)

* `docs/spec_understanding.md` – spec 完整流程、輸入輸出格式、例子（第一步）
* `docs/results.md` – 7 個版本的優化過程、結果表、風險與整合步驟（第二步）
* `designs/v1 … v7` – 每版 3 個提交檔（`DESIGN_module.v`、`synchronizer/Handshake_syn.v`、`synchronizer/FIFO_syn.v`）
* `common/NTT_TOP.v`、`00_TESTBED/TESTBED.v`、`GMb.txt` 為 TA 提供；`PATTERN.v`、`04_MEM`（SRAM 行為模型）、`NDFF_*`（stand-in）為自寫
* `tools/` – golden 模型、pattern 產生器、ROM 產生器、regression、yosys 面積/時序 proxy

建議：先用 **V5**（標準 Handshake，面積最小）；Jasper CDC 通過後再考慮 V6 / V7（latency 再 −12% / −16%）。
