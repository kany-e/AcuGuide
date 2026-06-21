import { Suspense, useMemo, useRef, useEffect, Component } from 'react';
import { Canvas, useFrame, useThree } from '@react-three/fiber';
import { OrbitControls, useGLTF, Html, ContactShadows } from '@react-three/drei';
import { EffectComposer, Bloom } from '@react-three/postprocessing';
import * as THREE from 'three';
import { clone as cloneSkinned } from 'three/examples/jsm/utils/SkeletonUtils.js';
import { MERIDIAN_COLORS } from './data';

const ARM_MERS = ['lung', 'pc', 'heart', 'li', 'sj', 'si'];
const LEG_MERS = ['stomach', 'gb', 'bladder', 'spleen', 'kidney', 'liver'];
const BUILD = 31;   // bump to force the channel useMemo to recompute on reload
const V = () => new THREE.Vector3();

/* ---------- find limbs from the skeleton by POSITION (naming-independent) ---------- */
const FINGER = /finger|thumb|index|middle|ring|pinky|toe|hand_?[1-9]|foot_?[1-9]|nub|end/i;
function skeletonBones(root) {
  let bs = [];
  root.traverse((o) => { if (o.isSkinnedMesh && o.skeleton && !bs.length) bs = o.skeleton.bones.slice(); });
  if (!bs.length) root.traverse((o) => { if (o.isBone) bs.push(o); });
  return bs;
}
const deArm = (n) => n.replace(/armature/ig, '');   // bone names end in "_Armature"; the "arm" in it was matching isArm on EVERY bone
const isArm = (n) => /arm|shoulder|elbow|wrist|hand|fore|clavicle/i.test(deArm(n));
const isLeg = (n) => /leg|thigh|hip|knee|shin|calf|ankle|foot|upleg/i.test(deArm(n));
const isSpine = (n) => /spine|chest|torso|neck|hips|pelvis|head|back/i.test(deArm(n));

// side: -1 left (x<0), +1 right (x>0), 0 centre. sortKey orders shoulder->hand / hip->foot.
function limbChain(root, bones, kindFn, side, sortKey) {
  const lp = (b) => root.worldToLocal(b.getWorldPosition(V()));
  let arr = bones.filter((b) => kindFn(b.name) && !FINGER.test(b.name)).map(lp)
    .filter((p) => (side < 0 ? p.x < -0.02 : side > 0 ? p.x > 0.02 : Math.abs(p.x) < 0.07));
  arr.sort(sortKey);
  const out = [];
  for (const p of arr) if (!out.length || out[out.length - 1].distanceTo(p) > 0.04) out.push(p);
  return out;
}
function extendTip(pts, len) {
  if (pts.length < 2) return pts;
  const a = pts[pts.length - 2], b = pts[pts.length - 1];
  return [...pts, b.clone().add(b.clone().sub(a).normalize().multiplyScalar(len))];
}
// insert interpolated points so projection pins the line along the whole limb
function densify(pts, perSeg) {
  if (pts.length < 2) return pts;
  const out = [];
  for (let i = 0; i < pts.length - 1; i++)
    for (let k = 0; k < perSeg; k++) out.push(pts[i].clone().lerp(pts[i + 1], k / perSeg));
  out.push(pts[pts.length - 1].clone());
  return out;
}
// project a chain of joint points onto the body surface by raycasting inward,
// so the meridian lies ON the mesh (any proportion / pose), not floating beside it.
function projectChain(meshes, ray, pts, acrossX, castDir) {
  const cd = castDir.clone().normalize();
  return pts.map((P) => {
    const a = P.clone().add(new THREE.Vector3(acrossX, 0, 0));
    ray.set(a.clone().add(cd.clone().multiplyScalar(0.4)), cd.clone().negate());
    const hit = ray.intersectObjects(meshes, true)[0];
    return hit ? hit.point.clone().add(cd.clone().multiplyScalar(0.006))
               : a.clone().add(cd.clone().multiplyScalar(0.018));
  });
}
// Laplacian smoothing removes the zigzag from low-poly facet hits
function smoothPts(pts, iters) {
  let p = pts.map((v) => v.clone());
  for (let it = 0; it < iters; it++) {
    const q = p.map((v) => v.clone());
    for (let i = 1; i < p.length - 1; i++)
      q[i] = p[i - 1].clone().add(p[i]).add(p[i + 1]).multiplyScalar(1 / 3);
    p = q;
  }
  return p;
}
const curveOf = (pts) => new THREE.CatmullRomCurve3(smoothPts(pts, 4), false, 'centripetal');

