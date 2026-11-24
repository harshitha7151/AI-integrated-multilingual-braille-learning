let THREE;

const canvas = document.querySelector('#threeCanvas');
const stage = canvas?.parentElement;
const detail = {
  title: document.querySelector('#componentTitle'),
  description: document.querySelector('#componentDescription'),
  status: document.querySelector('#componentStatus'),
  source: document.querySelector('#componentSource'),
  evidence: document.querySelector('#componentEvidence'),
};
const sceneState = document.querySelector('#sceneState');
const nodeButtons = document.querySelector('#nodeButtons');
const motionToggle = document.querySelector('#motionToggle');
const connectionText = document.querySelector('#connectionText');
const resetButton = document.querySelector('#cameraReset');
const overviewButton = document.querySelector('#cameraOverview');
const fullscreenButton = document.querySelector('#sceneFullscreen');

const nodes = [
  { id: 'speech', label: 'Speech input', component: 'Android speech recognition', file: 'lib/tutor/speech_to_text_recognizer.dart', description: 'Recognition runs on the phone after the learner explicitly starts listening. A laptop microphone is never used. This display lights only after a corresponding mobile event arrives.', matches: type => type.startsWith('speech_recognition'), color: 0x67dfff },
  { id: 'tutorInput', label: 'Tutor input', component: 'Flutter voice tutor controller', file: 'lib/tutor/voice_tutor_controller.dart', description: 'The phone tutor receives typed or recognized input. It checks validated local actions before sending an educational question to the backend.', matches: type => type === 'tutor_input_received', color: 0xb697ff },
  { id: 'intent', label: 'Contextual interpreter', component: 'Configured Ollama JSON interpreter', file: 'resonant_backend/main.py | lib/tutor/http_tutor_intent_interpreter.dart', description: 'When the local deterministic parser cannot resolve a non-question command, the backend may return a schema-validated intent candidate. Flutter still validates and executes it locally. This is not the experimental CLINC150 classifier.', matches: type => type.startsWith('tutor_intent_interpreted') || type.startsWith('tutor_intent_interpretation_'), color: 0xffb86b },
  { id: 'resolver', label: 'Command resolver', component: 'Deterministic parser and validator', file: 'lib/tutor/voice_command_parser.dart | lib/tutor/tutor_action_controller.dart', description: 'Known commands are resolved locally and validated against the current screen. Live navigation does not invoke the experimental CLINC150 model.', matches: type => type.includes('command_parsed') || type.includes('action_validated') || type.includes('navigation'), color: 0x8da7ff },
  { id: 'braille', label: 'Braille engine', component: 'Deterministic mapping and checking', file: 'lib/core/braille/ | resonant_backend/verified_braille.py', description: 'Verified tables encode supported text and validate learner input. This is deterministic processing, not a model prediction.', matches: type => type.includes('braille'), color: 0x72e5bc },
  { id: 'learning', label: 'Learning state', component: 'Lessons, practice and assessments', file: 'lib/main.dart | resonant_backend/assessment_service.py', description: 'These events describe state changes or attempts actually emitted by the application. Rule-based recommendations are kept distinct from experimental ML.', matches: type => /lesson|language|assessment|exercise|mastery|recommendation|hint/.test(type), color: 0xf2c675 },
  { id: 'tutor', label: 'Tutor service', component: 'FastAPI and configured Ollama', file: 'resonant_backend/main.py | lib/tutor/voice_tutor_controller.dart', description: 'This node activates only for a tutor backend request or response event. A local command does not imply that Ollama ran.', matches: type => type.startsWith('tutor_backend_request') || type.startsWith('tutor_response'), color: 0xc79aff },
  { id: 'tts', label: 'Spoken output', component: 'Flutter TTS', file: 'lib/main.dart | lib/tutor/voice_tutor_controller.dart', description: 'TTS plays on the mobile phone. Events show only reported speech state; this dashboard does not receive or replay device audio.', matches: type => type.startsWith('tts_'), color: 0xff8dd2 },
  { id: 'experimental', label: 'Experimental ML', component: 'Saved CLINC150 pipelines', file: 'resonant_backend/aiml_dashboard_service.py | aiml/artifacts/', description: 'Saved TF-IDF classifiers run only in the experiment playground. They are not used for live navigation or production recommendations.', matches: () => false, color: 0xff9d64 },
];

let renderer, scene, camera, world, core, coreShell, innerCore, raycaster, pointer;
let resizeObserver, animationId = 0, activeUntil = 0, selectedId = null;
let dragging = false, moved = false, lastPointer = null, dragDistance = 0;
let theta = 0.18, phi = Math.PI / 2.08, radius = 11.8;
let desiredTheta = theta, desiredPhi = phi, desiredRadius = radius;
let isRunning = false;
let eventEvidence = null;
const nodeMeshes = new Map();
const links = new Map();
const particles = [];
const pulseRings = [];
const pickTargets = [];
const brailleDots = new Map();
const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

