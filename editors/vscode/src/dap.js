#!/usr/bin/env node
// Adaptateur DAP (Debug Adapter Protocol) pour ALEX : traduit les requêtes de VS Code (ou de tout client DAP)
// vers le protocole JSON Lines de `alexc debug --protocol 2` (docs/SDK.md, « Protocole du débogueur »).
// Aucune dépendance : node src/dap.js (messages DAP « Content-Length » sur stdin / stdout).
'use strict';

const { spawn } = require('child_process');
const path = require('path');

let seq = 1;
let buffer = Buffer.alloc(0);

function send(msg) {
    msg.seq = seq++;
    const body = Buffer.from(JSON.stringify(msg), 'utf8');
    process.stdout.write('Content-Length: ' + body.length + '\r\n\r\n');
    process.stdout.write(body);
}

function respond(req, body, success = true, message) {
    const r = { type: 'response', request_seq: req.seq, success, command: req.command };
    if (body !== undefined) r.body = body;
    if (!success) r.message = message || 'erreur';
    send(r);
}

function event(name, body) {
    send({ type: 'event', event: name, body: body || {} });
}

// ---------------------------------------------------------------- session ALEX
let child = null;
let childBuf = '';
let launchArgs = null;
let lastPause = null;          // dernier événement « paused »
let configured = false;
let started = false;
let entryPending = false;
let waitingInput = false;
let pendingVars = new Map();   // id -> requête DAP « variables »
let pendingEval = new Map();   // id -> requête DAP « evaluate »
let scopeRefs = new Map();     // ref synthétique -> liste de variables
let nextScope = 1000000;
let nextId = 1;
let terminated = false;

function alex(cmd) {
    if (child && child.stdin.writable) child.stdin.write(JSON.stringify(cmd) + '\n');
}

function visibleFrames() {
    return lastPause ? lastPause.frames : [];
}

function toDapVar(v) {
    return { name: v.name, value: v.value, type: v.type, variablesReference: v.ref || 0 };
}

function onAlexEvent(ev) {
    switch (ev.event) {
        case 'started':
            started = true;
            break;
        case 'paused': {
            lastPause = ev;
            scopeRefs = new Map();
            if (ev.reason === 'entry' && !configured) {
                entryPending = true;
                event('initialized');
                return;
            }
            const reason = { breakpoint: 'breakpoint', step: 'step', exception: 'exception', pause: 'pause', entry: 'entry' }[ev.reason] || 'pause';
            const body = { reason, threadId: 1, allThreadsStopped: true };
            if (ev.exception) {
                body.description = ev.exception.type;
                body.text = ev.exception.type + ' : ' + ev.exception.message;
            }
            event('stopped', body);
            break;
        }
        case 'output':
            event('output', { category: ev.category === 'log' ? 'console' : 'stdout', output: ev.text, source: ev.file ? { path: ev.file } : undefined, line: ev.line });
            break;
        case 'input':
            waitingInput = true;
            event('output', { category: 'console', output: '⌨ le programme attend une saisie : tapez-la dans la console de débogage\n' });
            break;
        case 'variables': {
            const req = pendingVars.get(ev.id);
            if (req) {
                pendingVars.delete(ev.id);
                respond(req, { variables: (ev.variables || []).map(toDapVar) });
            }
            break;
        }
        case 'evaluate': {
            const req = pendingEval.get(ev.id);
            if (req) {
                pendingEval.delete(ev.id);
                if (ev.error) respond(req, undefined, false, ev.error);
                else respond(req, { result: ev.result, type: ev.type, variablesReference: ev.ref || 0 });
            }
            break;
        }
        case 'error': {
            const req = pendingVars.get(ev.id) || pendingEval.get(ev.id);
            if (req) {
                pendingVars.delete(ev.id);
                pendingEval.delete(ev.id);
                respond(req, undefined, false, ev.message);
            } else {
                event('output', { category: 'stderr', output: 'débogueur : ' + ev.message + '\n' });
            }
            break;
        }
        case 'compile_error':
            event('output', { category: 'stderr', output: ev.message + '\n' });
            finish(1);
            break;
        case 'exception':
            event('output', { category: 'stderr', output: ev.message + '\n' });
            finish(ev.exitCode !== undefined ? ev.exitCode : 1);
            break;
        case 'terminated':
        case 'stopped':
            finish(ev.exitCode || 0);
            break;
    }
}

