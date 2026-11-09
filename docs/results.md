# Lab07 NTT – 優化紀錄與結果

> **誠實聲明（先看這個）**
> * 本環境沒有 VCS / Design Compiler / PrimeTime / Jasper / TA 的 tar。功能驗證用 **iverilog**（RTL），
>   面積與時序只能用 **yosys + abc + 開源 Nangate45 liberty** 做「相對比較用的 proxy」，**不是** DC/PT 的數字，SRAM 巨集（固定不變）也沒算進去。
> * 沒有跑 gate-level 模擬、PrimeTime、Jasper CDC。**V6 / V7 因為改了 Handshake 結構，一定要先過 JG 再採用**（V1~V5 的 Handshake 是標準 Fig.5 結構）。
> * TA 的 `GMb.txt`、`NTT_TOP`、`CLK_x` 介面、SRAM 模型、PATTERN 都是自己依 spec 補的假設，見 `docs/spec_understanding.md` §7 與本文件 §5。

## 1. 結果總表（clk3 = 20.7 ns，100 組 pattern，4 種 clk3、多組隨機時脈相位全部通過）

| 版本 | latency (ns) | logic area (Nangate45 µm², 不含 SRAM) | FF 數 | abc 最長組合路徑 (ns) | latency×area（相對 V1） | 重點 |
|---|---|---|---|---|---|---|
| V1 | 9343.6 | 35,601 | 2453 | 5.23 | 1.000 | 基準：收滿 128 項再用一顆 butterfly 逐個算 |
| V2 | 4852.7 | 29,413 | 2514 | 1.65 | 0.429 | 7-stage radix-2 SDF pipeline、邊收邊算 |
| V3 | 4744.7 | 28,374 | 2414 | 1.46 | 0.405 | latency 微調：2 級 Montgomery、stage7 直通 FIFO、FIFO 1-cycle read |
| V4 | 4715.3 | 22,815 | 1857 | 1.49 | 0.323 | **面積**：radix-4 raw 前端（取代 stage1+2）、CLK1 ring buffer |
| V5 | 4711.7 | 20,472 | 1590 | 1.92 | 0.290 | **面積**：radix-8 raw 前端（取代 stage1~3），只剩 4 個乘法器 |
| V6 | 4128.2 | 20,531 | 1590 | 2.03 | 0.255 | V5 + Handshake fast-ack（**JG 未驗證**） |
| V7 | 3944.6 | 20,571 | 1591 | 1.96 | 0.244 | V6 + source 端改 falling edge（**JG 未驗證**） |

* 每一版都用 `tools/regress.sh` 驗證：4 個 clk3 週期 × 隨機初始相位 seed × 100 組 pattern（含全 0、全 15、單點 impulse、隨機），
  下一筆 1~3 個 clk1 cycle 後接著進來，out_valid/out_data 的零值規則、輸出筆數、latency < 5000 cycle 都由自寫 PATTERN 檢查。
* V6/V7 另外跑了 3000 組 pattern（約 45,000 次 handshake）+ 內建 overrun assertion，沒有觸發（word 間隔最小 8 個 clk2 cycle）。
* **最安全、最划算的選擇：V5（只用標準 Handshake 結構）；latency 想再壓就在 JG 通過後換 V6 / V7。**

> 單位換算：Nangate45 → 實際製程的面積倍率約 8×（130nm）。SRAM 不在表內，所以實際 Latency×Area 的改善幅度會被 SRAM 稀釋。
> `abc` 的延遲是「單純 mapping」估計；以 ~3.4× 換到 0.13µm 約 6~7 ns，10.1 ns 的 clk2 還有餘裕（V5~V7 最長路徑在 FRONT8 的 8 項加法 + 約化，
> 若 DC 回報不過，把 `DESIGN_MODULE.v` 內 `F8_PIPE` 設成 1 即可多插一級暫存器，已驗證功能正確，代價約 +10 ns latency）。

## 2. latency 組成（clk3 = 20.7 ns）

| 項目 (ns) | V1 | V2 | V3 | V4 | V5 | V6 | V7 |
|---|---|---|---|---|---|---|---|
| in_valid 落下 → 最後一個 word 進 clk2（Handshake 尾巴） | 2024 | 1842 | 1842 | 1842 | 1842 | 1256 | 1085 |
| 最後一個 word → 第一筆結果寫入 FIFO（NTT 尾巴） | 4535 | 263 | 192 | 172 | 152 | 151 | 151 |
| 寫入 FIFO → out_valid（FIFO 同步） | 103 | 107 | 53 | 53 | 52 | 58 | 64 |
| 128 筆輸出 × 20.7 | 2650 | 2650 | 2650 | 2650 | 2650 | 2650 | 2650 |
| 合計（`run_mon.sh`，2 筆 pattern 平均） | 9341 | 4862 | 4739 | 4725 | 4698 | 4128 | 3943 |

（V1 的 handshake 尾巴較長是因為它要等 16 個 word 收滿才開始送。）

