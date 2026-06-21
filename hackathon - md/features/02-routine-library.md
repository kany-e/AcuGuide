# Feature 02: Routine Library

## Goal

用固定数据定义每个入口的手部按压 routine，避免 LLM 自由生成医疗内容。

## User Story

作为用户，我希望得到清楚、短小、可执行的 routine，而不是一大段健康百科。

## Data Model

推荐字段：

```json
{
  "id": "hand_headache_basic",
  "symptom": "tension_headache",
  "title": "30-second hand pressure routine",
  "targetRegion": "thumb_index_web_area",
  "durationSeconds": 30,
  "steps": [
    "Place your hand in the camera frame.",
    "Gently press the highlighted area.",
    "Hold steady and breathe slowly."
  ],
  "safetyNotes": [
    "Stop if you feel sharp pain or numbness.",
    "This is not medical diagnosis."
  ],
  "redFlags": [
    "sudden severe headache",
    "vision change",
    "numbness"
  ]
}
```

## MVP Routine Set

| Routine | Status |
|---|---|
| hand_headache_basic | P0，完整 demo |
| hand_period_comfort | P0，固定指导 |
| hand_neck_shoulder_basic | P0，固定指导 |

## Acceptance Criteria

- [ ] 每个症状入口有一个 routine。
- [ ] 每个 routine 有 title、steps、duration、safetyNotes。
- [ ] routine 内容可以不依赖 LLM 显示。
- [ ] LLM 只能基于 routine 改写，不能添加新穴位。
- [ ] 文案简短，适合手机屏幕。

## Fallback

如果 LLM 不可用，直接显示 routine 原始 steps。不要让页面空白。

## Engineering Tips

把 routine library 当成 source of truth。所有 UI、LLM prompt、recap 都从这个数据结构读，不要复制粘贴三份文案。

