# Feature 01: Symptom Selection

## Goal

让用户从三个常见不适中选择一个入口，并进入对应的手部按压 routine。

## User Story

作为一个有轻度常见不适的用户，我想快速选择当前场景，从而获得一套简单、安全、可跟随的手部按压指导。

## Scope

MVP 包含三个入口：

| Entry | Label | Demo Priority |
|---|---|---|
| tension_headache | Tension Headache | 主 demo |
| period_discomfort | Period Discomfort | 强故事入口 |
| neck_shoulder_tension | Neck & Shoulder Tension | 泛人群入口 |

## UI Requirements

- 每个入口是一个清晰按钮或卡片。
- 每个入口有一句短说明。
- 页面不出现医疗诊断语言。
- 用户点击后进入 safety screen。

## Acceptance Criteria

- [ ] 三个入口都可见。
- [ ] 三个入口都可点击。
- [ ] 点击后进入正确 routine。
- [ ] 入口文案不声称治疗。
- [ ] 主 demo 入口默认在视觉上最突出。

## Fallback

如果 routine 数据加载失败，入口仍然显示，但点击后进入一个固定 demo routine。

## Engineering Tips

入口不要和医学逻辑耦合。推荐用简单配置驱动：

```json
{
  "id": "tension_headache",
  "label": "Tension Headache",
  "routineId": "hand_headache_basic"
}
```

