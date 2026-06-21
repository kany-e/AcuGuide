# Feature 06: Completion Recap

## Goal

在 routine 结束后总结用户完成情况，并保持安全、非诊断的下一步建议。

## User Story

作为用户，我希望知道自己是否完成了 routine，以及是否应该继续、休息或停止。

## Recap Content

推荐展示：

- Routine completed
- Hold duration
- Position stability
- Rhythm or steadiness
- Safety reminder
- Self-report question

## Self-Report Options

| Option | Response |
|---|---|
| Better | 建议休息并观察 |
| No change | 可以稍后再试，但不强迫继续 |
| Worse or unusual | 建议停止，严重或持续时寻求专业帮助 |

## Acceptance Criteria

- [ ] 完成 30 秒后自动进入 recap。
- [ ] recap 不声称症状被治疗。
- [ ] 有 self-report 三选项。
- [ ] 选择 worse 时不会推荐继续按压。
- [ ] recap 可以返回首页。

## Fallback

如果 tracking 数据不可用，recap 显示 “Guided routine completed” 和 safety reminder，不显示质量评分。

## Engineering Tips

不要给过度精确的分数，比如 97%。更可信的表达是 qualitative feedback：Good, Needs steadier hold, Try repositioning next time。

