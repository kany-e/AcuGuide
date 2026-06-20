# Demo Script

## Demo Goal

在 90-120 秒内让评委看到：AcuGuide 把静态穴位建议变成一个可执行、可反馈、可安全停止的手部按压 routine。

## Demo Path

主路径：

Tension Headache -> Safety -> Routine Preview -> Camera Feedback -> Completion Recap

## 90 秒 Script

### 0-15 秒: Problem

> A lot of people can find acupressure advice online, but the hard part is not reading the advice. The hard part is knowing whether you are pressing the right place and doing it safely.

中文备用：

> 网上有很多穴位建议，但真正的问题不是找不到信息，而是不知道自己有没有按对、按多久、什么时候该停。

### 15-30 秒: Product

> AcuGuide is an AI camera coach for guided hand acupressure routines. It is not an AI doctor. It helps users execute safe self-care routines with real-time visual feedback.

### 30-45 秒: Symptom Selection

展示首页三个入口：

- Period discomfort
- Tension headache
- Neck and shoulder tension

点击 Tension Headache。

旁白：

> For the demo, we will choose tension headache because it is common, quick to understand, and easy to demonstrate with the hand camera flow.

### 45-55 秒: Safety

展示 safety screen。

旁白：

> Before any routine, we set a clear boundary: this is wellness guidance, not diagnosis or treatment. If users report red flags, we stop the routine.

### 55-80 秒: Camera Feedback

进入摄像头页面，按顺序展示：

1. no hand: move your hand into frame
2. off target: move slightly toward the highlighted area
3. good position: keep holding
4. progress ring moves
5. routine complete

旁白：

> The key difference is that AcuGuide can see execution. It checks whether the hand is visible, whether the finger is near the target region, and whether the hold is steady long enough.

### 80-100 秒: Recap

展示 recap。

旁白：

> At the end, the app summarizes execution quality, not medical outcome. If the user reports worsening or unusual discomfort, we tell them to stop rather than keep pressing.

### Closing

> We are not building another health chatbot. We are building the missing execution layer for safe, guided self-care routines.

## 30 秒 Backup Script

> AcuGuide is an AI camera coach for hand acupressure. People can read pressure point advice online, but they cannot tell whether they are doing it correctly. Our app gives a curated routine, uses camera feedback to guide hand position and hold duration, and keeps clear safety boundaries so it stays as wellness self-care, not medical diagnosis.

## Demo Checklist

- [ ] 开场没有超过 15 秒。
- [ ] 明确说出 not an AI doctor。
- [ ] 展示三个入口。
- [ ] 主 demo 能在 60 秒内进入摄像头。
- [ ] 至少展示两个 feedback 状态。
- [ ] Recap 不声称治疗成功。
- [ ] 结尾回到 unique value。

## Fallback Script

如果摄像头失败：

> The live camera is failing in this environment, so we are switching to simulated camera states. The product logic is the same: hand visible, target alignment, hold stability, completion recap.

如果 LLM 失败：

> The core routine is deterministic and curated. The LLM layer improves coaching language and safety responses, but the demo does not rely on it to generate medical advice.

