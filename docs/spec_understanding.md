# Lab07 – NTT (n = 128, Q = 12289) 規格理解與完整流程

> 本文件對應作業第一步：把 spec 讀懂、釐清「輸入 → 輸出」的完整流程，並舉簡單例子。
> 所有數字範例都由 `tools/toy_example.py` / `tools/ntt_model.py` 產生並自我驗證過。

## 1. 要做的事（一句話）

在 clk1 domain 收進一個 128 項、每項 4-bit 的多項式 `x[0..127]`，經 **Handshake synchronizer**
送到 clk2 domain，在 clk2 domain 用 **128 點 NTT（模 Q = 12289）** 算出 128 個 14-bit 結果，
把結果寫進 **FIFO synchronizer**（內含 TA 給的 64×16 dual-port SRAM），再從 clk3 domain 讀出，
連續（或不連續）輸出 128 筆 `out_data`。

```
 clk1                    clk2                                clk3
 PATTERN -> CLK_1_MODULE -> Handshake_syn -> CLK_2_MODULE -> FIFO_syn -> CLK_3_MODULE -> PATTERN
 in_valid/in_data (32b)      32b / 次         NTT (7 stage)    16b x 128     out_valid/out_data (16b)
```

| clock | 週期 | 用途 |
|---|---|---|
| clk1 | 14.1 ns | 輸入、Handshake 的 source 端 |
| clk2 | 10.1 ns | Handshake destination、NTT 運算、FIFO write |
| clk3 | 20.7 ns（RTL 另測 3.1 / 4.1 / 11.1） | FIFO read、輸出 |

## 2. 輸入格式

* `in_valid` 拉高 **16 個 clk1 cycle**；每個 cycle `in_data[31:0]` 帶 **8 個 4-bit 係數**。
* 低 index 放 LSB：cycle `c` 的 `in_data[4*i +: 4] = x[8*c + i]`（`i = 0..7`）。
* 係數範圍 0..15（4-bit），所以 128 項共 512 bit。

簡單例子：`x[i] = i mod 16`

```
cycle 0 : in_data = 0x76543210   (x0 = 0, x1 = 1, ... x7 = 7)
cycle 1 : in_data = 0xfedcba98   (x8 = 8, ... x15 = 15)
cycle 2 : in_data = 0x76543210   ...
```

## 3. 演算法（spec 的 pseudo code）

```
NTT(x):  t = 128
for (m = 1; m < 128; m *= 2)        // 7 個 stage
    ht = t/2
    for (i = 0, j1 = 0; i < m; i++, j1 += t)
        s = GMb[m + i]              // 由 GMb.txt 提供的 twiddle factor
        for (j = j1; j < j1 + ht; j++)
            u = x[j];  v = modq_mul(x[j+ht], s)
            x[j]    = (u + v) mod Q
            x[j+ht] = (u - v) mod Q          // (a-b) mod Q = a-b (a>=b) , a-b+Q (a<b)
    t = ht
```

`modq_mul(a,b)` 是 Montgomery 乘法，R = 2^16，Q = 12289，Q0I = 12287：

```
x = a*b ; y = (x*Q0I) mod R ; z = (x + y*Q)/R ; return z>=Q ? z-Q : z      // = a*b*R^-1 mod Q
```

重點觀察：

* 每個 stage 有 64 個 butterfly，共 7×64 = **448 個 butterfly**；stage s 的 butterfly 距離 `ht = 64,32,16,8,4,2,1`。
* 所有中間值都是 [0, Q) 的 canonical 值，所以輸出對「任何數學上等價的算法」都是唯一的 → 可以自由重排運算。
* `Q = 12289 = 3·2^12 + 1`，`Q0I = 12287 = 3·2^12 − 1`，Montgomery 的 `x*Q0I mod 2^16`、`y*Q` 都只需要加減與 shift，**不用乘法器**。
* 只有 stage 1 的第二運算元 `x[j+64]` 是 4-bit（原始輸入），所以 stage 1 的 `modq_mul` 只有 16 種可能輸入。

### 3.1 例子 A：n = 8 的玩具版（同一演算法）

