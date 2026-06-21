# Experiment: Minimum CV Demo Scope (v2)

> v2 改动：① 穴位 A 改为 **TE3 中渚**（避开孕期禁忌的 LI4）② 频率 proxy 明确为"轻点 tap"动作并加滞回 ③ 录制角度改为**正面**（与 demo 摄像头一致）④ 补上 `rhythm_unstable` 的素材与验收 ⑤ 新增穴位与手法说明。
> v2.1 改动：穴位 B 改为 **PC6 内关**（恶心/压力）。注意 PC6 在前臂、为 off-model 外推点，CV 较难——见 §4 的 ⚠️ 提醒与 HT7 fallback。

## 1. Experiment Goal
本实验只验证最小 demo 所需的两个能力：
1. 系统能判断用户是否按到目标手部穴位区域。
2. 系统能判断用户按压（轻点）节奏是否大致合适。

这不是医学实验，也不是穴位疗效验证。目标是证明 camera feedback 可以把静态穴位图变成可执行的互动练习。

## 2. Minimum Demo Scope
最小 demo 只做：
- 2 个手部穴位区域（**均为孕期安全穴位**）
- 位置判断：对 / 错
- 节奏判断：合适 / 太快 / 不稳定
- 摄像头实时反馈

暂时不做：指尖 vs 指腹、真实压力检测、医学级精确定位、疼痛反馈推断疾病、多症状问诊、训练完整 CV 模型。

## 3. Recommended Technical Approach
不要从原始视频训练完整 CV 模型。更稳的路线是：
```text
Camera video
-> MediaPipe hand landmarks (21 点)
-> feature extraction（相对区域 + 时间序列）
-> rule-based feedback engine
-> UI feedback
```
位置、时长、频率都先用**规则**判断。素材主要用于测试阈值、验证稳定性、准备 demo fallback，不是训练大模型。

## 4. The Two Acupoints We Are Massaging（穴位 + 手法）

两个穴位都**孕期安全**、都能被 MediaPipe 直接追踪（on-model，不在前臂外推区）。视觉上用 hand landmark 的相对区域定义，不追求医学级精确。

### 穴位 A — TE3 中渚 (Zhongzhu) · 紧张性头痛 routine
- **真实位置**：手背，无名指与小指掌指关节后方的凹陷（轻握拳更明显）。
- **视觉区域（CV 定义）**：无名指 MCP(13) 与 小指 MCP(17) 之间，略向手腕(0)方向。
  `target = 0.45·L13 + 0.40·L17 + 0.15·L0`，容差 ≈ `0.16 × handSize`。
- **真实手法**：对侧拇指**指腹**按入凹陷，力度中等（~5–6/10），稳按或小幅画圈，约 30 秒。
- **Demo 手法（本实验用）**：在该区域做**有节奏的轻点**（tap-in / tap-out），用来产生可计数的 press/release 周期。

### 穴位 B — PC6 内关 (Neiguan) · 恶心 / 压力 routine
- **真实位置**：掌侧前臂，腕横纹上约 2 寸（约 3 横指），两条肌腱之间。
- **视觉区域（CV 定义，⚠️ off-model 外推）**：PC6 在**前臂上**，超出 MediaPipe 追踪的手腕点(0)，关键点追不到。需从手腕沿前臂方向**外推**：
  `axis = normalize(L0 − L9)`（手腕指向前臂的方向）
  `target = L0 + 1.1 × handSize × axis`，掌心朝上，左右居中。
  容差放大到 ≈ `0.22 × handSize`，置信度比 A 低。
- **真实手法**：掌心朝上，对侧拇指**指腹**按两腱之间，力度中等（~5/10），稳按或小幅画圈，约 30 秒。
- **Demo 手法（本实验用）**：在该区域做有节奏的轻点。

> ⚠️ **CV 提醒**：PC6 是两个穴位里**较难**的一个，因为它不在手部关键点覆盖范围内，只能外推估计。录制和 demo 时务必：① 掌心朝上 ② **手腕保持在画面内**（外推要用到手腕点）③ 用更大的目标圈、更"软"的反馈。若现场不稳，可临时回退到 **HT7 神门**（在腕横纹上，on-model：`0.70·L0 + 0.30·L17`，容差 `0.14×handSize`）作为 fallback。

## 5. Feedback States
| State | Meaning | UI Copy |
|---|---|---|
| `no_hand` | 没检测到手 | Move your hand into frame. |
| `wrong_position` | 手指不在目标区域（持续离开） | Move closer to the highlighted area. |
| `correct_position` | 手指在目标区域 | Good position. |
| `rhythm_good` | 轻点节奏合适 | Keep this rhythm. |
| `rhythm_too_fast` | 轻点太快 | Slow down. |
| `rhythm_unstable` | 节奏忽快忽慢 | Tap and release more steadily. |

