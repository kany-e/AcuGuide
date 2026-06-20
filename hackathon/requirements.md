# Requirements

## 1. 产品目标

AcuGuide Hand Coach 的目标是把静态的手部穴位按压建议，变成一个可执行、可反馈、可安全停止的 AI guided routine。用户不是来获得诊断，而是来完成一次低风险的 wellness self-care 练习。

## 2. MVP 范围

MVP 只覆盖手部。用户选择一个常见不适，App 展示对应的手部按压 routine，并在摄像头页面提供实时反馈。系统可以提示手是否入镜、按压区域是否接近目标、是否保持稳定、是否完成足够时长。

MVP 包含三个入口：

| 入口 | MVP 处理方式 |
|---|---|
| 紧张性头痛 | 完整 demo routine，优先实现 camera feedback |
| 经期不适 | 有入口、有安全提示、有 routine，可复用简化 feedback |
| 肩颈紧张 | 有入口、有 routine，可复用简化 feedback |

## 3. 明确非目标

产品不做疾病诊断、不判断用户体质、不根据按压疼痛推断疾病、不声称治疗经痛或头痛、不测量真实按压力度、不做全身 AR 建模、不做复杂中医辨证。

## 4. Functional Requirements

| ID | Requirement | Priority |
|---|---|---|
| R1 | 用户可以选择三个常见不适入口 | P0 |
| R2 | 每个入口对应一个固定手部 routine | P0 |
| R3 | 每个 routine 有安全提示和停止条件 | P0 |
| R4 | 摄像头页面可以检测手是否入镜 | P0 |
| R5 | 摄像头页面可以显示目标按压区域 overlay | P0 |
| R6 | 用户按压目标区域时，计时器可以开始或继续 | P0 |
| R7 | 用户移开手或位置偏离时，系统给出反馈 | P0 |
| R8 | 完成 routine 后展示 recap | P0 |
| R9 | LLM 可以生成教练式文案，但不能自由编穴位 | P1 |
| R10 | 支持无摄像头或模型失败时的 demo fallback | P0 |

## 5. Non-Functional Requirements

| 维度 | 要求 |
|---|---|
| 性能 | 摄像头 feedback 延迟最好小于 300ms，最低要求是肉眼不卡顿 |
| 稳定性 | demo 主路径不能依赖临场调试；至少有一个可离线 fallback |
| 隐私 | 摄像头画面默认本地处理，不上传图片或视频 |
| 安全 | 全流程使用 wellness language，不使用诊断或治疗承诺 |
| 可维护性 | routine 数据、视觉逻辑、LLM prompt 分离 |
| 可演示性 | 任何页面失败时都有下一步，不出现空白页 |

## 6. Acceptance Checklist

- [ ] 三个入口可以点击进入。
- [ ] 每个入口都有清晰 routine 标题、步骤和安全提示。
- [ ] 主 demo 入口可以打开摄像头。
- [ ] 系统能检测手是否入镜。
- [ ] 目标区域 overlay 可见且不遮挡关键 UI。
- [ ] 系统能给出至少三种反馈：未入镜、偏离目标、保持稳定。
- [ ] 计时器可以完成 30 秒 routine。
- [ ] 完成页展示 recap。
- [ ] 页面文案不出现“治疗”“诊断”“检测疾病”等高风险表达。
- [ ] 断网或 LLM 失败时，demo 仍可用固定文案完成。

## 7. Demo Release Gate

只有当以下条件满足时，才允许把 demo 交给 pitch：

- [ ] Golden path 连续跑 3 次不崩。
- [ ] 在实际场地光线下测试过摄像头。
- [ ] 至少一个队友不看代码也能完整演示。
- [ ] 备用流程准备好：摄像头失败、网络失败、LLM 失败。
- [ ] Pitch 话术明确说明非诊断边界。

