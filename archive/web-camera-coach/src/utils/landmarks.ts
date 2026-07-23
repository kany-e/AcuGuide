export const LANDMARKS = {
  WRIST: 0,
  THUMB_CMC: 1,
  THUMB_MCP: 2,
  THUMB_IP: 3,
  THUMB_TIP: 4,
  INDEX_MCP: 5,
  INDEX_PIP: 6,
  INDEX_DIP: 7,
  INDEX_TIP: 8,
  MIDDLE_MCP: 9,
  MIDDLE_PIP: 10,
  MIDDLE_DIP: 11,
  MIDDLE_TIP: 12,
  RING_MCP: 13,
  RING_PIP: 14,
  RING_DIP: 15,
  RING_TIP: 16,
  PINKY_MCP: 17,
  PINKY_PIP: 18,
  PINKY_DIP: 19,
  PINKY_TIP: 20,
} as const

// Resolve a point's per-point `press_finger` (acupoints.json) to a landmark index.
// TE3 uses INDEX_TIP (the separated index the re-shoot was captured with);
// everything else defaults to THUMB_TIP.
export function resolvePressFinger(name?: string): number {
  switch (name) {
    case 'INDEX_TIP':
      return LANDMARKS.INDEX_TIP
    case 'THUMB_TIP':
      return LANDMARKS.THUMB_TIP
    default:
      return LANDMARKS.THUMB_TIP
  }
}
