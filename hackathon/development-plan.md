# Development Plan

## 开发策略

采用 vertical slice 策略：先把一个症状的一条完整流程做通，再复制到其他入口。不要先搭完整架构、不要先做所有症状、不要先追求医学精度。

推荐顺序：

1. 静态 UI 跑通。
2. Routine 数据跑通。
3. 摄像头打开。
4. 手部检测跑通。
5. Overlay 和 feedback 跑通。
6. Recap 跑通。
7. LLM 教练文案接入。
8. Fallback 和 demo polish。

## Phase 1: Static Golden Path

目标是在没有摄像头、没有 LLM 的情况下，用户也能从首页走到 recap。

Checklist:

- [ ] 首页显示三个入口。
- [ ] 选择紧张性头痛后进入 safety 页面。
- [ ] safety 页面进入 routine preview。
- [ ] routine preview 进入 camera 页面。
- [ ] camera 页面可用按钮模拟 feedback 状态。
- [ ] 完成后进入 recap 页面。

成功标准：

> 即使没有任何 AI，产品故事也能被完整演示。

## Phase 2: Hand Tracking

目标是让摄像头成为真实互动，而不是背景装饰。

Checklist:

- [ ] 摄像头权限请求正常。
- [ ] 能检测手是否入镜。
- [ ] 能拿到手部 landmarks。
- [ ] 能在画面上画出目标区域。
- [ ] 能判断手指是否接近目标区域。

成功标准：

> 用户把手放到画面里，系统能稳定从 “not detected” 变成 “hand detected”。

## Phase 3: Feedback Engine

目标是让 demo 看起来像 coach。

Checklist:

- [ ] 未入镜时提示放入画面。
- [ ] 手入镜但目标偏离时提示移动。
- [ ] 接近目标时提示 good position。
- [ ] 稳定按住时计时开始。
- [ ] 移开时计时暂停或提醒。
- [ ] 完成 30 秒后进入 recap。

成功标准：

> 评委能直观看到 camera feedback 对用户动作产生了影响。

## Phase 4: AI Coach

目标是增加 AI 感，但不让 AI 成为风险源。

Checklist:

- [ ] routine 内容来自固定 JSON。
- [ ] LLM prompt 明确禁止诊断和自由编穴位。
- [ ] LLM 输出 step-by-step coaching language。
- [ ] 如果用户输入 red flag，系统建议停止并寻求专业帮助。
- [ ] LLM 失败时 fallback 到固定文案。

成功标准：

> AI 让产品更自然，但核心 demo 不依赖 AI 是否在线。

## Phase 5: Polish And Demo Readiness

目标是提高现场稳定性。

Checklist:

- [ ] UI 不遮挡摄像头关键区域。
- [ ] 主要按钮足够大。
- [ ] 文案短，不像医学文章。
- [ ] 有 loading、error、permission denied 状态。
- [ ] Golden path 录屏备份。
- [ ] 一台机器现场完整跑 3 次。

成功标准：

> 任何一个队友拿起电脑都能演示，不需要解释技术细节才能让人看懂。

## 经典开发技巧

### 1. Build The Walking Skeleton

先做最薄的一条完整路径。一个完整但简单的 demo，比三个半成品 feature 更有价值。

### 2. Fake The Hard Part Until It Matters

如果摄像头算法还不稳，先用按钮或固定图片模拟状态。等 UI 和 story 成立后，再接真实模型。

### 3. Separate Data From Logic

穴位 routine 放在 JSON 里，不写死在组件里。这样可以快速修改内容，也能证明 LLM 没有乱编。

### 4. Design For Failure

每个外部依赖都要有 fallback：摄像头、网络、LLM、模型加载、权限。

### 5. Optimize For Judge Perception

评委看到的是 flow、反馈、边界和价值，不会检查你是否医学级精确。先让 feedback 稳定可见。

