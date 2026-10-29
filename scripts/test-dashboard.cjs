#!/usr/bin/env node
'use strict';

// Prerequisites: moon, sqlite3, and Playwright with Chromium installed.
// Run from any directory: node scripts/test-dashboard.cjs
const assert = require('node:assert/strict');
const { execFile, spawn } = require('node:child_process');
const { once } = require('node:events');
const fs = require('node:fs/promises');
const net = require('node:net');
const os = require('node:os');
const path = require('node:path');
const { pathToFileURL } = require('node:url');
const { promisify } = require('node:util');
const { chromium } = require('playwright');

const exec = promisify(execFile);
const root = path.resolve(__dirname, '..');
const env = { ...process.env, MOON_WORK: 'off' };
const options = { cwd: root, env, timeout: 120000, maxBuffer: 4 * 1024 * 1024 };

async function freePort() {
  const reservation = net.createServer();
  reservation.listen(0, '127.0.0.1');
  await once(reservation, 'listening');
  const port = reservation.address().port;
  await new Promise((resolve, reject) => reservation.close(error => error ? reject(error) : resolve()));
  return port;
}

async function main() {
  const temp = await fs.mkdtemp(path.join(os.tmpdir(), 'issues-dashboard-'));
  let server;
  let browser;
  let serverOutput = '';
  try {
    await exec('moon', ['build', '--target', 'native', 'cmd/main'], options);
    const bin = path.resolve(root, process.env.ISSUES_BIN || '_build/native/debug/build/cmd/main/main.exe');
    const db = path.join(temp, 'issues.db');
    const cli = async (...args) => (await exec(bin, ['--db', db, ...args], options)).stdout.trim();
    await cli('init');
    const first = await cli('add', '--body', 'First original body', 'Browser first issue');
    const second = await cli('add', '--body', 'Second original body', 'Browser second issue');
    const initialGraph = JSON.parse(await cli('export-json'));
    const firstId = initialGraph.items.find(item => item.title === 'Browser first issue').id;
    const secondId = initialGraph.items.find(item => item.title === 'Browser second issue').id;
    assert.ok(first.includes(firstId) && second.includes(secondId), 'CLI created both fixtures');

    const port = await freePort();
    const origin = `http://127.0.0.1:${port}`;
    server = spawn(bin, ['--db', db, 'serve', '--host', '127.0.0.1', '--port', String(port)], { cwd: root, env, stdio: ['ignore', 'pipe', 'pipe'] });
    let serverError;
    server.on('error', error => { serverError = error; });
    server.stdout.on('data', chunk => { serverOutput += chunk; });
    server.stderr.on('data', chunk => { serverOutput += chunk; });
    const deadline = Date.now() + 60000;
    while (true) {
      if (serverError) throw serverError;
      if (server.exitCode !== null) throw new Error(`Dashboard server exited: ${serverOutput}`);
      try {
        const response = await fetch(`${origin}/healthz`, { signal: AbortSignal.timeout(1000) });
        if (response.ok) break;
      } catch (_) { /* The CLI builds the dashboard before listening. */ }
      if (Date.now() >= deadline) throw new Error(`Dashboard server did not start: ${serverOutput}`);
      await new Promise(resolve => setTimeout(resolve, 100));
    }

    browser = await chromium.launch({ headless: true });
    const page = await browser.newPage();
    page.setDefaultTimeout(10000);
    const browserErrors = [];
    const watchErrors = page => {
      page.on('pageerror', error => browserErrors.push(error.message));
      page.on('console', message => { if (message.type() === 'error') browserErrors.push(message.text()); });
    };
    watchErrors(page);
    // Chromium asks for this unrelated asset; keep console-error checking useful.
    await page.route('**/favicon.ico', route => route.fulfill({ status: 204 }));
    await page.goto(origin);
    await page.getByRole('heading', { name: 'Issues Dashboard', exact: true }).waitFor();
    await page.getByRole('button', { name: /Browser first issue/ }).click();
    await page.getByRole('heading', { name: `#${firstId} Browser first issue`, exact: true }).waitFor();
    const body = page.getByPlaceholder('Describe current context, acceptance criteria, or working notes.');
    assert.equal(await body.inputValue(), 'First original body');
    await page.getByRole('button', { name: /Browser second issue/ }).click();
    await page.getByRole('heading', { name: `#${secondId} Browser second issue`, exact: true }).waitFor();
    assert.equal(await body.inputValue(), 'Second original body');

    async function save(button, endpoint) {
      const responsePromise = page.waitForResponse(response => response.url() === origin + endpoint && response.request().method() === 'POST');
      await page.getByRole('button', { name: button, exact: true }).click();
      const response = await responsePromise;
      assert.equal(response.status(), 200, `${endpoint} succeeds`);
      await page.getByText('Saved.', { exact: true }).waitFor();
      return response.json();
    }
    const updatedBody = 'Body edited through the browser <not markup> & persisted';
    await body.fill(updatedBody);
    const savedGraph = await save('Save body', '/api/body');
    assert.equal(savedGraph.items.find(item => item.id === secondId).body, updatedBody);
    assert.ok((await cli('show', secondId)).includes(updatedBody), 'body persisted to SQLite');
    await page.reload();
    await page.getByRole('button', { name: /Browser second issue/ }).click();
    await page.getByRole('heading', { name: `#${secondId} Browser second issue`, exact: true }).waitFor();
    assert.equal(await body.inputValue(), updatedBody, 'body survives reload');

    let statusPosts = 0;
    page.on('request', request => {
      if (request.method() === 'POST' && request.url() === `${origin}/api/status`) statusPosts++;
    });
    await page.getByRole('button', { name: 'Done', exact: true }).click();
    await page.getByRole('button', { name: 'Save status', exact: true }).click();
    await page.getByText('Done status requires evidence.', { exact: true }).waitFor();
    assert.equal(statusPosts, 0, 'missing evidence is rejected before sending a request');
    assert.deepEqual(JSON.parse(await cli('export-json')).items.find(item => item.id === secondId).status,
      initialGraph.items.find(item => item.id === secondId).status, 'rejected update leaves persisted status unchanged');
    const evidence = 'Browser regression verified persistent edits';
    await page.getByPlaceholder('Evidence required when marking done.').fill(evidence);
    await save('Save status', '/api/status');
    assert.equal(statusPosts, 1);
    assert.ok((await cli('events', secondId)).includes(evidence), 'done evidence is persisted');
    assert.match(await cli('show', secondId), /^Status: done$/m, 'done status is persisted');

    const note = 'Browser note retained in the append-only event log';
    await page.getByPlaceholder('Append an event note.').fill(note);
    await save('Add note', '/api/note');
    assert.equal(await page.getByPlaceholder('Append an event note.').inputValue(), '');
    assert.ok((await cli('events', secondId)).includes(note), 'note is persisted');

    const exported = path.join(temp, 'export');
    await cli('dashboard', '--out', exported);
    const staticPage = await browser.newPage();
    staticPage.setDefaultTimeout(10000);
    watchErrors(staticPage);
    const staticPosts = [];
    staticPage.on('request', request => { if (request.method() === 'POST') staticPosts.push(request.url()); });
    await staticPage.goto(pathToFileURL(path.join(exported, 'index.html')).href);
    await staticPage.getByRole('heading', { name: 'Issues Dashboard', exact: true }).waitFor();
    assert.equal(await staticPage.locator('textarea, input').count(), 0, 'file export has no editors');
    assert.equal(await staticPage.getByRole('button', { name: /^(Save body|Save status|Add note)$/ }).count(), 0);
    await staticPage.getByRole('button', { name: /Browser second issue/ }).click();
    await staticPage.getByRole('heading', { name: `#${secondId} Browser second issue`, exact: true }).waitFor();
    await staticPage.getByText(updatedBody, { exact: true }).waitFor();
    await staticPage.getByRole('button', { name: /Browser first issue/ }).click();
    await staticPage.getByRole('heading', { name: `#${firstId} Browser first issue`, exact: true }).waitFor();
    await staticPage.getByText('First original body', { exact: true }).waitFor();
    assert.deepEqual(staticPosts, [], 'file export sends no mutation requests');
    assert.deepEqual(browserErrors, [], 'both dashboards have no browser errors');
    console.log('Dashboard browser regression passed: selection, body persistence, done evidence, notes, and read-only file export.');
  } finally {
    try {
      if (browser) await browser.close();
    } finally {
      try {
        if (server && server.exitCode === null && server.pid) {
          const exited = once(server, 'exit');
          server.kill('SIGTERM');
          const forceKill = setTimeout(() => server.kill('SIGKILL'), 3000);
          try { await exited; } finally { clearTimeout(forceKill); }
        }
      } finally {
        await fs.rm(temp, { recursive: true, force: true });
      }
    }
  }
}

main().catch(error => { console.error(error); process.exitCode = 1; });