function material(color, options = {}) {
  return new THREE.MeshStandardMaterial({
    color,
    emissive: color,
    emissiveIntensity: options.emissiveIntensity ?? 0.42,
    roughness: options.roughness ?? 0.28,
    metalness: options.metalness ?? 0.44,
    transparent: options.opacity !== undefined,
    opacity: options.opacity ?? 1,
    wireframe: options.wireframe ?? false,
    side: options.doubleSide ? THREE.DoubleSide : THREE.FrontSide,
  });
}

function line(points, color, opacity = 0.5, linewidth = 1) {
  const geometry = new THREE.BufferGeometry().setFromPoints(points);
  const object = new THREE.Line(geometry, new THREE.LineBasicMaterial({
    color, transparent: true, opacity, linewidth,
  }));
  world.add(object);
  return object;
}

function makeCore() {
  core = new THREE.Group();
  world.add(core);

  const energy = new THREE.Mesh(
    new THREE.IcosahedronGeometry(0.62, 3),
    new THREE.MeshPhysicalMaterial({
      color: 0x8deaff, emissive: 0x1d72bd, emissiveIntensity: 1.75,
      roughness: 0.12, metalness: 0.48, transmission: 0.22, thickness: 0.8,
      clearcoat: 1, clearcoatRoughness: 0.08,
    }),
  );
  innerCore = new THREE.Group();
  innerCore.add(energy);
  core.add(innerCore);

  const octa = new THREE.Mesh(
    new THREE.OctahedronGeometry(1.04, 1),
    material(0x5e9aff, { opacity: 0.13, emissiveIntensity: 0.72, metalness: 0.8 }),
  );
  octa.scale.set(1.12, 0.86, 1.12);
  core.add(octa);

  coreShell = new THREE.Group();
  const shell = new THREE.Mesh(
    new THREE.IcosahedronGeometry(1.22, 1),
    material(0x6ddfff, { wireframe: true, opacity: 0.62, emissiveIntensity: 0.92 }),
  );
  coreShell.add(shell);
  core.add(coreShell);

  const crystal = new THREE.Mesh(
    new THREE.DodecahedronGeometry(1.42, 0),
    material(0x8873ff, { wireframe: true, opacity: 0.23, emissiveIntensity: 0.45 }),
  );
  crystal.rotation.set(0.32, 0.18, 0.44);
  core.add(crystal);

  for (const [rotation, radius, tube, color, arc] of [
    [[0.28, 0.1, 0.22], 1.72, 0.012, 0x72dfff, Math.PI * 2],
    [[1.04, 0.28, 0.72], 1.92, 0.009, 0x9d82ff, Math.PI * 2],
    [[1.42, 1.03, 0.04], 2.12, 0.008, 0x54d4c5, Math.PI * 1.72],
  ]) {
    const orbit = new THREE.Mesh(
      new THREE.TorusGeometry(radius, tube, 8, 180, arc),
      new THREE.MeshBasicMaterial({ color, transparent: true, opacity: 0.46 }),
    );
    orbit.rotation.set(...rotation);
    core.add(orbit);
  }

  const halo = new THREE.Mesh(
    new THREE.SphereGeometry(2.22, 36, 24),
    new THREE.MeshBasicMaterial({ color: 0x3b76ba, wireframe: true, transparent: true, opacity: 0.055 }),
  );
  core.add(halo);

  for (let index = 0; index < 3; index++) {
    const ring = new THREE.Mesh(
      new THREE.TorusGeometry(0.75 + index * 0.18, 0.012, 6, 80),
      new THREE.MeshBasicMaterial({ color: index === 1 ? 0x9c81ff : 0x64d7ff, transparent: true, opacity: 0 }),
    );
    ring.userData.birth = 0;
    ring.userData.duration = 1700 + index * 200;
    core.add(ring);
    pulseRings.push(ring);
  }
}

function makeStars() {
  const count = 280;
  const data = new Float32Array(count * 3);
  for (let i = 0; i < count; i++) {
    const r = 5 + Math.random() * 12;
    const a = Math.random() * Math.PI * 2;
    const z = (Math.random() * 2 - 1) * 8;
    data[i * 3] = Math.cos(a) * r;
    data[i * 3 + 1] = Math.sin(a) * r;
    data[i * 3 + 2] = z;
  }
  const geometry = new THREE.BufferGeometry();
  geometry.setAttribute('position', new THREE.BufferAttribute(data, 3));
  const stars = new THREE.Points(geometry, new THREE.PointsMaterial({
    color: 0x8bbcff, size: 0.022, transparent: true, opacity: 0.62,
    sizeAttenuation: true, depthWrite: false,
  }));
  world.add(stars);
}