```
### toy example, n = 8, Q = 12289, input x = [1, 2, 3, 4, 5, 6, 7, 8]
GMb (toy, index 1..7) = [4401, 1081, 1229, 2530, 6014, 7947, 5329]
  stage m=1  GMb[1]= 4401 : x[0]=    1, x[4]=    5 -> v= 7395 -> x[0]=(u+v)%Q= 7396, x[4]=(u-v)%Q= 4895
  stage m=1  GMb[1]= 4401 : x[1]=    2, x[5]=    6 -> v= 8874 -> x[1]=(u+v)%Q= 8876, x[5]=(u-v)%Q= 3417
  stage m=1  GMb[1]= 4401 : x[2]=    3, x[6]=    7 -> v=10353 -> x[2]=(u+v)%Q=10356, x[6]=(u-v)%Q= 1939
  stage m=1  GMb[1]= 4401 : x[3]=    4, x[7]=    8 -> v=11832 -> x[3]=(u+v)%Q=11836, x[7]=(u-v)%Q=  461
  stage m=2  GMb[2]= 1081 : x[0]= 7396, x[2]=10356 -> v=11604 -> x[0]=(u+v)%Q= 6711, x[2]=(u-v)%Q= 8081
  stage m=2  GMb[2]= 1081 : x[1]= 8876, x[3]=11836 -> v=  418 -> x[1]=(u+v)%Q= 9294, x[3]=(u-v)%Q= 8458
  stage m=2  GMb[3]= 1229 : x[4]= 4895, x[6]= 1939 -> v=11715 -> x[4]=(u+v)%Q= 4321, x[6]=(u-v)%Q= 5469
  stage m=2  GMb[3]= 1229 : x[5]= 3417, x[7]=  461 -> v=  529 -> x[5]=(u+v)%Q= 3946, x[7]=(u-v)%Q= 2888
  stage m=4  GMb[4]= 2530 : x[0]= 6711, x[1]= 9294 -> v= 5982 -> x[0]=(u+v)%Q=  404, x[1]=(u-v)%Q=  729
  stage m=4  GMb[5]= 6014 : x[2]= 8081, x[3]= 8458 -> v= 1884 -> x[2]=(u+v)%Q= 9965, x[3]=(u-v)%Q= 6197
  stage m=4  GMb[6]= 7947 : x[4]= 4321, x[5]= 3946 -> v= 2036 -> x[4]=(u+v)%Q= 6357, x[5]=(u-v)%Q= 2285
  stage m=4  GMb[7]= 5329 : x[6]= 5469, x[7]= 2888 -> v= 8406 -> x[6]=(u+v)%Q= 1586, x[7]=(u-v)%Q= 9352
output (x[0..7] after the last stage) = [404, 729, 9965, 6197, 6357, 2285, 1586, 9352]
independent check  X[k] = sum x[n] * psi^((2*brv(k)+1)*n) : [404, 729, 9965, 6197, 6357, 2285, 1586, 9352] -> OK

### Montgomery product example (spec modq_mul), a=5, b=GMb[1] of the toy table = 4401
  x = a*b = 22005 ; y = (x*Q0I) mod 2^16 = 39435 ; z = (x + y*Q)/2^16 = 7395 ; z>=Q ? -> result 7395
  check: a*b*R^-1 mod Q = 7395

### real packing, n = 128: coefficient i of the polynomial = 4 bit value x[i]
  x[i] = i mod 16 -> in_data per cycle: ['76543210', 'fedcba98', '76543210', 'fedcba98'] ...
  (cycle 0: x0 in bits [3:0], x7 in bits [31:28])
  out_data (128 cycles, 16 bit, value < 12289) first 8 : [927, 11340, 3224, 8739, 10076, 8034, 7677, 7729]
```

可以看到：每個 stage 把 `x[j]`、`x[j+ht]` 配對，做 `v = x[j+ht]·s`，再寫回 `u+v`、`u−v`；
最後的結果與「直接把多項式代入 ψ^(2·brv(k)+1)」的獨立公式完全一致 →
輸出等於多項式在 128 個根上的取值（bit-reversed 順序）。

### 3.2 例子 B：真實規格（n = 128）

stage 1 (m=1, ht=64)：`x[0]=3, x[64]=5` → `v = modq_mul(5, GMb[1])`，`x[0] = (3+v) mod Q`，`x[64] = (3−v) mod Q`。

## 4. 輸出格式與握手規則