function ChannelLine({ curve, mer, onPick, dimmed, selected, part }) {
  const core = useMemo(() => new THREE.TubeGeometry(curve, 64, 0.0016, 8, false), [curve]);
  const halo = useMemo(() => new THREE.TubeGeometry(curve, 64, 0.0045, 8, false), [curve]);
  const hit = useMemo(() => new THREE.TubeGeometry(curve, 32, 0.03, 6, false), [curve]);
  const dots = useMemo(() => [0.08, 0.26, 0.44, 0.62, 0.8, 0.96].map((t) => curve.getPointAt(t).toArray()), [curve]);
  const op = dimmed ? 0.12 : 1;
  const ink = selected ? '#564e2d' : '#363c2f';      // soft sage-ink
  const wash = selected ? '#7a6c3e' : '#5b6551';
  return (
    <group
      onClick={(e) => { e.stopPropagation(); onPick && onPick(mer); }}
      onPointerOver={(e) => { e.stopPropagation(); document.body.style.cursor = 'pointer'; }}
      onPointerOut={() => { document.body.style.cursor = 'auto'; }}>
      <mesh geometry={hit} renderOrder={8} visible={false}><meshBasicMaterial /></mesh>
      <mesh geometry={halo} renderOrder={9}><meshBasicMaterial color={wash} transparent opacity={0.09 * op} depthTest={false} depthWrite={false} toneMapped={false} /></mesh>
      <mesh geometry={core} renderOrder={10}><meshBasicMaterial color={ink} transparent opacity={0.85 * op} depthTest={false} depthWrite={false} toneMapped={false} /></mesh>
      {dots.map((p, i) => (
        <group key={i} position={p}>
          <mesh renderOrder={11}><sphereGeometry args={[0.0075, 12, 12]} /><meshBasicMaterial color="#2a2e24" transparent opacity={0.16 * op} depthTest={false} toneMapped={false} /></mesh>
          <mesh renderOrder={12}><sphereGeometry args={[0.0042, 12, 12]} /><meshBasicMaterial color="#23271d" transparent opacity={0.92 * op} depthTest={false} toneMapped={false} /></mesh>
        </group>
      ))}
    </group>
  );
}
function Channels({ defs, solo, onPick, part }) {
  const vis = part ? defs.filter((d) => d.part === part) : defs;
  return (
    <group>
      {vis.map((d) => (
        <ChannelLine key={d.key} curve={d.curve} mer={d.mer} onPick={onPick} part={d.part}
          dimmed={solo && solo !== d.mer} selected={solo === d.mer} />
      ))}
    </group>
  );
}

