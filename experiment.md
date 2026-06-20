# Experiment: Minimum CV Demo Scope

## 1. Experiment Goal

本实验只验证最小 demo 所需的两个能力：

1. 系统能判断用户是否按到目标手部穴位区域。
2. 系统能判断用户按压频率是否大致合适。

这不是医学实验，也不是穴位疗效验证。目标是证明 camera feedback 可以把静态穴位图变成可执行的互动练习。

## 2. Minimum Demo Scope

最小 demo 只做：

- 2 个手部穴位区域
- 位置判断：对 / 错
- 频率判断：合适 / 太快 / 不稳定
- 摄像头实时反馈

暂时不做：

- 指尖 vs 指腹
- 真实压力检测
- 医学级穴位精确定位
- 疼痛反馈推断疾病
- 多症状复杂问诊
- 训练完整 CV 模型

## 3. Recommended Technical Approach

不要从原始视频训练完整 CV 模型。更稳的路线是：

```text
Camera video
-> MediaPipe / Vision hand landmarks
-> feature extraction
-> rule-based feedback engine
-> UI feedback
```

位置、时长、频率都先用规则判断。素材主要用于测试阈值、验证稳定性和准备 demo fallback，而不是训练大模型。

## 4. Two Demo Acupoint Regions

两个穴位不追求医学级精确，先用 hand landmarks 的相对区域定义。

| 穴位 | Demo 用途 | 视觉定义 | 判断方式 |
|---|---|---|---|
| 穴位 A | 头痛 routine | 拇指和食指之间区域 | 手指接近目标 zone 即视为位置正确 |
| 穴位 B | 肩颈/压力 routine | 手腕附近区域 | 手指接近手腕侧目标 zone 即视为位置正确 |

## 5. Feedback States

| State | Meaning | UI Copy |
|---|---|---|
| `no_hand` | 没检测到手 | Move your hand into frame. |
| `wrong_position` | 手指不在目标区域 | Move closer to the highlighted area. |
| `correct_position` | 手指在目标区域 | Good position. |
| `rhythm_good` | 频率合适 | Keep this rhythm. |
| `rhythm_too_fast` | 频率太快 | Slow down. |
| `rhythm_unstable` | 频率不稳定 | Press and release more steadily. |

## 6. Frequency Definition

频率不检测真实压力，用视觉 proxy：

- 手指靠近目标区域 = press
- 手指离开目标区域 = release
- 在 10 秒窗口内统计 press/release cycle 数量

建议阈值：

| 10 秒内 cycle 数 | 判断 |
|---:|---|
| 0-2 | 太慢或没有形成规律 |
| 3-6 | 合适 |
| 7+ | 太快 |

这些阈值可以根据录制素材调参。

## 7. Minimum Video Recording Table

每段视频建议 6-10 秒，30fps。优先用 45 度侧上方角度录制，这样更容易看到手指接近和离开目标区域。

| 组别 | 穴位 | 动作 | Label | 数量 |
|---|---|---|---|---:|
| 1 | A | 按对 + 正常频率 | `A_correct_good_rhythm` | 8 |
| 2 | A | 按对 + 太快 | `A_correct_too_fast` | 5 |
| 3 | A | 按错位置 | `A_wrong_position` | 8 |
| 4 | B | 按对 + 正常频率 | `B_correct_good_rhythm` | 8 |
| 5 | B | 按对 + 太快 | `B_correct_too_fast` | 5 |
| 6 | B | 按错位置 | `B_wrong_position` | 8 |
| 7 | A/B | 手不完整入镜 | `partial_hand` | 5 |
| 8 | A/B | 没有手，只有背景 | `no_hand` | 5 |

## 8. Recording Guidelines

录素材时保持以下一致性：

- 手机固定，不要频繁移动。
- 手和摄像头距离尽量一致。
- 每段视频只展示一个 label，不要混多个动作。
- 背景尽量简单，避免复杂纹理。
- 录制左手和右手至少各一部分样本。
- 至少 2-3 个不同人的手参与录制。
- 每个视频文件名包含 label，例如 `A_correct_good_rhythm_01.mp4`。

## 9. Acceptance Criteria

实验成功的标准：

- [ ] 系统能稳定区分 `no_hand` 和 `hand_detected`。
- [ ] 对穴位 A，系统能区分正确区域和明显错误区域。
- [ ] 对穴位 B，系统能区分正确区域和明显错误区域。
- [ ] 对正确位置样本，系统能给出 `correct_position`。
- [ ] 对明显偏离样本，系统能给出 `wrong_position`。
- [ ] 对正常频率样本，系统能给出 `rhythm_good`。
- [ ] 对快速点按样本，系统能给出 `rhythm_too_fast`。
- [ ] 现场 demo 至少能稳定跑通一个穴位的完整流程。

## 10. Demo Success Statement

最小 demo 只需要证明：

> AcuGuide can tell whether the user is pressing the right hand region and whether their pressing rhythm is appropriate.

中文版本：

> AcuGuide 能判断用户是否按到目标手部区域，并判断按压节奏是否合适。