function addPrimitive(group, object, nodeId) {
  object.userData.nodeId = nodeId;
  group.add(object);
  if (object.isMesh) pickTargets.push(object);
  return object;
}

function sphere(color, radius = 0.11, opacity = 1) {
  return new THREE.Mesh(new THREE.SphereGeometry(radius, 16, 12), material(color, { opacity, emissiveIntensity: 0.78 }));
}

function buildSpeech(group, id, color) {
  for (let index = 0; index < 4; index++) {
    const ring = new THREE.Mesh(
      new THREE.TorusGeometry(0.36 + index * 0.13, 0.009, 7, 64),
      new THREE.MeshBasicMaterial({ color, transparent: true, opacity: 0.62 - index * 0.08 }),
    );
    ring.rotation.set(index * 0.24, index * 0.15, index * 0.31);
    addPrimitive(group, ring, id);
  }
  const mic = new THREE.Mesh(new THREE.CylinderGeometry(0.11, 0.11, 0.38, 16), material(color));
  mic.rotation.z = Math.PI / 2;
  addPrimitive(group, mic, id);
  const cap = new THREE.Mesh(new THREE.SphereGeometry(0.11, 16, 10, 0, Math.PI * 2, 0, Math.PI / 2), material(0xc1f6ff));
  cap.position.x = 0.19;
  addPrimitive(group, cap, id);
}

function buildTutorInput(group, id, color) {
  const frame = new THREE.Mesh(new THREE.TorusKnotGeometry(0.3, 0.045, 72, 10, 2, 3), material(color, { emissiveIntensity: 0.85 }));
  addPrimitive(group, frame, id);
  for (let i = 0; i < 5; i++) {
    const bead = sphere(color, 0.045);
    const angle = (i / 5) * Math.PI * 2;
    bead.position.set(Math.cos(angle) * 0.48, Math.sin(angle) * 0.48, Math.sin(angle * 2) * 0.16);
    addPrimitive(group, bead, id);
  }
}

function buildResolver(group, id, color) {
  const center = new THREE.Mesh(new THREE.BoxGeometry(0.25, 0.25, 0.25), material(color));
  center.rotation.set(0.5, 0.4, 0.2);
  addPrimitive(group, center, id);
  const branches = [
    [[-0.1, 0, 0], [-0.3, 0.25, 0], [-0.56, 0.25, 0]],
    [[0.1, 0, 0], [0.3, 0, 0.12], [0.56, 0, 0.12]],
    [[0, -0.1, 0], [0, -0.3, -0.12], [0, -0.55, -0.12]],
  ];
  for (const points of branches) {
    const curve = new THREE.CatmullRomCurve3(points.map(([x, y, z]) => new THREE.Vector3(x, y, z)));
    const path = new THREE.Mesh(new THREE.TubeGeometry(curve, 16, 0.018, 5, false), material(color, { emissiveIntensity: 0.7 }));
    addPrimitive(group, path, id);
    const end = new THREE.Mesh(new THREE.OctahedronGeometry(0.085, 0), material(0xc6d1ff));
    end.position.copy(curve.getPoint(1));
    addPrimitive(group, end, id);
  }
}

function buildIntent(group, id, color) {
  const shell = new THREE.Mesh(new THREE.IcosahedronGeometry(0.42, 1), material(color, { wireframe: true, emissiveIntensity: 0.72 }));
  addPrimitive(group, shell, id);
  const rings = [0.63, 0.78].map((radius, index) => {
    const ring = new THREE.Mesh(new THREE.TorusGeometry(radius, 0.018, 6, 48), material(color, { transparent: true, opacity: 0.58 - index * 0.12 }));
    ring.rotation.set(index * 0.7, 0.45 + index * 0.6, 0.25);
    addPrimitive(group, ring, id);
    return ring;
  });
  group.userData.animate = time => {
    shell.rotation.x = time * 0.00022;
    shell.rotation.y = time * 0.00031;
    rings.forEach((ring, index) => { ring.rotation.z = time * (index ? -0.00018 : 0.00014); });
  };
}

function buildBraille(group, id, color) {
  const plate = new THREE.Mesh(new THREE.BoxGeometry(0.62, 0.84, 0.09), material(0x162c42, { opacity: 0.78, emissiveIntensity: 0.2 }));
  addPrimitive(group, plate, id);
  for (let dot = 1; dot <= 6; dot++) {
    const column = dot <= 3 ? -1 : 1;
    const row = (dot - 1) % 3;
    const bead = new THREE.Mesh(
      new THREE.SphereGeometry(0.09, 18, 14),
      new THREE.MeshPhysicalMaterial({ color, emissive: color, emissiveIntensity: 1.05, roughness: 0.17, metalness: 0.18 }),
    );
    bead.position.set(column * 0.16, 0.25 - row * 0.25, 0.07);
    bead.userData.brailleDot = dot;
    brailleDots.set(dot, bead);
    addPrimitive(group, bead, id);
  }
}

