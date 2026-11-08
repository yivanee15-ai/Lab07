# Lab07 – NTT (n = 128, Q = 12289) with CDC (Handshake + FIFO)

* `docs/spec_understanding.md` – spec 完整流程、輸入輸出格式、例子（第一步）
* `docs/results.md` – 7 個版本的優化過程、結果表、風險與整合步驟（第二步）
* `designs/v1 … v7` – 每版 3 個提交檔（`DESIGN_MODULE.v / Handshake_syn.v / FIFO_syn.v`）
* `common/`, `00_TESTBED/`, `04_MEM/` – 自寫的 top、PATTERN/TESTBED、SRAM 行為模型（皆為對 spec 的假設，見 docs）
* `tools/` – golden 模型、pattern 產生器、ROM 產生器、regression、yosys 面積/時序 proxy

建議：先用 **V5**（標準 Handshake，面積最小）；Jasper CDC 通過後再考慮 V6 / V7（latency 再 −12% / −16%）。
