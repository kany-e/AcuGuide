# Risks And Safety

## 核心原则

AcuGuide 必须被定义为 wellness self-care coach，而不是医疗诊断或治疗工具。产品可以指导用户完成低风险的手部按压 routine，但不能告诉用户他们有什么病，也不能承诺症状会被治疗。

## 高风险表达

避免使用：

- 治疗经痛
- 诊断头痛原因
- 判断你是否有疾病
- 检测身体问题
- 按这里可以治好
- 根据疼痛判断内脏问题
- 中医辨证结果

推荐使用：

- wellness routine
- self-care guidance
- comfort support
- guided acupressure
- educational use
- not medical diagnosis
- stop if symptoms worsen

## Safety Screen 文案

英文：

> AcuGuide provides wellness self-care guidance only. It does not diagnose, treat, or replace medical care. Stop if you feel sharp pain, numbness, dizziness, unusual symptoms, or worsening discomfort. Seek medical advice for severe, sudden, persistent, or concerning symptoms.

中文：

> AcuGuide 仅提供 wellness 自我护理指导，不做诊断，也不替代医疗建议。如果出现刺痛、麻木、眩晕、异常症状或不适加重，请停止练习。严重、突然、持续或令人担心的症状应寻求专业帮助。

## Red Flags

如果用户输入或选择以下情况，系统应该停止 routine：

- 突然剧烈头痛
- 视力异常
- 手脚麻木或无力
- 胸痛、呼吸困难
- 发烧伴随严重疼痛
- 怀孕相关异常疼痛
- 异常出血
- 外伤后疼痛
- 按压后症状明显加重

## AI Guardrail

LLM 必须遵守：

1. 不诊断疾病。
2. 不生成新穴位。
3. 不声称治疗效果。
4. 不解释按压疼痛意味着某种疾病。
5. 遇到 red flag，建议停止并寻求专业帮助。
6. 回答保持简短、温和、可执行。

## Demo 风险

| 风险 | 处理 |
|---|---|
| 评委认为这是医疗诊断 | 开场明确 wellness self-care，不是 AI doctor |
| 穴位知识被质疑 | 说明 routine 是 curated content，AI 不自由编造 |
| 摄像头定位不准 | 说明是 approximate guidance，不是 clinical precision |
| 用户问是否有效 | 回答产品目标是 execution confidence，不承诺临床疗效 |
| 经期不适敏感 | 用 comfort support，不说 treatment |

## Safety Checklist

- [ ] 首页或 routine 前有非诊断提示。
- [ ] LLM prompt 禁止诊断和治疗承诺。
- [ ] 文案不出现高风险表达。
- [ ] 用户选择 worse/unusual discomfort 时停止继续指导。
- [ ] Pitch 中主动说明 safety boundary。