function finish(code) {
    if (terminated) return;
    terminated = true;
    event('exited', { exitCode: code });
    event('terminated');
}

function startChild(args) {
    const alexPath = args.alexPath || process.env.ALEX_PATH || 'alex';
    const argv = ['debug', '--protocol', '2'];
    if (args.breakOnException !== false) argv.push('--break-on-exception');
    argv.push(path.resolve(args.cwd || process.cwd(), args.program));
    for (const a of args.args || []) argv.push(a);
    child = spawn(alexPath, argv, { cwd: args.cwd || process.cwd(), env: Object.assign({}, process.env, { ALEX_FLUSH: '1' }) });
    child.stdout.setEncoding('utf8');
    child.stdout.on('data', (d) => {
        childBuf += d;
        let k;
        while ((k = childBuf.indexOf('\n')) >= 0) {
            const line = childBuf.slice(0, k);
            childBuf = childBuf.slice(k + 1);
            if (!line.trim()) continue;
            try { onAlexEvent(JSON.parse(line)); } catch (e) { event('output', { category: 'stdout', output: line + '\n' }); }
        }
    });
    child.stderr.setEncoding('utf8');
    child.stderr.on('data', (d) => event('output', { category: 'stderr', output: d }));
    child.on('error', (e) => { event('output', { category: 'stderr', output: 'impossible de lancer ' + alexPath + ' : ' + e.message + '\n' }); finish(1); });
    child.on('exit', (code) => finish(code || 0));
}

