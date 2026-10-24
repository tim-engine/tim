'use strict';
const { describe, it, before } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const addon = require('../index.js');

describe('loader', () => {
  it('exposes the tim namespace with the full API', () => {
    for (const fn of ['init', 'render', 'renderView', 'version']) {
      assert.equal(typeof addon.tim[fn], 'function', fn);
    }
  });

  it('reports the loaded binary', () => {
    assert.match(addon.nativePair, /^(darwin|linux)-(arm64|x64)$/);
    assert.ok(fs.existsSync(addon.binaryPath));
  });

  it('exposes the engine version', () => {
    assert.match(addon.tim.version(), /^\d+\.\d+\.\d+$/);
  });

  it('refuses to render before init', () => {
    assert.throws(() => addon.tim.render('index'), /not initialized/);
    assert.throws(() => addon.tim.renderView('plain'), /not initialized/);
  });
});

describe('render', () => {
  const base = path.join(__dirname, 'fixtures');

  before(() => {
    fs.mkdirSync(path.join(base, 'output'), { recursive: true });
    assert.equal(addon.tim.init('templates', 'output', base), true);
  });

  it('renders a view within a layout', () => {
    const html = addon.tim.render('index', 'base', { name: 'Node' });
    assert.ok(html.includes('<h1>Hello, Node!</h1>'));
    assert.ok(html.includes('<p>Welcome to Tim.</p>'));
    assert.ok(html.includes('<title>tim-napi fixture</title>'));
  });

  it('accepts data as a JSON string', () => {
    const html = addon.tim.render('index', 'base', '{"name":"Str"}');
    assert.ok(html.includes('<h1>Hello, Str!</h1>'));
  });

  it('renders a view without a layout', () => {
    const html = addon.tim.renderView('plain', { name: 'Solo' });
    assert.equal(html, '<p>Just a view, Solo</p>');
  });

  it('propagates Nim errors as JS errors', () => {
    assert.throws(() => addon.tim.render('nope'), /view not found/);
    assert.throws(() => addon.tim.render('index', 'nolayout'), /layout not found/);
    assert.throws(() => addon.tim.renderView('nope'), /view not found/);
    assert.throws(() => addon.tim.render('index', 'base', '{bad'), /invalid JSON/);
  });
});