`2650 ns` 的輸出時間與「16 個 word 各做一次 4-phase handshake」是 spec 決定的下限，其餘都是設計能動的部分。

## 3. 各版本做了什麼、為什麼

### V1（基準）
`CLK_1` 收滿 16 個 word 才開始送；`CLK_2` 用 128×14-bit 暫存器陣列、每 cycle 一個 butterfly（Montgomery 完全照 spec 寫）。功能參考，也拿來比對其他版本。

### V2（latency：邊收邊算 + SDF pipeline）
* 觀察：每個輸出都依賴全部輸入，但 **handshake 每個 word 要 ~131 ns（4-phase + 2 個 NDFF）**，16 個 word 要 ~2 µs，所以 CLK_2 必須在 word 進來時就開始算，最後一個 word 之後只剩「最後 8 個 sample + pipeline 深度」。
* CLK_1 用 shift register buffer，第一個 word 一進來就開始送（不等 16 個收滿）。
* CLK_2 是 radix-2 **SDF（single-path delay feedback）**：每個 stage 一條 delay line，stage 的位置完全由全域 tick 計數器 `g` 決定（不需要 valid bit），所有暫存器用同一個 `adv` 致能（輸入沒到、FIFO 滿就停）。
* stage 1 的第二運算元只有 4 bit → `modq_mul` 只有 16 種輸入，用 LUT 取代乘法器，delay line 只存 `{x[j+64], x[j]}` 兩個 nibble（8 bit，而不是 14 bit）。
* **Q = 12289 = 3·2¹²+1、Q0I = 12287 = 3·2¹²−1** → Montgomery 的 `y = x·Q0I mod 2¹⁶`、`y·Q` 都只要加減，不需要額外乘法器。
* 「乘 1」技巧：phase A 的樣本乘 Montgomery 的 1（R mod Q = 4091）直接穿過同一個乘法器 → 每個乘法器、每個暫存器每個 tick 都在工作（不用另外做 bypass 路徑）。

### V3（latency 微調）
* Montgomery 拆成 2 級：level 1 = 乘法 + `y`（1.35 ns），level 2 = 約化 + butterfly（1.21 ns），兩級很平衡；
  約化後不做 normalise（z < 1.19Q），butterfly 直接用 3-way 修正（比先 normalise 再 butterfly 快 0.6 ns、面積更小）。
* stage 7 的結果直接進 FIFO（少一級暫存器）。
* FIFO：`rempty` 改成組合邏輯，SRAM 用 **next head pointer** 當讀位址 → 讀出延遲由 2 cycle 變 1 cycle。

### V4（面積：radix-4 raw 前端 + ring buffer）
* 觀察：輸入只有 4 bit，前兩個 stage 可以直接在「原始 4-bit sample」上做：
  `y[32k+p] = x[p] + c1[k]·x[p+32] + c2[k]·x[p+64] + c3[k]·x[p+96] (mod Q)`，常數 c 都是固定值 → 每一項 = 16 項查表，**不需要乘法器**。
  4 條 32×4-bit 的 circulating row（每 tick 轉一格）剛好在每個 tick 把 4 個運算元送到 row head。這取代了原本 64×8-bit + 32×14-bit 的 delay line + stage 2 乘法器。
* CLK_1 的 buffer 改成「每個 cycle 都在轉」的 ring（沒有 hold mux），handshake 用 tap mux 讀，tap index 用 4-bit 暫存器追蹤。
  ring 只有 **14 個 word**：word 14、15 進來時會蓋掉最舊的 word 0、1，而它們早就送進 handshake 了（simulation assertion 監看；V4~V7、3000 組 pattern × 多組相位都沒觸發）。

### V5（面積：radix-8 raw 前端）
* 同樣的想法延伸到 3 個 stage：8 條 16×4-bit row、7 個常數表、8 項加法 + 約化。
* 觀察到 C[k][i] 在 k 上最多只有 4 種「大小」（只差正負號）→ 表只存 |c|·x 與 sign（用 `Q − m` 取負，與 0 在 mod Q 下等價），常數表面積約 −18%。
* 再往 radix-16 試算過：LUT 面積 ×3.6 > 省下的 stage，不划算。→ radix-8 是甜蜜點。只剩 stage 4~7 需要乘法器。

### V6 / V7（Handshake latency；**JG 未驗證**）
* V6：`dack = dreq`（組合 acknowledge，目的端少兩個 clk2 cycle/word），destination register 一個 cycle 後從 source data register 取值（source register 在下一次 accept 前都不會變）。
* V7：source 端（`sreq`、source data register）改用 **falling edge**，req 提早半個 clk1 cycle（每個相位 −7 ns）。CLK_1 改成在 `sack` 上升時 pop。
* 風險：dack 是組合別名、sreq 是 negedge flop，JG 的 handshake scheme（`ACK_WO_SREQ / NAK_WO_SREQ / NRQ_WO_DACK / REQ_NO_HOLD / DAT_HS_STBL`）是否接受我無法驗證。**先跑 05_JG，沒有 violation 才採用。**
  V6/V7 也不再使用 `dbusy`，靠「CLK_2 8 個 cycle 內一定吃完一個 word、word 間隔 ≥ 8 cycle」保證，內建 simulation assertion 監看。