// ---------------------------------------------------------------- requêtes DAP
function handle(req) {
    const a = req.arguments || {};
    switch (req.command) {
        case 'initialize':
            respond(req, {
                supportsConfigurationDoneRequest: true,
                supportsConditionalBreakpoints: true,
                supportsHitConditionalBreakpoints: true,
                supportsLogPoints: true,
                supportsEvaluateForHovers: true,
                supportsTerminateRequest: true,
                supportsExceptionInfoRequest: true,
                exceptionBreakpointFilters: [{ filter: 'uncaught', label: 'Exceptions non rattrapées', default: true }],
            });
            break;
        case 'launch':
            launchArgs = a;
            startChild(a);
            respond(req);
            break;
        case 'setBreakpoints': {
            const file = a.source && a.source.path;
            const bps = (a.breakpoints || []).map((b) => {
                const o = { line: b.line };
                if (b.condition) o.condition = b.condition;
                if (b.hitCondition) { const n = parseInt(String(b.hitCondition).replace(/[^0-9]/g, ''), 10); if (n > 0) o.hitCount = n; }
                if (b.logMessage) o.logMessage = b.logMessage;
                return o;
            });
            alex({ command: 'breakpoints.set', file, breakpoints: bps });
            respond(req, { breakpoints: bps.map((b) => ({ verified: true, line: b.line })) });
            break;
        }
        case 'setExceptionBreakpoints':
            alex({ command: 'exceptions', break: (a.filters || []).indexOf('uncaught') >= 0 });
            respond(req);
            break;
        case 'configurationDone':
            configured = true;
            respond(req);
            if (launchArgs && launchArgs.stopOnEntry && lastPause) {
                event('stopped', { reason: 'entry', threadId: 1, allThreadsStopped: true });
            } else {
                alex({ command: 'continue' });
            }
            break;
        case 'threads':
            respond(req, { threads: [{ id: 1, name: 'principal' }] });
            break;
        case 'stackTrace': {
            const frames = visibleFrames();
            const out = [];
            for (let i = frames.length - 1; i >= 0; i--) {
                const f = frames[i];
                const p = f.file ? path.resolve((launchArgs && launchArgs.cwd) || process.cwd(), f.file) : undefined;
                out.push({ id: i, name: f.function, line: f.line, column: 1, source: p ? { name: path.basename(p), path: p } : undefined });
            }
            respond(req, { stackFrames: out, totalFrames: out.length });
            break;
        }
        case 'scopes': {
            const f = visibleFrames()[a.frameId];
            const scopes = [];
            if (f) {
                const ref = nextScope++;
                scopeRefs.set(ref, f.locals || []);
                scopes.push({ name: 'Locales', variablesReference: ref, expensive: false });
            }
            if (lastPause && lastPause.globals && lastPause.globals.length) {
                const ref = nextScope++;
                scopeRefs.set(ref, lastPause.globals);
                scopes.push({ name: 'Globales', variablesReference: ref, expensive: false });
            }
            respond(req, { scopes });
            break;
        }
        case 'variables': {
            const ref = a.variablesReference;
            if (scopeRefs.has(ref)) {
                respond(req, { variables: scopeRefs.get(ref).map(toDapVar) });
            } else {
                const id = nextId++;
                pendingVars.set(id, req);
                alex({ command: 'variables', ref, id });
            }
            break;
        }
        case 'evaluate': {
            if (waitingInput && a.context === 'repl') {
                waitingInput = false;
                alex({ command: 'input', text: a.expression });
                respond(req, { result: '(envoyé au programme)', variablesReference: 0 });
                break;
            }
            const id = nextId++;
            pendingEval.set(id, req);
            alex({ command: 'evaluate', expression: a.expression, frame: a.frameId !== undefined ? a.frameId : -1, id });
            break;
        }
        case 'exceptionInfo': {
            const ex = lastPause && lastPause.exception;
            respond(req, { exceptionId: ex ? ex.type : 'Exception', description: ex ? ex.message : '', breakMode: 'unhandled' });
            break;
        }
        case 'continue':
            alex({ command: 'continue' });
            respond(req, { allThreadsContinued: true });
            break;
        case 'next':
            alex({ command: 'step', mode: 'over' });
            respond(req);
            break;
        case 'stepIn':
            alex({ command: 'step', mode: 'into' });
            respond(req);
            break;
        case 'stepOut':
            alex({ command: 'step', mode: 'out' });
            respond(req);
            break;
        case 'pause':
            alex({ command: 'pause' });
            respond(req);
            break;
        case 'terminate':
        case 'disconnect':
            alex({ command: 'stop' });
            respond(req);
            setTimeout(() => { if (child) child.kill(); finish(0); if (req.command === 'disconnect') process.exit(0); }, 300);
            break;
        default:
            respond(req, undefined, false, 'requête non prise en charge : ' + req.command);
    }
}

process.stdin.on('data', (chunk) => {
    buffer = Buffer.concat([buffer, chunk]);
    while (true) {
        const sep = buffer.indexOf('\r\n\r\n');
        if (sep < 0) return;
        const header = buffer.slice(0, sep).toString('ascii');
        const m = /Content-Length:\s*(\d+)/i.exec(header);
        if (!m) { buffer = buffer.slice(sep + 4); continue; }
        const len = parseInt(m[1], 10);
        if (buffer.length < sep + 4 + len) return;
        const body = buffer.slice(sep + 4, sep + 4 + len).toString('utf8');
        buffer = buffer.slice(sep + 4 + len);
        try { handle(JSON.parse(body)); } catch (e) { event('output', { category: 'stderr', output: 'adaptateur : ' + e.message + '\n' }); }
    }
});
process.stdin.on('end', () => { if (child) child.kill(); process.exit(0); });
