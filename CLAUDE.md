# CLAUDE.md — AcuGuide Hand Coach (AcuGuide/ repo)

## 项目状态（截至 June 20, 2026 深夜）

React + Vite + TypeScript + TailwindCSS 应用，已可在 iPhone 上通过 HTTPS 运行。

### 已完成 ✅

| 模块 | 文件 | 状态 |
|------|------|------|
| 脚手架 | package.json / vite.config.ts / tsconfig*.json | 完成 |
| 类型定义 | src/types/index.ts | 完成 |
| 穴位数据 | src/data/acupoints.json | 完成（从 PointLandmark.json 复制） |
| Landmark 常量 | src/utils/landmarks.ts | 完成 |
| 几何工具 | src/utils/geometry.ts | 完成 |
| Canvas 绘制 | src/utils/drawOverlay.ts | 完成 |
| MediaPipe hook | src/hooks/useMediaPipe.ts | 完成，从 CDN 加载 WASM |
| 手部分类 | src/hooks/useHandClassifier.ts | 完成，dorsal/palmar 启发式 |
| 按压检测 | src/hooks/usePressDetection.ts | 完成，handSize 相对 tolerance |
| 状态机 | src/hooks/useCoachingState.ts | 完成，时间戳防抖（非 setTimeout） |
| Router | src/App.tsx | 完成 |
| HomePage | src/pages/HomePage.tsx | 完成，3 张症状卡片 |
| SafetyPage | src/pages/SafetyPage.tsx | 完成，红旗列表 + 强制确认 |
| RoutinePage | src/pages/RoutinePage.tsx | 完成，穴位详情 + Start 按钮 |
| CameraPage | src/pages/CameraPage.tsx | 完成，双摄切换 + overlay + timer ring |
| RecapPage | src/pages/RecapPage.tsx | 完成，FeelingSelector + 安全提示 |

### 已验证在 iPhone Safari 上工作 ✅

- HTTPS via mkcert（证书在 `~/.vite-plugin-mkcert/`，已在 iPhone 信任）
- 摄像头权限正常弹出
- MediaPipe 手部检测工作（灰/橙/蓝/绿圆圈状态切换）
- 前后摄像头切换（右上角按钮）
- 7 状态机转换正常

### 关键技术决策（新会话必须保留）

1. **不用 React StrictMode** — `src/main.tsx` 里已移除，因为 StrictMode 双调用 effect 会导致 iOS `getUserMedia` AbortError
2. **`video.play()` 不 await** — iOS Safari 上 await play() 会抛 AbortError，改为 `.catch(() => {})`
3. **时间戳防抖，非 setTimeout** — 状态机每帧运行，setTimeout 防抖会被每帧重置永远不触发，改用 `pendingRef.current.since` 时间戳比较
4. **摄像头初始化与 MediaPipe 分离** — 两个独立 try-catch，分别显示不同错误页
5. **`facingMode: { ideal: 'environment' }`** — 软约束，不满足时 fallback 到前置，不抛错
6. **`effect` 依赖数组为空 `[]`** — CameraPage 的摄像头 useEffect 只跑一次，MediaPipe 用 `mediaPipeStarted` ref 防重复初始化

### 还剩什么

**必做（demo 相关）：**
- [x] UI 整体视觉重设计 — 深色 Ladder 风格，lime 主色，hero card + routine stack，feedback card + progress ring
- [ ] WRONG_FACE 状态：目前状态机有这个 state 但永远不会进入，因为 useHandClassifier 在 face 不对时返回 `targetHand: null`（会进 NO_HAND 而不是 WRONG_FACE）。修法：在 useHandClassifier 区分"手在画面里但面朝错误" vs "没有手"
- [ ] 后置摄像头时 Canvas overlay 的坐标镜像：后置摄像头不镜像视频，但 MediaPipe 返回的 landmark 坐标仍然是 mirrored 的，需要确认 overlay 圆圈位置是否准确

**拉伸目标（有时间再做）：**
- [ ] TTS 语音播报（Web Speech API）
- [ ] LLM coaching 文案（`POST /api/coaching`）
- [ ] 后端 recap 摘要（`POST /api/recap`）

---

## 文件结构（实际）

```
AcuGuide/
├── src/
│   ├── App.tsx
│   ├── main.tsx                    # 无 StrictMode
│   ├── index.css                   # Tailwind directives + dark body
│   ├── vite-env.d.ts
│   ├── pages/
│   │   ├── HomePage.tsx
│   │   ├── SafetyPage.tsx
│   │   ├── RoutinePage.tsx
│   │   ├── CameraPage.tsx          # 核心页面
│   │   └── RecapPage.tsx
│   ├── hooks/
│   │   ├── useMediaPipe.ts
│   │   ├── useHandClassifier.ts
│   │   ├── usePressDetection.ts
│   │   └── useCoachingState.ts
│   ├── utils/
│   │   ├── landmarks.ts
│   │   ├── geometry.ts
│   │   └── drawOverlay.ts
│   ├── data/
│   │   └── acupoints.json
│   └── types/
│       └── index.ts
├── index.html
├── package.json
├── vite.config.ts                  # host: true, HTTPS via mkcert certs
├── tailwind.config.js
├── tsconfig.app.json
└── tsconfig.node.json
```

## Dev 命令

```bash
npm run dev      # HTTPS on https://localhost:5173 + https://10.31.150.113:5173
npm run build    # 生产构建
npx tsc --noEmit # 类型检查
```

## 症状 → 穴位映射

| 症状 | 穴位 | 手面 |
|------|------|------|
| tension_headache | TE3 | 手背朝摄像头 |
| neck_shoulder_tension | SI3 | 手背/尺侧朝摄像头 |
| menstrual_discomfort | PC6 | 手心朝摄像头（前臂外插值） |

## 安全规则（不可改动）

- 文案里**不能出现** treat / cure / heal / diagnose
- SafetyPage 必须强制确认，不能跳过
- 用户选 "Felt worse" → 显示停止提示，不推荐继续
- LI4 全局排除（无需妊娠筛查）

---

## UI 重设计说明

**已完成（June 20, 2026）**

参考 Ladder-inspired iOS 深色运动 App 风格。

### 设计 token（tailwind.config.js 已扩展）
| token | 值 |
|---|---|
| `surface` | #101113 |
| `panel` | #171a1f |
| `panel-2` | #20242a |
| `lime` | #c8ff3d（主 accent） |
| `muted` | #9ba1a7 |
| `soft` | #6f767d |
| `c-orange` | #ff8a3d |
| `c-red` | #ff6b5f |
| `c-blue` | #82d8ff |

### 各页面变化
- **HomePage** — lime kicker + hero card（渐变背景）+ 可选中 routine stack，选中再点 Start
- **SafetyPage** — 深色 panel 卡片列表，lime "I understand" CTA
- **RoutinePage** — 3-col metric row + 编号 step list + prep card，lime "Open coach" CTA
- **CameraPage** — 底部 feedback card（状态标签 + coaching text + progress ring 合一），移除顶部独立 timer ring；新增点击对焦（iPhone 角括号样式，`#FFD60A`）
- **RecapPage** — 大 lime 分数卡 + 3-col metrics + self-report panel，Run again / Choose another routine