/* ---------- real rigged mesh, auto-fitted, with skeleton-bound channels ---------- */
function GLBBody({ solo, onPick, lang, onEnterHand, part }) {
  const { scene } = useGLTF('/model.glb');
  const { root, defs, handPos, anchors } = useMemo(() => {
    const root = new THREE.Group();
    const m = cloneSkinned(scene);                       // skinned-safe clone
    m.traverse((o) => { if (o.isMesh) { o.material = new THREE.MeshStandardMaterial({ color: '#aebd9d', roughness: 0.85, metalness: 0.0, emissive: new THREE.Color('#2c3626'), emissiveIntensity: 0.12 }); o.frustumCulled = false; o.castShadow = true; } });
    root.add(m);
    const measure = () => { root.updateMatrixWorld(true); const b = new THREE.Box3().setFromObject(root); return { b, s: b.getSize(V()) }; };
    let { s } = measure();
    if (s.z > s.y * 1.2 && s.z >= s.x) m.rotateX(-Math.PI / 2);
    else if (s.x > s.y * 1.2 && s.x >= s.z) m.rotateZ(Math.PI / 2);
    ({ s } = measure());
    m.scale.multiplyScalar(1.7 / (s.y || 1));
    const { b } = measure();
    const c = b.getCenter(V());
    m.position.x -= c.x; m.position.z -= c.z; m.position.y -= b.min.y;
    root.updateMatrixWorld(true);

    let defs = [];
    let handPos = null;
    let anchors = {};
    try {
      const bones = skeletonBones(m);
      const byX = (a, b2) => Math.abs(a.x) - Math.abs(b2.x);
      const byY = (a, b2) => b2.y - a.y;
      const armR = limbChain(root, bones, isArm, +1, byX);
      const armL = limbChain(root, bones, isArm, -1, byX);
      const hands = armR.length ? armR : armL;
      handPos = hands.length ? hands[hands.length - 1].clone() : null;
      const lpb = (b) => root.worldToLocal(b.getWorldPosition(V()));
      const anchor = (re, side) => {
        for (const b of bones) {
          if (!re.test(b.name) || FINGER.test(b.name)) continue;
          const p = lpb(b);
          if (side === undefined || (side < 0 ? p.x < -0.02 : side > 0 ? p.x > 0.02 : Math.abs(p.x) < 0.07)) return p;
        }
        return null;
      };
      anchors = {
        head: anchor(/head/i, 0),
        chest: anchor(/chest|upperchest/i, 0) || anchor(/spine/i, 0),
        belly: anchor(/hips|pelvis/i, 0),
        arm: anchor(/lower_?arm|forearm|elbow/i, -1) || anchor(/arm/i, -1),
        leg: anchor(/lower_?leg|calf|shin|knee/i, -1) || anchor(/leg/i, -1),
        foot: anchor(/foot|ankle/i, -1),
      };
      const legR = limbChain(root, bones, isLeg, +1, byY);
      const legL = limbChain(root, bones, isLeg, -1, byY);
      const spine = limbChain(root, bones, isSpine, 0, byY);
      // three cannot reliably raycast a skinned mesh, so build plain proxy meshes
      // (same geometry, same world transform) and cast against those instead.
      const meshes = [];
      m.traverse((o) => {
        if (o.isMesh && o.geometry) {
          o.updateWorldMatrix(true, false);
          const pm = new THREE.Mesh(o.geometry);
          pm.matrixAutoUpdate = false;
          pm.matrixWorld.copy(o.matrixWorld);
          meshes.push(pm);
        }
      });
      const ray = new THREE.Raycaster();
      const FRONT = new THREE.Vector3(0, 0, 1), BACK = new THREE.Vector3(0, 0, -1);
      const lat = (sg) => new THREE.Vector3(sg, 0, 0);
      const arm = (pts, sg, sd) => {
        if (pts.length < 2) return [];
        const p = pts.slice();
        p[0] = p[0].clone().lerp(p[1], 0.24);                       // start down the upper arm
        // NO raycast: fixed push onto the front of the arm. deterministic, cannot loop.
        const off = (dx) => p.map((q) => q.clone().add(new THREE.Vector3(dx, 0, 0.03)));
        return [
          { key: 'LU' + sd, mer: 'lung', curve: curveOf(off(-sg * 0.011)) },
          { key: 'LI' + sd, mer: 'li', curve: curveOf(off(sg * 0.011)) },
        ];
      };
      const leg = (pts, sg, sd) => {
        if (pts.length < 2) return [];
        const p = pts.slice();
        p[0] = p[0].clone().lerp(p[1], 0.2);                        // start down the thigh
        const e = p.length - 1;
        if (e >= 1) p[e] = p[e - 1].clone().lerp(p[e], 0.7);        // end above the ankle
        // NO raycast on legs: push a fixed amount onto the front of the leg. deterministic, cannot loop.
        const off = (dx) => p.map((q) => q.clone().add(new THREE.Vector3(dx, 0, 0.045)));
        return [
          { key: 'ST' + sd, mer: 'stomach', curve: curveOf(off(-sg * 0.012)) },
          { key: 'GB' + sd, mer: 'gb', curve: curveOf(off(sg * 0.028)) },
        ];
      };
      const spineRD = spine.length > 2 ? spine.slice(1) : spine; // drop the head joint
      const armDefs = [...arm(armR.slice(1), +1, 'R'), ...arm(armL.slice(1), -1, 'L')].map((d) => ({ ...d, part: 'arm' }));
      const legDefs = [...leg(legR, +1, 'R'), ...leg(legL, -1, 'L')].map((d) => ({ ...d, part: 'leg' }));
      const torsoDefs = [];
      if (spineRD.length >= 2) {
        torsoDefs.push({ key: 'ren', mer: 'ren', part: 'torso', curve: curveOf(projectChain(meshes, ray, densify(spineRD, 6), 0, FRONT)) });
        torsoDefs.push({ key: 'du', mer: 'du', part: 'torso', curve: curveOf(projectChain(meshes, ray, densify(spineRD, 6), 0, BACK)) });
      }
      defs = [...armDefs, ...legDefs, ...torsoDefs];
    } catch (e) { defs = []; }
    return { root, defs, handPos, anchors };
  }, [scene, BUILD]);

  return (<group>
    <primitive object={root} />
    <Channels defs={defs} solo={solo} onPick={onPick} part={part} />
    {handPos && <HandHotspot pos={handPos} lang={lang} onEnterHand={onEnterHand} />}
    {anchors.head && <RegionLabel pos={anchors.head} text={lang === 'zh' ? '头部' : 'Head'} dx={0.14} dy={0.03} />}
    {anchors.chest && <RegionLabel pos={anchors.chest} text={lang === 'zh' ? '胸' : 'Chest'} dx={-0.2} dy={0.02} />}
    {anchors.belly && <RegionLabel pos={anchors.belly} text={lang === 'zh' ? '腹' : 'Abdomen'} dx={-0.2} dy={0.0} />}
    {anchors.arm && <RegionLabel pos={anchors.arm} text={lang === 'zh' ? '臂' : 'Arm'} dx={-0.1} dy={0.02} />}
    {anchors.leg && <RegionLabel pos={anchors.leg} text={lang === 'zh' ? '腿' : 'Leg'} dx={-0.12} dy={0.0} />}
    {anchors.foot && <RegionLabel pos={anchors.foot} text={lang === 'zh' ? '足' : 'Foot'} dx={-0.1} dy={-0.02} />}
  </group>);
}