function buildLearning(group, id, color) {
  for (let index = 0; index < 3; index++) {
    const ring = new THREE.Mesh(new THREE.TorusGeometry(0.32 + index * 0.1, 0.018, 8, 72), material(index === 1 ? color : 0xc6a6ff, { emissiveIntensity: 0.58 }));
    ring.rotation.x = Math.PI / 2 + index * 0.34;
    ring.rotation.y = index * 0.43;
    addPrimitive(group, ring, id);
  }
  const marker = new THREE.Mesh(new THREE.ConeGeometry(0.09, 0.18, 8), material(0xffe4a2));
  marker.position.set(0.3, 0.17, 0.08);
  marker.rotation.z = -0.45;
  addPrimitive(group, marker, id);
}

function buildTutor(group, id, color) {
  for (let index = 0; index < 4; index++) {
    const layer = new THREE.Mesh(
      new THREE.CylinderGeometry(0.32 - index * 0.05, 0.32 - index * 0.05, 0.055, 6),
      material(index % 2 ? 0xe3caff : color, { emissiveIntensity: 0.52 }),
    );
    layer.position.y = (index - 1.5) * 0.13;
    layer.rotation.y = index * 0.35;
    addPrimitive(group, layer, id);
  }
  const orbit = new THREE.Mesh(new THREE.TorusGeometry(0.49, 0.012, 6, 64), new THREE.MeshBasicMaterial({ color, transparent: true, opacity: 0.75 }));
  orbit.rotation.set(0.9, 0.5, 0.2);
  addPrimitive(group, orbit, id);
}

function buildTts(group, id, color) {
  for (let index = 0; index < 9; index++) {
    const height = 0.12 + (Math.sin(index * 1.17) + 1) * 0.13;
    const bar = new THREE.Mesh(new THREE.CylinderGeometry(0.025, 0.025, height, 8), material(index % 2 ? color : 0xffc2e9));
    bar.position.set((index - 4) * 0.105, Math.cos(index * 0.76) * 0.08, 0);
    addPrimitive(group, bar, id);
  }
  const hoop = new THREE.Mesh(new THREE.TorusGeometry(0.55, 0.012, 6, 64, Math.PI * 1.55), new THREE.MeshBasicMaterial({ color, transparent: true, opacity: 0.68 }));
  hoop.rotation.set(0.5, 0.2, 0.55);
  addPrimitive(group, hoop, id);
}

function buildExperimental(group, id, color) {
  const network = new THREE.Group();
  const points = [];
  for (let layer = 0; layer < 3; layer++) {
    const count = layer === 1 ? 4 : 3;
    points[layer] = [];
    for (let index = 0; index < count; index++) {
      const position = new THREE.Vector3((layer - 1) * 0.28, (index - (count - 1) / 2) * 0.25, Math.cos(index + layer) * 0.12);
      points[layer].push(position);
      const cell = new THREE.Mesh(new THREE.OctahedronGeometry(0.065, 0), material(color, { emissiveIntensity: 0.85 }));
      cell.position.copy(position);
      addPrimitive(network, cell, id);
    }
  }
  for (let layer = 0; layer < 2; layer++) {
    for (const left of points[layer]) for (const right of points[layer + 1]) {
      const edge = new THREE.Line(
        new THREE.BufferGeometry().setFromPoints([left, right]),
        new THREE.LineBasicMaterial({ color, transparent: true, opacity: 0.32 }),
      );
      network.add(edge);
    }
  }
  addPrimitive(group, network, id);
}

function buildNode(node, position) {
  const group = new THREE.Group();
  group.position.copy(position);
  group.userData.nodeId = node.id;
  const builders = {
    speech: buildSpeech,
    tutorInput: buildTutorInput,
    intent: buildIntent,
    resolver: buildResolver,
    braille: buildBraille,
    learning: buildLearning,
    tutor: buildTutor,
    tts: buildTts,
    experimental: buildExperimental,
  };
  builders[node.id](group, node.id, node.color);

  const halo = new THREE.Mesh(
    new THREE.TorusGeometry(0.72, 0.006, 5, 72),
    new THREE.MeshBasicMaterial({ color: node.color, transparent: true, opacity: 0.22 }),
  );
  halo.rotation.x = Math.PI / 2.4;
  halo.userData.nodeId = node.id;
  group.add(halo);
  const hit = new THREE.Mesh(new THREE.SphereGeometry(0.77, 12, 8), new THREE.MeshBasicMaterial({ transparent: true, opacity: 0, depthWrite: false }));
  hit.userData.nodeId = node.id;
  group.add(hit);
  pickTargets.push(hit);
  world.add(group);
  nodeMeshes.set(node.id, group);
}

