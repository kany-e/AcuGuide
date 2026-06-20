# Feature 04: Visual Feedback

## Goal

把 hand tracking 的状态转成用户能理解的实时指导。

## User Story

作为用户，我希望 App 不只是显示摄像头，而是真的告诉我现在该怎么调整。

## Feedback Types

| Feedback | Trigger |
|---|---|
| Move your hand into frame | no_hand |
| Hold your hand steady | hand_detected but unstable |
| Move slightly toward the highlighted area | hand detected but not target_near |
| Good position, keep holding | target_near |
| Timer paused, find the target again | target_lost |
| Routine complete | duration completed |

## UI Components

- Camera preview
- Hand target overlay
- Feedback text
- Progress ring or timer
- Safety reminder
- Continue / finish button fallback

## Acceptance Criteria

- [ ] 用户能看到当前 feedback。
- [ ] feedback 文案短，不超过一行或两行。
- [ ] good position 时 timer 启动。
- [ ] lost target 时 timer 暂停或减速。
- [ ] 完成后自动进入 recap。
- [ ] overlay 不挡住关键手部位置。

## Fallback

如果实时 tracking 不稳定，允许用户手动点击 “Looks aligned” 进入计时，但 UI 上保留 camera coach 体验。

## Engineering Tips

视觉 feedback 要少而明确。不要同时显示很多建议。每一刻只回答一个问题：用户下一步该做什么。