/* ---------- placeholder (only if /model.glb fails to load) ---------- */
function Skin() { return <meshStandardMaterial color="#d6a87e" roughness={0.62} metalness={0.06} />; }
function Bone({ from, to, rA, rB }) {
  const a = new THREE.Vector3(...from), b = new THREE.Vector3(...to);
  const mid = a.clone().add(b).multiplyScalar(0.5), len = a.distanceTo(b);
  const quat = new THREE.Quaternion().setFromUnitVectors(new THREE.Vector3(0, 1, 0), b.clone().sub(a).normalize());
  return <mesh position={mid.toArray()} quaternion={quat}><cylinderGeometry args={[rB, rA, len, 16]} /><Skin /></mesh>;
}
function Blob({ p, s }) { return <mesh position={p} scale={s}><sphereGeometry args={[1, 24, 24]} /><Skin /></mesh>; }
function PlaceholderBody() {
  return (<group>
    <Blob p={[0, 1.63, 0.01]} s={[0.10, 0.122, 0.108]} />
    <Bone from={[0, 1.44, 0]} to={[0, 1.55, 0.005]} rA={0.052} rB={0.046} />
    <Blob p={[0, 1.36, 0]} s={[0.205, 0.085, 0.115]} />
    <Blob p={[0, 1.24, 0]} s={[0.165, 0.135, 0.115]} />
    <Blob p={[0, 1.06, 0]} s={[0.125, 0.12, 0.10]} />
    <Blob p={[0, 0.92, 0]} s={[0.16, 0.115, 0.115]} />
    <Bone from={[-0.185, 1.37, 0.01]} to={[-0.205, 1.12, 0.03]} rA={0.058} rB={0.044} />
    <Bone from={[-0.205, 1.12, 0.03]} to={[-0.222, 0.84, 0.05]} rA={0.044} rB={0.034} />
    <Blob p={[-0.224, 0.78, 0.06]} s={[0.05, 0.07, 0.032]} />
    <Bone from={[0.185, 1.37, 0.01]} to={[0.205, 1.12, 0.03]} rA={0.058} rB={0.044} />
    <Bone from={[0.205, 1.12, 0.03]} to={[0.222, 0.84, 0.05]} rA={0.044} rB={0.034} />
    <Blob p={[0.224, 0.78, 0.06]} s={[0.05, 0.07, 0.032]} />
    <Bone from={[-0.085, 0.9, 0.01]} to={[-0.11, 0.48, 0.02]} rA={0.088} rB={0.058} />
    <Bone from={[-0.11, 0.48, 0.02]} to={[-0.115, 0.08, 0.02]} rA={0.058} rB={0.04} />
    <Bone from={[0.085, 0.9, 0.01]} to={[0.11, 0.48, 0.02]} rA={0.088} rB={0.058} />
    <Bone from={[0.11, 0.48, 0.02]} to={[0.115, 0.08, 0.02]} rA={0.058} rB={0.04} />
  </group>);
}
class ModelBoundary extends Component {
  constructor(p) { super(p); this.state = { failed: false }; }
  static getDerivedStateFromError() { return { failed: true }; }
  render() { return this.state.failed ? <PlaceholderBody /> : this.props.children; }
}