function makeLinks(positions) {
  const hub = new THREE.Vector3(0, 0, 0);
  nodes.forEach((node, index) => {
    const end = new THREE.Vector3(...positions[index]);
    const bend = new THREE.Vector3(end.x * 0.48, end.y * 0.48, (index % 2 ? 1 : -1) * 0.75);
    const curve = new THREE.CatmullRomCurve3([hub, bend, end]);
    const points = curve.getPoints(52);
    const geometry = new THREE.BufferGeometry().setFromPoints(points);
    const lineObject = new THREE.Line(geometry, new THREE.LineBasicMaterial({ color: node.color, transparent: true, opacity: 0.16 }));
    world.add(lineObject);
    const stream = [];
    for (let i = 0; i < 3; i++) {
      const point = new THREE.Mesh(new THREE.SphereGeometry(0.025, 8, 6), new THREE.MeshBasicMaterial({ color: node.color, transparent: true, opacity: 0.38 }));
      world.add(point);
      stream.push({ mesh: point, offset: i / 3 });
      particles.push({ curve, point, speed: 0.07 + i * 0.009, phase: i / 3, active: false, nodeId: node.id });
    }
    links.set(node.id, { curve, line: lineObject, stream });
  });
}

function describe(node, source = 'EXPLANATORY MAP') {
  if (!node) return;
  selectedId = node.id;
  detail.title.textContent = node.label;
  detail.description.textContent = node.description;
  detail.source.textContent = node.file;
  detail.status.textContent = source;
  for (const button of nodeButtons.querySelectorAll('button')) {
    button.setAttribute('aria-pressed', String(button.dataset.node === node.id));
  }
  const evidence = eventEvidence?.nodeId === node.id ? eventEvidence.event : null;
  if (detail.evidence) {
    detail.evidence.textContent = evidence
      ? `${evidence.event_type} · ${new Date(evidence.timestamp).toLocaleTimeString()} · ${evidence.source || 'mobile event'}\n${JSON.stringify(evidence.payload || {})}`
      : 'No matching live event received for this component in the current session.';
  }
}

function initScene() {
  if (!canvas || !stage) throw new Error('The 3D canvas is unavailable.');
  const probe = document.createElement('canvas');
  if (!probe.getContext('webgl2') && !probe.getContext('webgl')) throw new Error('WebGL is unavailable.');

  renderer = new THREE.WebGLRenderer({ canvas, antialias: true, alpha: true, powerPreference: 'low-power' });
  renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 1.5));
  renderer.setClearColor(0x050a14, 0);
  renderer.outputColorSpace = THREE.SRGBColorSpace;
  scene = new THREE.Scene();
  scene.fog = new THREE.FogExp2(0x080e1b, 0.017);
  camera = new THREE.PerspectiveCamera(42, 1, 0.1, 100);
  camera.position.set(0, 0, radius);
  world = new THREE.Group();
  scene.add(world);
  scene.add(new THREE.HemisphereLight(0x9cc9ff, 0x11172d, 2.1));
  const keyLight = new THREE.PointLight(0x56cfff, 62, 34);
  keyLight.position.set(3, 4, 7);
  scene.add(keyLight);
  const violetLight = new THREE.PointLight(0x805cff, 38, 30);
  violetLight.position.set(-5, -2, 5);
  scene.add(violetLight);

  makeStars();
  makeCore();
  const positions = [
    [-4.25, 2.05, 0.1], [-4.45, 0.05, 0.5], [-4.15, -2.05, -0.1],
    [-2.25, 3.65, -0.4], [-1.55, 3.35, -0.45], [1.7, 3.28, 0.12],
    [4.2, 1.88, -0.2], [4.25, -1.96, 0.25], [0.15, -3.55, -0.5],
  ];
  nodes.forEach((node, index) => buildNode(node, new THREE.Vector3(...positions[index])));
  makeLinks(positions);

  raycaster = new THREE.Raycaster();
  pointer = new THREE.Vector2();
  canvas.addEventListener('pointerdown', onPointerDown);
  canvas.addEventListener('pointermove', onPointerMove);
  canvas.addEventListener('pointerup', onPointerUp);
  canvas.addEventListener('pointercancel', onPointerUp);
  canvas.addEventListener('wheel', onWheel, { passive: false });
  resetButton?.addEventListener('click', resetCamera);
  overviewButton?.addEventListener('click', showOverview);
  fullscreenButton?.addEventListener('click', toggleFullscreen);
  motionToggle?.addEventListener('change', requestRender);
  resizeObserver = new ResizeObserver(resize);
  resizeObserver.observe(stage);
  resize();
  document.addEventListener('visibilitychange', onVisibility);
  window.addEventListener('resonant-live-event', onLiveEvent);
  statusObserver = new MutationObserver(syncConnectionStatus);
  if (connectionText) statusObserver.observe(connectionText, { childList: true, characterData: true, subtree: true });
  if (window.matchMedia('(prefers-reduced-motion: reduce)').matches) {
    if (motionToggle) motionToggle.checked = false;
  }
  sceneState.textContent = 'Concept map · awaiting actual mobile events';
  requestRender();
}