## 4. 試過但放棄的方向（以及原因）

| 想法 | 為什麼放棄 |
|---|---|
| 多個 stage 共用乘法器 | 全速 SDF 下各 stage 的乘法時槽重疊，同時需求最多 5（stage 5~7 也最少 3，補 skew 暫存器也降不下去）；要共用只能把 tick 放慢成 2 cycle，latency +~6%，面積只省 ~9%，且控制複雜 |
| Handshake 改 2-phase / toggle | 會違反 JG handshake scheme 的 4-phase 檢查 |
| 全 pipeline 自由運轉（拿掉 hold mux） | 要靠「預估最後一個 word 到達時間」提早啟動，最壞情況 jitter 要留餘量 → 平均多等 ~90 ns，且 FIFO 64 深度裝不下 128 筆全速輸出，需另加 skid buffer；淨效益 ≲ 2% 不值得 |
| stage 內只用 1 級暫存器（L=1） | abc 估計單級 2.34 ns（→ 0.13µm ≈ 8 ns+FF 開銷），對 10.1 ns 太緊；只省 ~40 ns / 0.9k µm² |
| CLK_1 ring 縮成 13 word 以下 | word 2 在最慢的標準 handshake 下來不及送出，會被蓋掉（14 已是各版本通用的安全值） |
| 去掉 Handshake 的 source data register | din 隨 ring 位置變化時 mux 可能有 glitch，與 dest 取樣撞到 → 不安全 |

## 5. 整合到真正的作業環境（已對齊 TA 的 NTT_TOP.v）

`common/NTT_TOP.v` 現在就是 TA 的檔案原樣；`designs/vN/` 的結構與作業一致：

```
designs/vN/DESIGN_module.v                 -> 01_RTL/DESIGN_module.v
designs/vN/synchronizer/Handshake_syn.v    -> 01_RTL/synchronizer/Handshake_syn.v
designs/vN/synchronizer/FIFO_syn.v         -> 01_RTL/synchronizer/FIFO_syn.v
```

1. 只要把這三個檔案複製到 TA 範本對應位置（`NDFF_syn.v`、`NDFF_BUS_syn.v`、`NTT_TOP.v`、`TESTBED.v` 用 TA 的）。
   我的模組 port 已照 TA 的 `NTT_TOP.v` 命名（含 `flag_*`）。`NDFF_syn` 我假設 port 是 `.D .Q .clk .rst_n`、`NDFF_BUS_syn #(WIDTH)` 同樣，**請對照 TA 的實際檔案**。
2. flag 的用法：`flag_handshake_to_clk1` 用來把 Handshake 同步後的 acknowledge 帶回 CLK_1（V1、V7 會用到），其餘 flag 固定接 0。
3. `GMb.txt` 已用 TA 真檔重生所有 ROM 與 pattern；若更新檔案，重跑
   `python3 tools/gen_rom.py <GMb.txt> designs/v5/DESIGN_module.v`。
4. 必跑：`01_run_vcs_rtl`（4 種 clk3）→ `01_run_dc_shell`（slack ≥ 0、無 latch/error）→ `02_run_pt` → `03_run_vcs_gate` → `05_JG/01_run_jg`。
   若 DC 的 clk2 路徑不過：先把 `F8_PIPE` 設 1（FRONT8 多一級）。
5. 需要留意的結構風險（V3 起）：`FIFO_syn` 的 `rempty` 是組合邏輯（`rptr == wptr_s`）、SRAM 讀位址用 next-head pointer。
   若 Jasper / DC 對這兩點有意見，改回「registered rempty、位址 = rbin」即可（各多 1 個 clk3 cycle ≈ +21 ns latency，功能不變）。
6. SRAM 假設為 `DUAL_64X16X1BM1`，port A 寫（CKA=wclk）、port B 讀（CKB=rclk，輸出 DOB），已照 TA 的 FIFO_syn 模板，`WEAN/WEBN` active-low；
   FIFO 讀位址用 next-head，所以同位址讀寫時 SRAM 的 `MEM_Warning`（spec 已列為可接受）可能出現。

## 6. 復現指令

```bash
python3 tools/ntt_model.py                      # golden 模型自我驗證（含 radix-4/8/16 前端恆等式）
python3 tools/gen_pattern.py --n 100            # 產生 pattern（00_TESTBED/）
tools/run_sim.sh designs/v5 20.7 100            # 單一設計、單一 clk3
SEEDS="0 1 2" tools/regress.sh                  # 全部設計 × 4 種 clk3 × 隨機相位
tools/report.sh                                 # latency / 面積 proxy 總表
tools/synth_design.sh designs/v5                # yosys + Nangate45 面積與延遲 proxy
tools/synth_hier.sh designs/v5                  # 各子模組面積
tools/run_mon.sh designs/v7 20.7                # latency 時間軸（handshake / FIFO / out_valid）
```
