# Feature 05: AI Coach And Safety

## Goal

让 AI 提供自然的教练式语言，同时防止医疗诊断、治疗承诺和自由编造穴位建议。

## User Story

作为用户，我希望指导语言简短、温和、像有人在带我做，而不是一段百科或医疗建议。

## AI Responsibilities

AI 可以做：

- 改写固定 routine。
- 根据用户选择生成温和引导语。
- 解释为什么要慢慢按、保持稳定。
- 识别 red flag 并建议停止。
- 生成完成后的鼓励式 recap。

AI 不可以做：

- 诊断疾病。
- 判断体质。
- 自由推荐新穴位。
- 声称治疗效果。
- 根据疼痛点推断疾病。

## Prompt Requirements

Prompt 必须包含：

- 产品是 wellness self-care coach。
- 不做 diagnosis、treatment、prescription。
- 只能使用 provided routine。
- 如果出现 red flag，停止 routine。
- 输出短句，适合 mobile UI。

## Acceptance Criteria

- [ ] LLM 输出不包含诊断语言。
- [ ] LLM 不添加 routine library 之外的穴位。
- [ ] red flag 输入触发停止建议。
- [ ] LLM 失败时 fallback 到固定文案。
- [ ] AI 文案比原始 steps 更自然，但不更冒险。

## Fallback

如果没有时间接 LLM，保留固定 coach 文案。Pitch 中可以说 AI layer 用于 personalization and safety response，当前 demo 使用 curated deterministic script。

## Engineering Tips

把 AI 放在 “polish layer”，不要放在 critical path。hackathon 现场最怕网络、key、rate limit 出问题。核心 demo 应该没有 LLM 也能跑。

