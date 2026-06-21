// Verified against standard / WHO-aligned acupoint references.
// Educational reference only; not medical advice.

export const MERIDIAN_COLORS = {
  lung: '#b8c6d9', li: '#d4b876', stomach: '#7ab89a', spleen: '#d4a857',
  heart: '#d97a85', si: '#d9a890', bladder: '#7ac0d4', kidney: '#9a85d4',
  pc: '#d485c0', sj: '#85d4c0', gb: '#6abd8a', liver: '#d48585',
  ren: '#f0e6d2', du: '#e8d4a0',
};

export const MERIDIANS = [
  { id: 'lung',    zh: '手太阴肺经',   en: 'Lung',            ab: 'LU' },
  { id: 'li',      zh: '手阳明大肠经', en: 'Large Intestine', ab: 'LI' },
  { id: 'stomach', zh: '足阳明胃经',   en: 'Stomach',         ab: 'ST' },
  { id: 'spleen',  zh: '足太阴脾经',   en: 'Spleen',          ab: 'SP' },
  { id: 'heart',   zh: '手少阴心经',   en: 'Heart',           ab: 'HT' },
  { id: 'si',      zh: '手太阳小肠经', en: 'Small Intestine', ab: 'SI' },
  { id: 'bladder', zh: '足太阳膀胱经', en: 'Bladder',         ab: 'BL' },
  { id: 'kidney',  zh: '足少阴肾经',   en: 'Kidney',          ab: 'KI' },
  { id: 'pc',      zh: '手厥阴心包经', en: 'Pericardium',     ab: 'PC' },
  { id: 'sj',      zh: '手少阳三焦经', en: 'Sanjiao',         ab: 'SJ' },
  { id: 'gb',      zh: '足少阳胆经',   en: 'Gallbladder',     ab: 'GB' },
  { id: 'liver',   zh: '足厥阴肝经',   en: 'Liver',           ab: 'LR' },
  { id: 'ren',     zh: '任脉',         en: 'Ren Mai',         ab: 'RN' },
  { id: 'du',      zh: '督脉',         en: 'Du Mai',          ab: 'GV' },
];

