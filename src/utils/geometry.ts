import type { Landmark, AnchorDef } from '../types'

export function euclidean(a: Landmark, b: Landmark): number {
  const dx = a.x - b.x
  const dy = a.y - b.y
  return Math.sqrt(dx * dx + dy * dy)
}

export function handSize(landmarks: Landmark[]): number {
  if (!landmarks[0] || !landmarks[9]) return 0
  return euclidean(landmarks[0], landmarks[9])
}

export function weightedTarget(landmarks: Landmark[], anchors: AnchorDef[]): Landmark {
  let x = 0, y = 0, z = 0
  for (const { landmark, weight } of anchors) {
    x += landmarks[landmark].x * weight
    y += landmarks[landmark].y * weight
    z += landmarks[landmark].z * weight
  }
  return { x, y, z }
}

export function stdDev(values: number[]): number {
  if (values.length === 0) return 0
  const mean = values.reduce((s, v) => s + v, 0) / values.length
  const variance = values.reduce((s, v) => s + (v - mean) ** 2, 0) / values.length
  return Math.sqrt(variance)
}

export function offsetVariance(offsets: { dx: number; dy: number }[]): number {
  const dxValues = offsets.map(o => o.dx)
  const dyValues = offsets.map(o => o.dy)
  return Math.max(stdDev(dxValues), stdDev(dyValues))
}
