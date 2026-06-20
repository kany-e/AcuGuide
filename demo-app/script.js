const routines = {
  tension: {
    label: "Tension Headache",
    short: "Tension-related discomfort",
    title: "30-Second Hand Pressure",
    description:
      "Gently press the highlighted region between your thumb and index finger. Hold steady and breathe slowly.",
    duration: 30,
    steps: [
      "Place the back of your hand in view.",
      "Find the highlighted target region.",
      "Press gently with the opposite thumb.",
      "Hold steady for 30 seconds.",
      "Stop if symptoms feel sharp, unusual, or worse."
    ]
  },
  period: {
    label: "Period Discomfort",
    short: "Gentle comfort support",
    title: "Gentle Hand Comfort",
    description:
      "A short comfort-support routine for mild discomfort. Stop if discomfort increases.",
    duration: 30,
    steps: [
      "Place your hand in view.",
      "Follow the highlighted hand region.",
      "Use gentle, steady pressure.",
      "Hold while breathing slowly.",
      "Stop if discomfort feels severe or unusual."
    ]
  },
  neck: {
    label: "Neck & Shoulder",
    short: "Everyday tension routine",
    title: "Everyday Tension Reset",
    description:
      "A hand-based guided routine for everyday tension. This is self-care guidance, not medical care.",
    duration: 30,
    steps: [
      "Place your hand in view.",
      "Align with the on-screen guide.",
      "Press gently near the highlighted region.",
      "Hold for 30 seconds.",
      "Stop if you feel numbness or sharp pain."
    ]
  }
};

const feedback = {
  no_hand: {
    state: "Looking for hand",
    text: "Move your hand into frame.",
    mode: "warn"
  },
  hand_detected: {
    state: "Hand detected",
    text: "Move toward the highlighted area.",
    mode: "warn"
  },
  target_off: {
    state: "Adjust position",
    text: "Shift slightly toward the target.",
    mode: "warn"
  },
  target_near: {
    state: "Good position",
    text: "Good position. Keep holding.",
    mode: "good"
  },
  complete: {
    state: "Complete",
    text: "Routine complete.",
    mode: "good"
  }
};

const state = {
  routineId: "tension",
  step: "home",
  timer: 0,
  interval: null,
  demoTimers: []
};

const appScreen = document.querySelector("#appScreen");
const flowList = document.querySelector("#flowList");

function init() {
  renderHome();
  bindClicks();
}

function setStep(step) {
  state.step = step;
  document.querySelectorAll("#flowList li").forEach((item) => {
    item.classList.toggle("active", item.dataset.step === step);
  });
  document.querySelectorAll(".tab").forEach((tab) => {
    const active =
      (step === "home" || step === "safety" || step === "preview") && tab.dataset.nav === "home" ||
      step === "coach" && tab.dataset.nav === "coach" ||
      step === "recap" && tab.dataset.nav === "recap";
    tab.classList.toggle("active", active);
  });
}

function useTemplate(selector) {
  const template = document.querySelector(selector);
  appScreen.replaceChildren(template.content.cloneNode(true));
}

function renderHome() {
  stopDemoTimers();
  setStep("home");
  useTemplate("#homeTemplate");
  const list = document.querySelector("#routineList");
  list.innerHTML = Object.entries(routines)
    .map(
      ([id, routine]) => `
        <button class="routine-card ${id === state.routineId ? "active" : ""}" data-routine="${id}">
          <span class="small-label">${routine.short}</span>
          <strong>${routine.label}</strong>
          <p>${routine.description}</p>
          <span class="routine-meta">
            <span>${routine.duration}s</span>
            <span>Coach</span>
            <span>Self-care</span>
          </span>
          <span class="routine-play" aria-hidden="true"></span>
        </button>
      `
    )
    .join("");
}

function renderSafety() {
  stopDemoTimers();
  setStep("safety");
  useTemplate("#safetyTemplate");
}

function renderPreview() {
  stopDemoTimers();
  setStep("preview");
  useTemplate("#previewTemplate");
  const routine = routines[state.routineId];
  document.querySelector("#routineCategory").textContent = routine.label;
  document.querySelector("#routineTitle").textContent = routine.title;
  document.querySelector("#routineDescription").textContent = routine.description;
  document.querySelector("#routineDuration").textContent = `${routine.duration}s`;
  document.querySelector("#routineSteps").innerHTML = routine.steps
    .map((step, index) => `<div><strong>${index + 1}</strong> ${step}</div>`)
    .join("");
}