function resize() {
  if (!renderer || !stage) return;
  const width = Math.max(1, stage.clientWidth);
  const height = Math.max(1, stage.clientHeight);
  camera.aspect = width / height;
  camera.fov = width < 560 ? 49 : 42;
  camera.updateProjectionMatrix();
  renderer.setSize(width, height, false);
  desiredRadius = Math.max(desiredRadius, width < 560 ? 13.6 : 11.8);
  requestRender();
}

function nodeFromObject(object) {
  let current = object;
  while (current && !current.userData?.nodeId) current = current.parent;
  return current || null;
}

function getHit(event) {
  const rect = canvas.getBoundingClientRect();
  pointer.x = ((event.clientX - rect.left) / rect.width) * 2 - 1;
  pointer.y = -((event.clientY - rect.top) / rect.height) * 2 + 1;
  raycaster.setFromCamera(pointer, camera);
  const intersections = raycaster.intersectObjects(pickTargets, false);
  return intersections.length ? nodeFromObject(intersections[0].object) : null;
}

function onPointerDown(event) {
  if (event.button !== undefined && event.button !== 0) return;
  dragging = true;
  moved = false;
  dragDistance = 0;
  lastPointer = { x: event.clientX, y: event.clientY };
  canvas.setPointerCapture?.(event.pointerId);
  canvas.style.cursor = 'grabbing';
}

function onPointerMove(event) {
  if (dragging && lastPointer) {
    const dx = event.clientX - lastPointer.x;
    const dy = event.clientY - lastPointer.y;
    dragDistance += Math.abs(dx) + Math.abs(dy);
    if (dragDistance > 5) moved = true;
    if (moved) {
      desiredTheta -= dx * 0.006;
      desiredPhi = Math.max(0.22, Math.min(Math.PI - 0.22, desiredPhi + dy * 0.006));
      requestRender();
    }
    lastPointer = { x: event.clientX, y: event.clientY };
    return;
  }
  const hit = getHit(event);
  canvas.style.cursor = hit ? 'pointer' : 'grab';
  if (hit) canvas.setAttribute('aria-description', nodes.find(node => node.id === hit.userData.nodeId)?.label || '');
}

function onPointerUp(event) {
  if (!dragging) return;
  dragging = false;
  canvas.releasePointerCapture?.(event.pointerId);
  if (!moved) {
    const hit = getHit(event);
    if (hit) focusNode(hit.userData.nodeId, true);
  }
  lastPointer = null;
  canvas.style.cursor = 'grab';
  requestRender();
}

function onWheel(event) {
  event.preventDefault();
  desiredRadius = Math.max(7.5, Math.min(19, desiredRadius + event.deltaY * 0.009));
  requestRender();
}

function cameraFocusFor(nodeId) {
  const group = nodeMeshes.get(nodeId);
  if (!group) return;
  const worldPosition = new THREE.Vector3();
  group.getWorldPosition(worldPosition);
  const from = worldPosition.clone().normalize().multiplyScalar(Math.max(8.1, desiredRadius - 1.3));
  desiredTheta = Math.atan2(from.x, from.z);
  desiredPhi = Math.acos(Math.max(-1, Math.min(1, from.y / from.length())));
  desiredLookAt.copy(worldPosition.multiplyScalar(0.47));
  desiredRadius = Math.max(8.1, Math.min(desiredRadius, 12.5));
}

const desiredLookAt = { x: 0, y: 0, z: 0, copy(target) { this.x = target.x; this.y = target.y; this.z = target.z; return this; }, set(x, y, z) { this.x = x; this.y = y; this.z = z; } };
const lookAtTarget = { x: 0, y: 0, z: 0 };

function focusNode(id, speakStatus = false) {
  const node = nodes.find(item => item.id === id);
  if (!node) return;
  describe(node, eventEvidence?.nodeId === id ? 'LIVE MOBILE EVENT' : 'EXPLANATORY MAP');
  cameraFocusFor(id);
  if (speakStatus) sceneState.textContent = `Exploring component · ${node.component}`;
  requestRender();
}

