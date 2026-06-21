# Team Roles

## 推荐分工

## Product / Demo Owner

负责产品叙事、demo flow、Devpost、pitch 和安全边界。

Checklist:

- [ ] 维护 PRD 和 demo script。
- [ ] 确保每个页面有清楚用户目标。
- [ ] 准备 90 秒 pitch。
- [ ] 检查所有文案不踩医疗风险。
- [ ] 准备 Devpost 描述、截图和视频要点。

## Frontend Owner

负责页面结构、UI 状态、摄像头页面布局和 recap。

Checklist:

- [ ] 首页、safety、routine、camera、recap 页面完成。
- [ ] UI 在 demo 设备上不溢出。
- [ ] 摄像头页面 overlay 清晰。
- [ ] 有 loading 和 error 状态。
- [ ] 视觉上看起来像一个完整 app。

## Vision Owner

负责手部检测、landmarks、目标区域判断和反馈状态。

Checklist:

- [ ] 摄像头权限流程完成。
- [ ] 手部 landmarks 可用。
- [ ] 能区分 no hand / hand detected / target matched。
- [ ] 能输出稳定的 feedback state。
- [ ] 有 mock mode 或 static image fallback。

## AI / Backend Owner

负责 routine 数据、LLM prompt、安全 guardrail 和 fallback。

Checklist:

- [ ] routine JSON 完成。
- [ ] prompt 禁止自由编医疗建议。
- [ ] LLM 输出短、像教练、不像百科。
- [ ] red flag 输入触发停止建议。
- [ ] LLM 失败时使用固定文案。

## Integration Owner

如果队伍人多，安排一个人专门负责合并和 demo 稳定性。

Checklist:

- [ ] 每 2 小时拉一次 main demo branch。
- [ ] 维护 demo env。
- [ ] 跑 golden path。
- [ ] 记录 bug 和 owner。
- [ ] 准备最终提交包。

## 协作节奏

推荐每 2 小时做一次 10 分钟 sync：

1. 当前 demo path 是否还能跑。
2. 哪个 feature 阻塞。
3. 下一小时只做什么。
4. 有什么要砍掉。

## Scope Control Rules

- 如果一个功能不能让 demo 更清楚，先不做。
- 如果一个功能需要真实医学精度，先不做。
- 如果一个功能破坏 golden path，先关掉。
- 如果一个功能只有 pitch 里讲得到、demo 看不到，优先级降低。