function renderCoach() {
  stopDemoTimers();
  setStep("coach");
  state.timer = 0;
  useTemplate("#coachTemplate");
  document.querySelector("#coachRoutineTitle").textContent =
    routines[state.routineId].title;
  setProgress(0);
  setFeedback("no_hand");
}

function renderRecap() {
  stopDemoTimers();
  setStep("recap");
  useTemplate("#recapTemplate");
  document.querySelector("#recapTime").textContent =
    state.timer > 0 ? `${Math.min(state.timer, 30)} seconds` : "30 seconds";
}

function bindClicks() {
  document.addEventListener("click", (event) => {
    const routineButton = event.target.closest("[data-routine]");
    if (routineButton) {
      state.routineId = routineButton.dataset.routine;
      renderHome();
      return;
    }

    const action = event.target.closest("[data-action]")?.dataset.action;
    if (action) {
      handleAction(action);
      return;
    }

    const demoState = event.target.closest("[data-state]")?.dataset.state;
    if (demoState) {
      setFeedback(demoState);
      return;
    }

    const report = event.target.closest("[data-report]")?.dataset.report;
    if (report) {
      setReport(report);
      return;
    }

    const nav = event.target.closest("[data-nav]")?.dataset.nav;
    if (nav) {
      if (nav === "home") renderHome();
      if (nav === "coach") renderCoach();
      if (nav === "recap") renderRecap();
    }
  });
}

function handleAction(action) {
  const actions = {
    "open-safety": renderSafety,
    "start-selected": renderSafety,
    "back-home": renderHome,
    "accept-safety": renderPreview,
    "back-safety": renderSafety,
    "open-coach": renderCoach,
    "back-preview": renderPreview,
    "run-demo": runDemoSequence,
    "finish-routine": renderRecap,
    "restart-demo": () => {
      renderCoach();
      runDemoSequence();
    }
  };
  actions[action]?.();
}

function setFeedback(key) {
  const item = feedback[key];
  if (!item) return;

  const stateLabel = document.querySelector("#feedbackState");
  const feedbackText = document.querySelector("#feedbackText");
  const target = document.querySelector("#coachTarget");
  if (!stateLabel || !feedbackText || !target) return;

  stateLabel.textContent = item.state;
  feedbackText.textContent = item.text;
  target.classList.remove("warn", "good");
  if (item.mode) target.classList.add(item.mode);

  if (key === "target_near") {
    startProgress();
  } else if (key !== "complete") {
    pauseProgress();
  }
}

function setProgress(seconds) {
  const circle = document.querySelector("#progressCircle");
  const label = document.querySelector("#timerLabel");
  if (!circle || !label) return;
  const normalized = Math.min(seconds / routines[state.routineId].duration, 1);
  const circumference = 113;
  circle.style.strokeDashoffset = `${circumference - circumference * normalized}`;
  label.textContent = `${Math.min(seconds, routines[state.routineId].duration)}s`;
}

function startProgress() {
  if (state.interval) return;
  state.interval = window.setInterval(() => {
    state.timer += 1;
    setProgress(state.timer);
    if (state.timer >= routines[state.routineId].duration) {
      setFeedback("complete");
      window.clearInterval(state.interval);
      state.interval = null;
      state.demoTimers.push(window.setTimeout(renderRecap, 650));
    }
  }, 620);
}

function pauseProgress() {
  if (!state.interval) return;
  window.clearInterval(state.interval);
  state.interval = null;
}

function runDemoSequence() {
  stopDemoTimers();
  state.timer = 0;
  setProgress(0);
  [
    [0, "no_hand"],
    [850, "hand_detected"],
    [1750, "target_off"],
    [2850, "target_near"]
  ].forEach(([delay, key]) => {
    state.demoTimers.push(window.setTimeout(() => setFeedback(key), delay));
  });
}

function stopDemoTimers() {
  state.demoTimers.forEach((timerId) => window.clearTimeout(timerId));
  state.demoTimers = [];
  pauseProgress();
}

function setReport(report) {
  const reportText = document.querySelector("#reportText");
  if (!reportText) return;
  const copy = {
    better:
      "Rest and observe how you feel. This routine is for self-care support only.",
    same: "No problem. Self-care routines may not help every time.",
    worse:
      "Please stop this routine. Seek medical advice for severe, sudden, persistent, or worsening symptoms."
  };
  reportText.textContent = copy[report];
}

init();
