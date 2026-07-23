# Demo Flow

## Demo 目标

让评委快速看到：AcuGuide 不是一个回答健康问题的 chatbot，而是一个能引导用户完成手部穴位按压动作的 AI camera coach。

## 推荐 Demo 时长

总时长控制在 90 到 120 秒。

## Script

### 0. Opening

开场一句话：

> A lot of people can find acupressure advice online, but they still do not know whether they are pressing the right place. AcuGuide turns static wellness advice into a camera-guided self-care routine.

中文解释：

> 网上可以搜到很多穴位建议，但用户真正的问题是不知道自己有没有按对。AcuGuide 把静态建议变成一个能实时反馈的手部按压教练。

### 1. Symptom Selection

展示三个入口：

- Period discomfort
- Tension headache
- Neck and shoulder tension

选择 **Tension headache** 作为主 demo。

### 2. Safety Boundary

展示短安全提示：

> This is a wellness self-care routine, not medical diagnosis. Stop if you feel sharp pain, numbness, dizziness, or worsening symptoms.

不要停留太久，只需要让评委看到产品知道边界。

### 3. Routine Preview

展示 routine：

- 目标区域：手部指定区域
- 动作：轻柔按压
- 时长：30 秒
- 反馈：位置、稳定性、节奏

这里强调：

> The routine content is curated. The LLM does not invent medical advice.

### 4. Camera Feedback

打开摄像头。演示以下状态：

1. 手未入镜：提示把手放入画面。
2. 手入镜但手指偏离：提示稍微移动。
3. 手指接近目标区域：显示 good position，计时开始。
4. 手指移开：计时暂停或提示保持稳定。
5. 完成 30 秒：进入 recap。

### 5. Recap

展示完成总结：

- Position: good
- Hold time: 30s completed
- Stability: steady
- Reminder: stop if symptoms worsen

### 6. Closing Pitch

结尾一句话：

> We are not building an AI doctor. We are building the missing execution layer for safe, guided self-care routines.

## Demo 成功 Checklist

- [ ] 开场 15 秒内讲清楚 pain point。
- [ ] 30 秒内进入摄像头页面。
- [ ] 摄像头 feedback 至少展示 2 种状态。
- [ ] 计时器可以被稳定触发。
- [ ] Recap 页面可见。
- [ ] 安全边界被说出来。
- [ ] 没有把产品讲成诊断或治疗。

## Demo Fallback

如果摄像头失败：

- 切换到 prerecorded 或 simulated camera state。
- 用静态手部图片演示 overlay 和 feedback。
- 仍然讲完整产品逻辑：手部识别、目标区域、计时、recap。

如果 LLM 失败：

- 使用固定 routine 文案。
- 说 LLM 在产品中负责教练语言和 safety response，但 demo 不依赖实时生成。

如果场地网络差：

- 所有 routine 数据本地化。
- 所有核心 feedback 本地化。
- 只把 LLM 作为 optional polish。