function resetCamera() {
  desiredTheta = 0.18;
  desiredPhi = Math.PI / 2.08;
  desiredRadius = window.innerWidth < 700 ? 13.6 : 11.8;
  desiredLookAt.set(0, 0, 0);
  selectedId = null;
  for (const button of nodeButtons.querySelectorAll('button')) button.setAttribute('aria-pressed', 'false');
  detail.title.textContent = 'Choose a component';
  detail.description.textContent = 'Drag to rotate, use the wheel or pinch to zoom, and select a structure for details.';
  detail.status.textContent = 'EXPLANATORY MAP';
  detail.source.textContent = '';
  if (detail.evidence) detail.evidence.textContent = 'Select a component to inspect received live evidence.';
  sceneState.textContent = eventEvidence ? 'Concept map · last event remains in the live timeline' : 'Concept map · awaiting actual mobile events';
  requestRender();
}

function showOverview() {
  resetCamera();
}

async function toggleFullscreen() {
  try {
    if (!document.fullscreenElement) await stage.requestFullscreen?.();
    else await document.exitFullscreen?.();
  } catch (error) {
    sceneState.textContent = `Fullscreen unavailable · ${error.message}`;
  }
}

function firePulse(nodeId) {
  activeUntil = performance.now() + 2100;
  const link = links.get(nodeId);
  if (link) {
    link.line.material.opacity = 0.95;
    for (const particle of particles) if (particle.nodeId === nodeId) particle.active = true;
  }
  for (const ring of pulseRings) {
    ring.userData.birth = performance.now();
    ring.material.opacity = 0.72;
    ring.scale.setScalar(0.78);
  }
  requestRender();
}

function onLiveEvent(event) {
  const data = event.detail;
  if (!data?.event_type) return;
  const node = nodes.find(candidate => candidate.matches(data.event_type));
  if (node) {
    eventEvidence = { nodeId: node.id, event: data };
    describe(node, 'LIVE MOBILE EVENT');
    firePulse(node.id);
    sceneState.textContent = `LIVE EVENT · ${node.component}`;
  }
  const payload = data.payload || {};
  const dotsValue = Object.hasOwn(payload, 'dots') ? payload.dots : payload.active_dots;
  const reportedDots = typeof dotsValue === 'string'
    ? dotsValue.split(',').map(value => Number(value.trim())).filter(Number.isInteger)
    : dotsValue;
  if (Array.isArray(reportedDots)) {
    const activeDots = new Set(reportedDots.filter(dot => Number.isInteger(dot) && dot >= 1 && dot <= 6));
    for (const [dot, mesh] of brailleDots) {
      const active = activeDots.has(dot);
      mesh.scale.setScalar(active ? 1.48 : 1);
      mesh.material.emissiveIntensity = active ? 2.2 : 1.05;
    }
  }
  if (payload.language) document.querySelector('#currentLanguage').textContent = payload.language;
}

let statusObserver;
function syncConnectionStatus() {
  const value = connectionText?.textContent?.trim() || '';
  if (/disconnected|reconnecting|expired|not connected|unavailable|session ended/i.test(value)) {
    sceneState.textContent = `SESSION ${value.toUpperCase()} · live animation is idle`;
  }
}

