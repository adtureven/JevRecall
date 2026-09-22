export const ACTIONS = {
  scan: { label: '扫描飞船', command: '扫描整艘飞船，报告当前状态', description: 'Inspect, scan or ask about the ship, status, surroundings, available actions or help. 查看、扫描、报告状态、询问怎么办。' },
  seal_leak: { label: '封闭泄漏', command: '关闭破损舱段的隔离门，阻止氧气泄漏', description: 'Seal the hull leak or close the damaged compartment isolation door to stop air escaping. 堵漏、关闭破损舱隔离门。' },
  restore_power: { label: '恢复供电', command: '接通备用电源，恢复飞船供电', description: 'Turn on backup power, repair or restart the power system. 接通备用电源、恢复供电。' },
  align_antenna: { label: '校准天线', command: '将通讯天线对准救援站', description: 'Align, repair or aim the communications antenna at the rescue station. 校准天线、对准救援站。' },
  send_beacon: { label: '发送求救', command: '发送包含我们坐标的求救信号', description: 'Transmit a distress beacon, SOS or coordinates to rescuers. 发出求救信号、发送坐标。' },
  launch: { label: '启动逃生舱', command: '让船员进入逃生舱，发射离船', description: 'Evacuate crew using the escape pod; launch the pod and leave the ship. 进入逃生舱并发射离船。' },
  wait: { label: '原地等待', command: '什么也不做，原地等待一轮', description: 'Explicitly wait or do nothing for a turn. 原地等待一轮。' },
  vent: { label: '打开外舱门', command: '打开外舱门，把舱内空气排到太空', description: 'Open an exterior airlock or deliberately vent breathable cabin air into space. 打开外舱门、排出舱内空气。 NOT closing an interior isolation door to seal a leak.' },
  unknown: { label: '无法识别', command: '', description: 'No single supported action: unrelated chat, only a negated command, requests to change game rules or invent items, ambiguous references without a target, or several distinct actions in one command. 无关、否定、修改规则、模糊或多步指令。' },
};

export const THRESHOLDS = Object.freeze({ confidence: 0.45, probability: 0.6, explicit: 0.7, risk: 1.5 });

export function initialState() {
  return { oxygen: 100, turn: 0, sealed: false, powered: false, aligned: false, beacon: false, outcome: 'active' };
}

export function objectives(state) {
  return [
    { id: 'seal_leak', label: '封闭泄漏', detail: '关闭破损舱段的隔离门', done: state.sealed },
    { id: 'restore_power', label: '恢复供电', detail: '启用备用电源', done: state.powered },
    { id: 'align_antenna', label: '校准天线', detail: '将天线对准救援站', done: state.aligned },
    { id: 'send_beacon', label: '发送求救', detail: '广播飞船坐标', done: state.beacon },
    { id: 'launch', label: '撤离船员', detail: '乘坐逃生舱离开', done: state.outcome === 'rescued' },
  ];
}

export function describe(state) {
  if (state.outcome === 'rescued') return '救援站已接住逃生舱。四名船员全部安全抵达，你把他们带回了家。';
  if (state.outcome === 'lost') return '氧气储备已耗尽，飞船失去联络。重新开始，尝试先封闭泄漏。';
  if (!state.sealed) return '微陨石击穿了「白鹭号」的货舱。空气正在流失，四名船员等候你的指令。先关闭破损舱段的隔离门。';
  if (!state.powered) return '泄漏已停止。主电源离线，通讯阵列和逃生舱无法启动。备用电源仍然完好。';
  if (!state.aligned) return '备用电源已接通。通讯天线偏离救援站，先校准方向，才能把求救信号送出去。';
  if (!state.beacon) return '通讯链路稳定。救援站还不知道你的位置，发送带有坐标的求救信号。';
  return '救援站已确认坐标，接应航线开放。让四名船员进入逃生舱，准备发射。';
}