* `out_valid` 在 128 個 clk3 cycle 為高（**不需要連續**），`out_data[15:0]` = `x[0], x[1], …, x[127]`（演算法結束後的陣列順序）。
* `out_valid` 為低時 `out_data` 必須為 0；`in_valid` 為高時 `out_valid`、`out_data` 必須為 0。
* 下一筆輸入在第 128 筆輸出收到後 **1~3 個 clk1 cycle** 就會進來 → 內部狀態必須在輸出完成時已經回到 idle。
* Latency = `in_valid` 下降緣 → 最後一筆 `out_valid` 下降緣（含 128 個輸出 cycle），要 < 5000 個 clk3 cycle。
* 效能分數 = Latency × Area（Area ≤ 2,000,000；Latency 以 clk3 = 20.7 ns 計）。

## 5. CDC（Clock Domain Crossing）部分

* clk1 → clk2：**Handshake_syn**（4-phase req/ack，兩個 NDFF_syn，每筆 32-bit 資料要走完整個 req↑ ack↑ req↓ ack↓）。
* clk2 → clk3：**FIFO_syn**（gray-code pointer、NDFF_BUS_syn、`DUAL_64X16X1BM1` SRAM，SRAM 輸出後要再多一級 DFF）。
* 要通過 Jasper CDC（`05_JG`）：不能有 violation，所以 Handshake/FIFO 的結構、命名（`sreq/dreq/dack/sack/din`、`wptr/rptr/wfull/rempty/winc/rinc/wdata/rdata`）都要維持。
* 因為 clk3 週期在 RTL 階段會變（3.1~20.7 ns），CLK_3 必須用 `rempty` 控制，out_valid 可以不連續。

## 6. 完整流程（時間軸）

```
t = 0                    in_valid 拉高（16 cycle × 14.1ns = 226 ns）
  └─ 每個 word 進 CLK_1 buffer，Handshake 一次傳 1 個 32-bit word（一次約 12~14 個 clk2 cycle ≈ 131 ns）
in_valid 下降（latency 起點）   此時只送完約 1.7 個 word；其餘 ~14 個 word 還在 CLK_1 buffer 裡
  └─ 16 個 word 全部過 Handshake 大約再花 ≈ 1.8 µs   ← 這段最長、不可避免（每筆都要 4-phase）
最後一個 word 到 clk2     CLK_2 的 NTT pipeline 只剩下「最後一個 word 的 8 個 sample + pipeline 深度」
  └─ 第一筆結果寫進 FIFO（再經 FIFO 同步約 2~3 個 clk3 cycle）
out_valid 連續 128 個 clk3 cycle（128 × 20.7 = 2650 ns）
最後一筆輸出的 out_valid 下降 = latency 終點
```

latency 的組成（V4 實測，clk3 = 20.7 ns）：Handshake 尾巴 ≈ 1.84 µs + NTT pipeline ≈ 0.19 µs + FIFO ≈ 0.05 µs + 輸出 128 cycle ≈ 2.65 µs ≈ 4.7 µs。
**輸出 128 個 clk3 cycle 與 16 次 Handshake 是下限，能壓的是 NTT 尾巴（pipeline）、FIFO 同步、Handshake 的 local logic。**

## 7. 本 repo 對 spec 缺資料的假設（重要）

TA 的 tar（`~iclabTA01/Lab07_2026F.tar`）沒有在此環境，以下是自己補的：

| 項目 | 本 repo 的處理 |
|---|---|
| `GMb.txt` | 用 `GMb[k] = ψ^brv7(k)·R mod Q`（ψ = 11^48 為 256 次單位根）自行產生 → `00_TESTBED/GMb.txt`。拿到真正的檔案後 `python3 tools/gen_pattern.py --gmb <真檔>` 重生 pattern，`python3 tools/gen_rom.py <真檔> designs/vN/DESIGN_MODULE.v` 重寫 ROM |
| `NTT_TOP / CLK_x 介面` | 依 Fig.1 與 IC LAB 慣例自訂（`common/NTT_TOP.v`），整合時請對照 TA 的 top 修改 port 名稱 |
| `DUAL_64X16X1BM1` | `04_MEM/` 放行為模型，port 採 Artisan 命名（A0..A5、DIB0..、WEAN/WEBN、CKA/CKB…） |
| `Handshake_syn / FIFO_syn / NDFF*` | 依 Fig.5/Fig.6 與 Jasper 投影片重寫；`WIDTH` 預設 32 / 16 |
| PATTERN / TESTBED | 自寫（`00_TESTBED/`），含 4 種 clk3 週期、隨機時脈相位、1~3 個 clk1 cycle 後接下一筆、latency 量測 |
