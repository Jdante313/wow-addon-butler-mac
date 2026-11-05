'use strict';

const { execFile } = require('node:child_process');
const { promisify } = require('node:util');
const { AppError } = require('./errors');

const execFileAsync = promisify(execFile);

function isSupported() {
  return process.platform === 'darwin';
}

function appleScript(lines, argv = [], timeout = 10 * 60 * 1000) {
  const args = [];
  for (const line of lines) args.push('-e', line);
  if (argv.length) args.push('--', ...argv);
  return execFileAsync('/usr/bin/osascript', args, {
    timeout,
    encoding: 'utf8',
    maxBuffer: 1024 * 1024,
  });
}

function canceled(error) {
  const text = `${error?.stderr || ''} ${error?.message || ''}`;
  return /\(-128\)|User canceled|用户已取消/i.test(text);
}

async function pickFolder({ title = '选择文件夹', defaultPath = '' } = {}) {
  if (!isSupported()) {
    throw new AppError('当前系统不支持原生文件夹选择，请手动填写路径', 'UNSUPPORTED', 400);
  }
  const lines = [
    'on run argv',
    'set promptText to item 1 of argv',
    'set startPath to item 2 of argv',
    'try',
    'set startFolder to POSIX file startPath',
    'set chosen to choose folder with prompt promptText default location startFolder',
    'on error errMsg number errNum',
    'if errNum = -128 then error number -128',
    'set chosen to choose folder with prompt promptText',
    'end try',
    'return POSIX path of chosen',
    'end run',
  ];
  try {
    const { stdout } = await appleScript(lines, [title, defaultPath || '']);
    const selected = String(stdout || '').trim().replace(/\/+$/, '');
    return { path: selected, canceled: !selected };
  } catch (error) {
    if (canceled(error)) return { path: '', canceled: true };
    throw new AppError(`无法打开文件夹选择器：${error.message}`, 'SELECT_FOLDER_FAILED', 500);
  }
}

async function pickFile({ title = '选择文件', defaultPath = '' } = {}) {
  if (!isSupported()) {
    throw new AppError('当前系统不支持原生文件选择，请手动填写路径', 'UNSUPPORTED', 400);
  }
  const lines = [
    'on run argv',
    'set promptText to item 1 of argv',
    'set startPath to item 2 of argv',
    'try',
    'set startFolder to POSIX file startPath',
    'set chosen to choose file with prompt promptText default location startFolder',
    'on error errMsg number errNum',
    'if errNum = -128 then error number -128',
    'set chosen to choose file with prompt promptText',
    'end try',
    'return POSIX path of chosen',
    'end run',
  ];
  try {
    const { stdout } = await appleScript(lines, [title, defaultPath || '']);
    const selected = String(stdout || '').trim();
    return { path: selected, canceled: !selected };
  } catch (error) {
    if (canceled(error)) return { path: '', canceled: true };
    throw new AppError(`无法打开文件选择器：${error.message}`, 'SELECT_FILE_FAILED', 500);
  }
}

async function pickSavePath({ title = '保存文件', defaultName = 'profile.wowpack', defaultPath = '' } = {}) {
  if (!isSupported()) {
    throw new AppError('当前系统不支持原生保存对话框，请手动填写路径', 'UNSUPPORTED', 400);
  }
  const lines = [
    'on run argv',
    'set promptText to item 1 of argv',
    'set fileName to item 2 of argv',
    'set startPath to item 3 of argv',
    'try',
    'set startFolder to POSIX file startPath',
    'set chosen to choose file name with prompt promptText default name fileName default location startFolder',
    'on error errMsg number errNum',
    'if errNum = -128 then error number -128',
    'set chosen to choose file name with prompt promptText default name fileName',
    'end try',
    'return POSIX path of chosen',
    'end run',
  ];
  try {
    const { stdout } = await appleScript(lines, [title, defaultName, defaultPath || '']);
    const selected = String(stdout || '').trim();
    return { path: selected, canceled: !selected };
  } catch (error) {
    if (canceled(error)) return { path: '', canceled: true };
    throw new AppError(`无法打开保存对话框：${error.message}`, 'SAVE_FILE_FAILED', 500);
  }
}

module.exports = { pickFolder, pickFile, pickSavePath, isSupported };
