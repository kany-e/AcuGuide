# Feature 03: Camera Hand Tracking

## Goal

在浏览器或移动端摄像头中检测用户手部，输出稳定的 hand state 给 feedback engine。

## User Story

作为用户，我希望 App 能看到我的手是否在画面中，从而指导我调整位置。

## Scope

MVP 只需要判断：

- 是否检测到手。
- 手是否大致在画面中央。
- 是否能获取关键 landmarks。
- 用户手指是否接近目标区域。

不需要判断真实按压力度，不需要医学级穴位定位。

## Output States

| State | Meaning |
|---|---|
| no_camera | 摄像头不可用 |
| permission_denied | 用户拒绝权限 |
| no_hand | 没检测到手 |
| hand_detected | 检测到手 |
| target_near | 手指接近目标区域 |
| target_lost | 之前接近目标，后来丢失 |

## Acceptance Criteria

- [ ] 摄像头能打开。
- [ ] 拒绝权限时有可读提示。
- [ ] 手入镜后状态从 no_hand 变成 hand_detected。
- [ ] 能稳定输出 target_near。
- [ ] 状态变化不会疯狂闪烁。
- [ ] 有 mock mode 可以模拟所有状态。

## Fallback

如果手部模型加载失败：

- 显示静态手图。
- 用按钮模拟 no_hand、target_near、target_lost。
- 保留完整 demo flow。

## Engineering Tips

不要直接把每一帧 landmarks 驱动 UI。做一个简单 smoothing 或 debounce，例如连续 5 帧 target_near 才进入 good position。这样现场 demo 稳定很多。