// Hand/forearm acupoints. x,y are in the 360 x 440 hand SVG coordinate box.
export const ACUPOINTS = [
  {
    id: 'LI4', nameZh: '合谷', nameEn: 'Hegu', pinyin: 'Hégǔ', mer: 'li', x: 156, y: 206,
    meridianZh: '手阳明大肠经', meridianEn: 'Large Intestine Meridian',
    locationZh: '在手背，第1、2掌骨之间，约当第2掌骨桡侧的中点处。',
    locationEn: 'On the back of the hand, between the first and second metacarpal bones, near the midpoint of the second metacarpal bone on the radial side.',
    indZh: '传统上常用于头痛、牙痛、面部不适、鼻塞、咽喉不适等相关调理。',
    indEn: 'Traditionally used in acupuncture practice for headache, toothache, facial discomfort, nasal congestion, and throat discomfort.',
    cautZh: '孕期慎用。本内容仅供学习参考，不替代专业医疗建议。',
    cautEn: 'Use with caution during pregnancy. Educational reference only; not medical advice.',
  },
  {
    id: 'PC6', nameZh: '内关', nameEn: 'Neiguan', pinyin: 'Nèiguān', mer: 'pc', x: 200, y: 344,
    meridianZh: '手厥阴心包经', meridianEn: 'Pericardium Meridian',
    locationZh: '在前臂掌侧，腕横纹上约2寸，两筋之间。',
    locationEn: 'On the palmar side of the forearm, about two cun above the wrist crease, between the two tendons.',
    indZh: '传统上常与恶心、胸闷、心神不宁、晕动不适等相关联。',
    indEn: 'Commonly associated in acupuncture practice with nausea, chest tightness, an unsettled spirit, and motion-related discomfort.',
    cautZh: '本内容仅供学习参考，不替代专业医疗建议。',
    cautEn: 'Educational reference only; not medical advice.',
  },
  {
    id: 'SJ5', nameZh: '外关', nameEn: 'Waiguan', pinyin: 'Wàiguān', mer: 'sj', x: 174, y: 320,
    meridianZh: '手少阳三焦经', meridianEn: 'Sanjiao Meridian',
    locationZh: '在前臂背侧，腕背横纹上约2寸，与内关相对。',
    locationEn: 'On the dorsal side of the forearm, about two cun above the dorsal wrist crease, opposite Neiguan.',
    indZh: '传统上常用于头侧不适、耳部不适、上肢酸楚等相关调理。',
    indEn: 'Traditionally used in acupuncture practice for side-of-head discomfort, ear discomfort, and aching of the arm.',
    cautZh: '本内容仅供学习参考，不替代专业医疗建议。',
    cautEn: 'Educational reference only; not medical advice.',
  },
  {
    id: 'PC8', nameZh: '劳宫', nameEn: 'Laogong', pinyin: 'Láogōng', mer: 'pc', x: 186, y: 214,
    meridianZh: '手厥阴心包经', meridianEn: 'Pericardium Meridian',
    locationZh: '在手掌中央，约当第2、3掌骨之间偏于第3掌骨处。',
    locationEn: 'At the center of the palm, between the second and third metacarpal bones, nearer the third.',
    indZh: '传统上常与心烦、口部不适、手心热等相关联。',
    indEn: 'Commonly associated in acupuncture practice with restlessness, mouth discomfort, and warmth of the palms.',
    cautZh: '本内容仅供学习参考，不替代专业医疗建议。',
    cautEn: 'Educational reference only; not medical advice.',
  },
  {
    id: 'HT7', nameZh: '神门', nameEn: 'Shenmen', pinyin: 'Shénmén', mer: 'heart', x: 214, y: 262,
    meridianZh: '手少阴心经', meridianEn: 'Heart Meridian',
    locationZh: '在腕部，腕掌侧横纹尺侧端，尺侧腕屈肌腱的桡侧凹陷处。',
    locationEn: 'At the wrist, on the ulnar end of the palmar crease, in the depression on the radial side of the flexor carpi ulnaris tendon.',
    indZh: '传统上常与睡眠不安、心神不宁、情绪紧张等相关联。',
    indEn: 'Commonly associated in acupuncture practice with restless sleep, an unsettled spirit, and emotional tension.',
    cautZh: '本内容仅供学习参考，不替代专业医疗建议。',
    cautEn: 'Educational reference only; not medical advice.',
  },
  {
    id: 'SI3', nameZh: '后溪', nameEn: 'Houxi', pinyin: 'Hòuxī', mer: 'si', x: 236, y: 174,
    meridianZh: '手太阳小肠经', meridianEn: 'Small Intestine Meridian',
    locationZh: '在手尺侧，第5掌指关节后方，握拳时横纹尽头赤白肉际处。',
    locationEn: 'On the ulnar side of the hand, in the depression proximal to the head of the fifth metacarpal bone, at the end of the crease when a loose fist is made.',
    indZh: '传统上常用于颈项强紧、肩背不适、头侧不适等相关调理。',
    indEn: 'Traditionally used in acupuncture practice for neck stiffness, shoulder and upper-back discomfort, and side-of-head discomfort.',
    cautZh: '本内容仅供学习参考，不替代专业医疗建议。',
    cautEn: 'Educational reference only; not medical advice.',
  },
];

// UI strings
export const S = {
  title: { zh: '经络图谱', en: 'Meridian Atlas' },
  subtitle: { zh: 'Poetic Meridian Atlas', en: '诗词山河 · 经络图谱' },
  meridian: { zh: '经络', en: 'Meridian' },
  location: { zh: '定位', en: 'Location' },
  indications: { zh: '传统用途', en: 'Traditional indications' },
  notes: { zh: '注意事项', en: 'Notes' },
  fullBody: { zh: '全身图', en: 'Full Body' },
  hand: { zh: '手部', en: 'Hand' },
  coach: { zh: '推拿', en: 'Coach' },
  ask: { zh: '问询', en: 'Ask' },
  enterHand: { zh: '查看手部穴位', en: 'View hand points' },
  back: { zh: '返回全身', en: 'Back to body' },
  tapHand: { zh: '点按手部进入', en: 'Tap the hand to enter' },
  disclaimer: {
    zh: '本应用仅供学习与文化参考，不构成医疗建议、诊断或治疗。',
    en: 'For educational and cultural reference only. Not medical advice, diagnosis, or treatment.',
  },
};

// Connected back-of-hand + forearm outline (one contour), 360 x 440 box.
export const HAND_PTS = [
  [140,430],[136,360],[134,300],[137,272],[141,250],
  [130,232],[114,222],[99,208],[91,196],[88,188],[95,180],[111,182],[128,189],
  [137,172],[142,150],[140,96],[143,78],[152,72],[161,78],[164,96],[166,150],
  [170,162],[172,146],[170,60],[173,50],[182,45],[191,50],[194,62],[196,146],
  [200,160],[202,143],[200,72],[203,60],[211,55],[219,60],[222,74],[224,144],
  [228,158],[230,141],[229,108],[231,98],[238,94],[244,100],[246,112],[248,150],
  [244,200],[238,250],[231,272],[226,300],[224,360],[220,430],
];