function HandHotspot({ pos, lang, onEnterHand }) {
  const ref = useRef();
  useFrame((s) => { if (ref.current) ref.current.scale.setScalar(1 + 0.2 * Math.sin(s.clock.elapsedTime * 2.4)); });
  const lx = pos.x > 0 ? 0.07 : -0.07;
  return (
    <group position={[pos.x, pos.y, pos.z + 0.04]}>
      <mesh ref={ref} onClick={onEnterHand} renderOrder={13}>
        <sphereGeometry args={[0.018, 16, 16]} />
        <meshBasicMaterial color="#caa15a" toneMapped={false} depthTest={false} />
      </mesh>
      <Html distanceFactor={1.6} position={[lx, -0.03, 0]} center>
        <div className="brush-label sm" onClick={onEnterHand}>{lang === 'zh' ? '手部' : 'Hand'}</div>
      </Html>
    </group>
  );
}

// quiet brush label that names a region (no zoom-in, unlike the hand)
function RegionLabel({ pos, text, dx = 0, dy = 0 }) {
  if (!pos) return null;
  return (
    <Html distanceFactor={1.9} position={[pos.x + dx, pos.y + dy, (pos.z || 0) + 0.05]} center>
      <div className="brush-label sm soft">{text}</div>
    </Html>
  );
}

// render the figure toward the left third of the canvas
function ShiftLeft({ amount = 0.32 }) {
  const { camera, size } = useThree();
  useEffect(() => {
    camera.setViewOffset(size.width * (1 + amount), size.height, size.width * amount, 0, size.width, size.height);
    camera.updateProjectionMatrix();
    return () => { camera.clearViewOffset(); camera.updateProjectionMatrix(); };
  }, [camera, size, amount]);
  return null;
}

export default function Body3D({ lang, solo, onEnterHand, onPick, part }) {
  return (
    <div className="canvas-wrap">
      <Canvas camera={{ position: [0, 1.05, 3.0], fov: 42 }} dpr={[1, 2]} gl={{ antialias: true, alpha: true }} style={{ background: 'transparent' }}>
        <fog attach="fog" args={['#e6e7df', 7, 13]} />
        <ambientLight intensity={0.9} />
        <hemisphereLight args={['#ffffff', '#cdd2c4', 0.7]} />
        <directionalLight position={[2.5, 4, 3]} intensity={0.85} color="#fffaf0" castShadow />
        <directionalLight position={[-2.5, 2, -1.5]} intensity={0.35} color="#dfe6ea" />

        <Suspense fallback={<Html center><span className="loading3d">载入中…</span></Html>}>
          <group position={[0, -0.85, 0]}>
            <ModelBoundary><GLBBody solo={solo} onPick={onPick} lang={lang} onEnterHand={onEnterHand} part={part} /></ModelBoundary>
            <ContactShadows position={[0, 0.01, 0]} opacity={0.32} scale={3} blur={3} far={2} color="#5e6b54" />
          </group>
        </Suspense>

        <OrbitControls enablePan={false} minDistance={2.4} maxDistance={3.6} target={[0, 0.25, 0]} maxPolarAngle={Math.PI / 1.7} autoRotate autoRotateSpeed={0.5} />
      </Canvas>
    </div>
  );
}

try { useGLTF.preload('/model.glb'); } catch (e) { /* no model yet */ }