UI 文案统一用 **"tap"（轻点）** 而非 "press"，与频率 proxy 一致。

## 6. Frequency Definition（含滞回 hysteresis）
不检测真实压力，用视觉 proxy，且动作定义为**节奏性轻点**：
- 手指**进入**目标区域 = press
- 手指**离开**目标区域 = release
- 一个 press→release = 一个 cycle，在 10 秒滑动窗口内计数

**关键：加滞回，避免把"轻点的抬起"误判成 `wrong_position`：**
- 短暂离开（< 0.5s）= 正常 release，不报 `wrong_position`
- 持续离开（≥ 0.5s）才判为 `wrong_position`
- 用两个半径（进入用小半径、离开用稍大半径）防止边界抖动反复触发

建议阈值（可用素材调参）：
| 10 秒内 cycle 数 | 判断 | State |
|---:|---|---|
| 0–2 | 太慢 / 没形成规律 | `rhythm_unstable` 或提示加快 |
| 3–6 | 合适 | `rhythm_good` |
| 7+ | 太快 | `rhythm_too_fast` |

`rhythm_unstable` 单独判定：相邻 cycle 间隔的方差过大（忽快忽慢）即判为不稳定，**不依赖**总数。

## 7. Minimum Video Recording Table
每段 6–10 秒，30fps。**录制角度 = 正面、略高于手**（与 demo 用的笔记本/手机摄像头一致），不要用 45° 侧上方——否则调出来的阈值在正面 demo 时不通用。

| 组别 | 穴位 | 动作 | Label | 数量 |
|---|---|---|---|---:|
| 1 | A (TE3) | 按对 + 正常节奏 | `A_correct_good_rhythm` | 4 |
| 2 | A (TE3) | 按对 + 太快 | `A_correct_too_fast` | 3 |
| 3 | A (TE3) | 按对 + 节奏不稳 | `A_correct_unstable` | 2 |
| 4 | A (TE3) | 按错位置 | `A_wrong_position` | 4 |
| 5 | B (PC6) | 按对 + 正常节奏 | `B_correct_good_rhythm` | 4 |
| 6 | B (PC6) | 按对 + 太快 | `B_correct_too_fast` | 3 |
| 7 | B (PC6) | 按对 + 节奏不稳 | `B_correct_unstable` | 2 |
| 8 | B (PC6) | 按错位置 | `B_wrong_position` | 4 |
| 9 | A/B | 手不完整入镜 | `partial_hand` | 3 |
| 10 | A/B | 没有手，只有背景 | `no_hand` | 3 |

合计 ~32 段（原 v1 约 52 段；精简后仍覆盖全部验收项）。

## 8. Recording Guidelines
- **摄像头固定、正面略高**，与现场 demo 设备一致。
- 手和摄像头距离尽量一致。
- **录 PC6 时掌心朝上、手腕务必在画面内**（外推依赖手腕点）。
- 每段只展示一个 label，不混多个动作。
- 背景简单，避免复杂纹理。
- 左手右手各录一部分；至少 2–3 个不同人的手。
- 文件名含 label，如 `A_correct_good_rhythm_01.mp4`。
- **同时记录原始 landmark 流为 `.jsonl`**（便于 FrameState 级别回放与单测）。

## 9. Acceptance Criteria
- [ ] 稳定区分 `no_hand` 与 `hand_detected`。
- [ ] 穴位 A(TE3)：能区分正确区域与明显错误区域。
- [ ] 穴位 B(PC6)：能区分正确区域与明显错误区域（注意 off-model 外推，手腕需在画面内）。
- [ ] 正确位置样本 → `correct_position`。
- [ ] 明显偏离样本 → `wrong_position`（且轻点的抬起**不会**误判为偏离）。
- [ ] 正常节奏样本 → `rhythm_good`。
- [ ] 快速点按样本 → `rhythm_too_fast`。
- [ ] 忽快忽慢样本 → `rhythm_unstable`。
- [ ] 现场 demo 至少能稳定跑通一个穴位的完整流程。

## 10. Demo Success Statement
> AcuGuide can tell whether the user is pressing the right hand region and whether their tapping rhythm is appropriate.

中文：
> AcuGuide 能判断用户是否按到目标手部区域（TE3 / PC6），并判断轻点节奏是否合适。
