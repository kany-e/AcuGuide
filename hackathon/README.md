# AcuGuide Hand Coach Hackathon Docs

## 项目一句话

AcuGuide Hand Coach 是一个手部穴位 AI 自我护理教练：用户选择常见不适后，App 用摄像头引导用户找到手部按压区域，并实时反馈位置、稳定性、节奏和时长，同时保持清晰的非诊断安全边界。

## Demo 成功定义

这次 hackathon 的目标不是做完整医疗产品，而是做出一个 2 分钟内能讲清楚、能演示、能让评委看到差异化的 MVP。

成功 demo 应该满足：

- 评委 30 秒内明白产品不是健康 chatbot，而是视觉引导的手部按压 coach。
- 三个入口存在：经期不适、紧张性头痛、肩颈紧张。
- 至少一个入口完成完整 camera feedback flow。
- 摄像头页面能识别手是否入镜，并给出实时反馈。
- 用户可以完成一次 30 秒 routine。
- 结束页能展示完成度 recap。
- 全流程有 safety boundary，不做诊断、不声称治疗。

## 推荐 Demo 主线

主 demo 用 **紧张性头痛**。原因是手部展示最清楚、安全风险较低、评委容易理解。

备用故事用 **经期不适**。原因是用户痛点更强，但措辞要更保守，避免说成治疗。

## 文档结构

| 文件 | 用途 |
|---|---|
| [requirements.md](./requirements.md) | 总需求和验收标准 |
| [demo-flow.md](./demo-flow.md) | 评委演示流程 |
| [development-plan.md](./development-plan.md) | 开发拆分、顺序、fallback |
| [market-value-prop.md](./market-value-prop.md) | 市场价值、独特价值、pitch |
| [risks-and-safety.md](./risks-and-safety.md) | 医疗风险、安全边界、措辞规范 |
| [team-roles.md](./team-roles.md) | 队伍分工和协作方式 |
| [features/01-symptom-selection.md](./features/01-symptom-selection.md) | 症状入口 |
| [features/02-routine-library.md](./features/02-routine-library.md) | 固定 routine 数据 |
| [features/03-camera-hand-tracking.md](./features/03-camera-hand-tracking.md) | 手部识别 |
| [features/04-visual-feedback.md](./features/04-visual-feedback.md) | 实时反馈 |
| [features/05-ai-coach-safety.md](./features/05-ai-coach-safety.md) | AI 教练和安全 guardrail |
| [features/06-completion-recap.md](./features/06-completion-recap.md) | 结束总结 |

## 工程原则

1. 先做一条完整 vertical slice，再扩展三个入口。
2. 先保证 demo path 稳定，再追求真实算法精度。
3. 医疗相关内容用固定数据，LLM 只负责改写和安全对话。
4. 摄像头 feedback 允许近似，但必须稳定、可解释、不卡顿。
5. 每个 feature 都要有 fallback，避免现场网络、摄像头、模型失效导致 demo 崩掉。

