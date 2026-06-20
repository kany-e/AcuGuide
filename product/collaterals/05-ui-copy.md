# UI Copy

## Home Screen

### Header

**AcuGuide**

### Subtitle

Camera-guided hand acupressure routines for everyday self-care.

### Entry Cards

#### Tension Headache

Short hand routine for tension-related discomfort.

Button: **Start routine**

#### Period Discomfort

Gentle comfort-support routine for mild discomfort.

Button: **Start routine**

#### Neck & Shoulder Tension

Hand-based relaxation routine for everyday tension.

Button: **Start routine**

## Safety Screen

### Title

Before You Start

### Body

AcuGuide provides wellness self-care guidance only. It does not diagnose, treat, or replace medical care. Use gentle pressure only. Stop if you feel sharp pain, numbness, dizziness, unusual symptoms, or worsening discomfort.

### Extra Note

Do not press on broken, irritated, swollen, or infected skin. If pregnant or possibly pregnant, avoid certain pressure points unless advised by a clinician.

### Buttons

- **I understand**
- **Back**

## Routine Preview

### Tension Headache Title

30-Second Hand Pressure Routine

### Tension Headache Body

Place your hand in the camera frame. Gently press the highlighted region between your thumb and index finger. Hold steady and breathe slowly.

### Routine Details

- Duration: 30 seconds
- Pressure: gentle and steady
- Goal: guided self-care practice

### Buttons

- **Open camera**
- **Back**

## Camera Screen

### Default Prompt

Place your hand in the frame.

### Feedback States

| State | Copy |
|---|---|
| no_camera | Camera is unavailable. Try demo mode. |
| permission_denied | Camera permission is needed for live feedback. |
| no_hand | Move your hand into frame. |
| hand_detected | Hand detected. Move toward the highlighted area. |
| target_off | Move slightly toward the target region. |
| target_near | Good position. Keep holding. |
| unstable | Hold steady and breathe slowly. |
| target_lost | Timer paused. Find the target again. |
| complete | Routine complete. |

### Buttons

- **Use demo mode**
- **Finish routine**
- **Stop**

## Recap Screen

### Title

Routine Complete

### Metrics

- Hold time: 30 seconds completed
- Position: near target region
- Stability: steady hold

### Self-Report

How do you feel after this routine?

Buttons:

- **A bit better**
- **No clear change**
- **Worse or unusual**

### Better Response

Take a moment to rest and observe how you feel. This routine is for self-care support only.

### No Change Response

No problem. Self-care routines may not help every time. Rest and monitor how you feel.

### Worse Response

Please stop this routine. If symptoms are severe, sudden, persistent, or worsening, consider seeking medical advice.

## Copy QA Checklist

- [ ] No "treat", "cure", or "diagnose".
- [ ] "Wellness self-care" appears before any routine.
- [ ] Safety copy is visible before camera flow.
- [ ] Camera feedback is short and action-oriented.
- [ ] Recap summarizes execution, not medical outcome.

