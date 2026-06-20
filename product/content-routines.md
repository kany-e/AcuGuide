# Content And Routine Draft

## Content Principle

Routine 内容必须固定、短、可审查。LLM 只能改写语气，不能自由生成新穴位或医疗建议。

这些内容是 hackathon demo 草案，不是医学建议。最终提交前需要至少一次安全措辞检查。

## Routine 1: Tension Headache

**Product label:** Tension headache  
**Demo priority:** P0  
**Goal:** 展示手部视觉反馈最清楚的一条主路径。  
**Target region:** Thumb-index web area, commonly referred to as LI-4 / Hegu in acupressure references.  
**Safety note:** Avoid this point if pregnant. Do not press over wounds, rash, swelling, redness, infection, or broken skin.

### User-facing copy

Try a short hand pressure routine for tension-related discomfort. Place your hand in the camera frame, gently press the highlighted area between your thumb and index finger, and hold steady while breathing slowly.

### Steps

1. Put the back of your hand facing the camera.
2. Move your hand until the target area is visible.
3. Place your opposite thumb near the highlighted region.
4. Press gently and hold for 30 seconds.
5. Stop if you feel sharp pain, numbness, dizziness, or worsening symptoms.

### Feedback states

- Hand not visible: Move your hand into frame.
- Target not aligned: Move slightly toward the highlighted area.
- Good position: Good position. Keep holding.
- Unstable: Hold steady and breathe slowly.
- Complete: Routine complete.

## Routine 2: Period Discomfort

**Product label:** Period discomfort  
**Demo priority:** P1  
**Goal:** 提供情绪共鸣强的入口，但避免治疗承诺。  
**Target region:** Hand comfort routine using the same visual hand coaching mechanics.  
**Important caution:** Do not position this as treating menstrual cramps. If pregnancy is possible, avoid LI-4 style pressure points unless advised by a clinician.

### User-facing copy

This is a gentle comfort-support routine, not a treatment. Use it only for mild discomfort, and stop if symptoms feel severe, unusual, or worsening.

### Steps

1. Place your hand in the camera frame.
2. Follow the highlighted hand region.
3. Use gentle, steady pressure.
4. Hold for 30 seconds while breathing slowly.
5. Stop if discomfort increases.

### Product note

这个入口适合讲故事，但不适合作为主 demo 的医学 claim。Pitch 中应说 “comfort support”，不要说 “relieves period cramps” 或 “treats cramps”。

## Routine 3: Neck And Shoulder Tension

**Product label:** Neck and shoulder tension  
**Demo priority:** P1  
**Goal:** 服务久坐人群，用同一个手部 feedback engine 展示可扩展性。  
**Target region:** Hand routine placeholder, to be validated before stronger claims.

### User-facing copy

Try a short hand-based relaxation routine for everyday tension. This is not medical care; it is a guided self-care exercise.

### Steps

1. Place your hand in the camera frame.
2. Align your hand with the on-screen guide.
3. Press gently near the highlighted region.
4. Hold for 30 seconds.
5. Stop if you feel numbness, sharp pain, or worsening discomfort.

## Routine Data Checklist

- [ ] 每个 routine 有 symptom id。
- [ ] 每个 routine 有 title。
- [ ] 每个 routine 有 user-facing copy。
- [ ] 每个 routine 有 safety note。
- [ ] 每个 routine 有 3-5 步步骤。
- [ ] 每个 routine 有 red flag stop condition。
- [ ] LLM prompt 明确只能使用这些内容。

## Open Content Questions

- [ ] Period discomfort 是否保留为首页入口，还是改成 less medical 的 “body comfort”？
- [ ] Neck and shoulder tension 是否需要改成 “stress tension” 以减少具体健康 claim？
- [ ] 是否有队友或 mentor 能快速 review acupressure wording？