export function checkAction(state, action) {
  if (state.outcome !== 'active') return '本次任务已经结束，请重新开始。';
  if (!Object.hasOwn(ACTIONS, action) || action === 'unknown') return '请描述一个具体动作，例如「接通备用电源」。每次只执行一步。';
  if (action === 'seal_leak' && state.sealed) return '泄漏已经封闭，无需重复操作。';
  if (action === 'restore_power' && state.powered) return '备用电源已经在线。';
  if (action === 'align_antenna' && !state.powered) return '天线伺服系统没有供电。先接通备用电源。';
  if (action === 'align_antenna' && state.aligned) return '天线已经对准救援站。';
  if (action === 'send_beacon' && !state.powered) return '通讯系统没有供电。先接通备用电源。';
  if (action === 'send_beacon' && !state.aligned) return '天线尚未对准救援站。先校准天线。';
  if (action === 'send_beacon' && state.beacon) return '救援站已收到坐标，可以撤离了。';
  if (action === 'launch' && !state.sealed) return '舱内气压尚未稳定。先封闭泄漏，船员才能安全转移。';
  if (action === 'launch' && !state.powered) return '逃生舱发射机构没有供电。先恢复供电。';
  if (action === 'launch' && !state.beacon) return '救援站还不知道你的位置。先完成天线校准并发送求救信号。';
  return null;
}

export function decide(state, answers) {
  if (state.outcome !== 'active') return { status: 'ended', message: describe(state) };
  const action = answers.action.choice;
  if (action === 'unknown' || answers.action.confidence < THRESHOLDS.confidence || answers.action.probabilities[action] < THRESHOLDS.probability || answers.explicit_command.noul < THRESHOLDS.explicit) {
    return { status: 'clarify', action, message: '这条指令还不够明确。请一次说一个动作，并说明操作对象；飞船状态没有改变。' };
  }
  const blocked = checkAction(state, action);
  if (blocked) return { status: 'blocked', action, message: blocked };
  if (action === 'vent' || answers.risk.score >= THRESHOLDS.risk) {
    return { status: 'confirm', action, message: action === 'vent' ? '打开外舱门会损失至少 35% 的氧气。确定要执行吗？' : `「${ACTIONS[action].label}」被模型评为高风险，请确认后执行。` };
  }
  return { status: 'execute', action };
}

// All world changes are deterministic. Model output never mutates state directly.
export function applyAction(state, action) {
  const blocked = checkAction(state, action);
  if (blocked) return { state, status: 'blocked', message: blocked };
  if (action === 'scan') return { state: { ...state }, status: 'executed', message: describe(state) };
  const next = { ...state, turn: state.turn + 1 };
  const costs = { seal_leak: 4, restore_power: 8, align_antenna: 8, send_beacon: 6, launch: 4, wait: 15, vent: 35 };
  if (action === 'seal_leak') next.sealed = true;
  if (action === 'restore_power') next.powered = true;
  if (action === 'align_antenna') next.aligned = true;
  if (action === 'send_beacon') next.beacon = true;
  next.oxygen = Math.max(0, next.oxygen - costs[action] - (next.sealed ? 0 : 6));
  if (next.oxygen === 0) next.outcome = 'lost';
  else if (action === 'launch') next.outcome = 'rescued';
  const messages = {
    seal_leak: '隔离门闭合，泄漏停止。舱内的呼吸声终于平稳下来。',
    restore_power: '备用电源启动。走廊灯光依次亮起，通讯系统重新上线。',
    align_antenna: '天线缓缓转动，锁定救援站。通讯链路已建立。',
    send_beacon: '求救信号已送达。救援站回复：「收到坐标，我们等你们。」',
    launch: '逃生舱成功分离。四名船员朝着救援站的灯光飞去。',
    wait: '一个操作周期过去了。没有新的信号，氧气还在消耗。',
    vent: '外舱门打开，空气涌入太空。紧急系统随后关闭舱门，但氧气已经流失。',
  };
  return { state: next, status: 'executed', message: next.outcome === 'active' ? messages[action] : describe(next), oxygenUsed: state.oxygen - next.oxygen };
}

export function publicState(state) {
  return { ...state, description: describe(state), objectives: objectives(state) };
}