function render(time = 0) {
  animationId = 0;
  const moving = !!motionToggle?.checked && !reducedMotion && !document.hidden;
  const smoothing = moving ? 0.055 : 0.18;
  theta += (desiredTheta - theta) * smoothing;
  phi += (desiredPhi - phi) * smoothing;
  radius += (desiredRadius - radius) * smoothing;
  lookAtTarget.x += (desiredLookAt.x - lookAtTarget.x) * smoothing;
  lookAtTarget.y += (desiredLookAt.y - lookAtTarget.y) * smoothing;
  lookAtTarget.z += (desiredLookAt.z - lookAtTarget.z) * smoothing;
  camera.position.set(
    lookAtTarget.x + radius * Math.sin(phi) * Math.sin(theta),
    lookAtTarget.y + radius * Math.cos(phi),
    lookAtTarget.z + radius * Math.sin(phi) * Math.cos(theta),
  );
  camera.lookAt(lookAtTarget.x, lookAtTarget.y, lookAtTarget.z);

  if (moving) {
    core.rotation.y += 0.00034;
    core.rotation.x = Math.sin(time * 0.00013) * 0.035;
    coreShell.rotation.y -= 0.00062;
    coreShell.rotation.z += 0.0002;
    innerCore.rotation.y += 0.0018;
    innerCore.scale.setScalar(1 + Math.sin(time * 0.0015) * 0.025);
    world.rotation.y = Math.sin(time * 0.00008) * 0.012;
  }

  let pulseActive = false;
  for (const [nodeId, link] of links) {
    const active = time < activeUntil && selectedId === nodeId;
    link.line.material.opacity += ((active ? 0.9 : 0.16) - link.line.material.opacity) * 0.12;
    const group = nodeMeshes.get(nodeId);
    if (group) {
      if (moving) group.userData.animate?.(time);
      const pulse = moving ? 1 + Math.sin(time * 0.0011 + [...nodeMeshes.keys()].indexOf(nodeId)) * 0.015 : 1;
      const target = active ? 1.12 * pulse : pulse;
      const scale = group.scale.x + (target - group.scale.x) * 0.12;
      group.scale.setScalar(scale);
    }
    for (const particle of particles) {
      if (particle.nodeId !== nodeId) continue;
      if (moving || particle.active) {
        particle.phase = (particle.phase + particle.speed * (particle.active ? 1.8 : 1) * 0.016) % 1;
        particle.point.position.copy(link.curve.getPoint(particle.phase));
        particle.point.material.opacity = particle.active ? 0.96 : 0.38;
        particle.point.scale.setScalar(particle.active ? 1.55 : 1);
      }
      if (particle.active) {
        pulseActive = true;
        if (time >= activeUntil) particle.active = false;
      }
    }
  }

  for (const ring of pulseRings) {
    if (!ring.userData.birth) continue;
    const age = time - ring.userData.birth;
    const progress = Math.min(1, age / ring.userData.duration);
    ring.scale.setScalar(0.78 + progress * 1.8);
    ring.material.opacity = (1 - progress) * 0.72;
  }

  if (renderer && scene && camera) renderer.render(scene, camera);
  if (moving || dragging || pulseActive || time < activeUntil || Math.abs(radius - desiredRadius) > 0.025 || Math.abs(theta - desiredTheta) > 0.002 || Math.abs(phi - desiredPhi) > 0.002) requestRender();
}

function requestRender() {
  if (!isRunning || animationId || document.hidden) return;
  animationId = requestAnimationFrame(render);
}

function onVisibility() {
  if (document.hidden) {
    cancelAnimationFrame(animationId);
    animationId = 0;
  } else requestRender();
}

function onFullscreenChange() {
  resize();
  if (fullscreenButton) fullscreenButton.textContent = document.fullscreenElement ? 'Exit fullscreen' : 'Fullscreen';
}

function disposeScene() {
  isRunning = false;
  cancelAnimationFrame(animationId);
  resizeObserver?.disconnect();
  document.removeEventListener('visibilitychange', onVisibility);
  document.removeEventListener('fullscreenchange', onFullscreenChange);
  statusObserver?.disconnect();
  window.removeEventListener('resonant-live-event', onLiveEvent);
  canvas?.removeEventListener('pointerdown', onPointerDown);
  canvas?.removeEventListener('pointermove', onPointerMove);
  canvas?.removeEventListener('pointerup', onPointerUp);
  canvas?.removeEventListener('pointercancel', onPointerUp);
  canvas?.removeEventListener('wheel', onWheel);
  resetButton?.removeEventListener('click', resetCamera);
  overviewButton?.removeEventListener('click', showOverview);
  fullscreenButton?.removeEventListener('click', toggleFullscreen);
  motionToggle?.removeEventListener('change', requestRender);
  if (scene) {
    scene.traverse(object => {
      object.geometry?.dispose?.();
      if (Array.isArray(object.material)) object.material.forEach(item => item.dispose());
      else object.material?.dispose?.();
    });
  }
  renderer?.dispose();
  nodeMeshes.clear();
  links.clear();
  particles.length = 0;
  pulseRings.length = 0;
  pickTargets.length = 0;
  brailleDots.clear();
}

function addKeyboardControls() {
  for (const node of nodes) {
    const button = document.createElement('button');
    button.type = 'button';
    button.className = 'node-button';
    button.dataset.node = node.id;
    button.textContent = node.label;
    button.setAttribute('aria-pressed', 'false');
    button.addEventListener('click', () => focusNode(node.id, true));
    nodeButtons.append(button);
  }
}

addKeyboardControls();
document.addEventListener('fullscreenchange', onFullscreenChange);
window.addEventListener('pagehide', disposeScene, { once: true });
import('https://cdn.jsdelivr.net/npm/three@0.170.0/build/three.module.js').then(module => {
  THREE = module;
  isRunning = true;
  initScene();
}).catch(error => {
  disposeScene();
  sceneState.textContent = '3D view unavailable · accessible component controls remain available';
  console.warn('Resonant 3D lab could not start:', error.message);
});
