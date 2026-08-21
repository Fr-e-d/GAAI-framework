#!/usr/bin/env node
import { createHash } from 'node:crypto';
import { readFile, writeFile } from 'node:fs/promises';
import { spawnSync } from 'node:child_process';
import { pathToFileURL } from 'node:url';

const VERSION = '1.0.0';
const POLICY_KEYS = ['schema_version', 'policy_version', 'repository', 'limits', 'commands',
  'selectors', 'exhaustive_command_ids', 'non_executable_prefixes', 'broadening_prefixes',
  'dependency_inputs', 'risk_input_policy', 'required_environment'];
const LIMIT_KEYS = ['max_policy_bytes', 'max_diff_bytes', 'max_changed_paths', 'max_commands',
  'max_selectors', 'max_identifier_bytes', 'max_arguments_per_command', 'max_argument_bytes'];
const COMMAND_KEYS = ['id', 'argv', 'timeout_seconds', 'output_limit_bytes', 'config_paths', 'enabled'];
const SELECTOR_KEYS = ['id', 'path_prefixes', 'command_ids'];

class AdmissionError extends Error {
  constructor(reason, details = {}) { super(reason); this.reason = reason; this.details = details; }
}
const fail = (reason, details) => { throw new AdmissionError(reason, details); };
const digest = value => createHash('sha256').update(value).digest('hex');
const canonical = value => {
  if (Array.isArray(value)) return `[${value.map(canonical).join(',')}]`;
  if (value && typeof value === 'object') return `{${Object.keys(value).sort()
    .map(key => `${JSON.stringify(key)}:${canonical(value[key])}`).join(',')}}`;
  return JSON.stringify(value);
};
const object = value => value !== null && typeof value === 'object' && !Array.isArray(value);
const exactKeys = (value, keys) => object(value) && Object.keys(value).length === keys.length
  && keys.every(key => Object.hasOwn(value, key));
const positive = value => Number.isSafeInteger(value) && value > 0;
const text = value => typeof value === 'string' && value.length > 0;
const unique = values => new Set(values).size === values.length;
const safePath = value => text(value) && !value.startsWith('/')
  && !value.includes('\\') && !/[\0-\x1f\x7f]/.test(value)
  && value.split('/').every(part => part && part !== '.' && part !== '..');
const boundedId = (value, limit) => text(value) && Buffer.byteLength(value, 'utf8') <= limit;
const hasPrefix = (path, prefix) => path === prefix || path.startsWith(`${prefix}/`);
const safeDetail = value => ({ detail_digest: digest(String(value)) });

function runGit(repo, args, maxBuffer, reason = 'repository_unresolvable') {
  const result = spawnSync('git', ['-C', repo, ...args], { encoding: null, maxBuffer });
  if (result.error || result.status !== 0) fail(reason);
  return result.stdout;
}

function validatePolicy(policy, policyBytes, baseRef) {
  if (!exactKeys(policy, POLICY_KEYS) || policy.schema_version !== VERSION
      || !text(policy.policy_version) || !exactKeys(policy.repository, ['remote', 'base_ref'])
      || !text(policy.repository.remote) || policy.repository.base_ref !== baseRef
      || !exactKeys(policy.limits, LIMIT_KEYS) || !LIMIT_KEYS.every(key => positive(policy.limits[key]))
      || policyBytes > policy.limits.max_policy_bytes || !Array.isArray(policy.commands)
      || !policy.commands.length || policy.commands.length > policy.limits.max_commands
      || !Array.isArray(policy.selectors) || !policy.selectors.length
      || policy.selectors.length > policy.limits.max_selectors
      || !Array.isArray(policy.exhaustive_command_ids) || !policy.exhaustive_command_ids.length
      || !Array.isArray(policy.non_executable_prefixes) || !Array.isArray(policy.broadening_prefixes)
      || !Array.isArray(policy.dependency_inputs) || !Array.isArray(policy.required_environment)
      || !exactKeys(policy.risk_input_policy, ['allowed_boolean_keys', 'exhaustive_when_true'])) {
    fail('policy_malformed');
  }
  const { max_identifier_bytes: idLimit, max_arguments_per_command: argvLimit,
    max_argument_bytes: argBytes } = policy.limits;
  const commandIds = new Set();
  for (const command of policy.commands) {
    if (!exactKeys(command, COMMAND_KEYS) || !boundedId(command.id, idLimit) || commandIds.has(command.id))
      fail(commandIds.has(command?.id) ? 'policy_ambiguous' : 'policy_malformed');
    if (command.enabled !== true) fail(command.enabled === false ? 'command_skipped' : 'policy_malformed');
    if (!Array.isArray(command.argv) || !command.argv.length || command.argv.length > argvLimit
        || !command.argv.every(arg => text(arg) && Buffer.byteLength(arg, 'utf8') <= argBytes)
        || !positive(command.timeout_seconds) || !positive(command.output_limit_bytes)
        || !Array.isArray(command.config_paths) || !command.config_paths.every(safePath)) fail('policy_malformed');
    commandIds.add(command.id);
  }
  if (!unique(policy.exhaustive_command_ids)
      || !policy.exhaustive_command_ids.every(id => commandIds.has(id))) fail('command_unresolved');
  const selectorIds = new Set();
  for (const selector of policy.selectors) {
    if (!exactKeys(selector, SELECTOR_KEYS) || !boundedId(selector.id, idLimit)
        || selectorIds.has(selector.id) || !Array.isArray(selector.path_prefixes)
        || !selector.path_prefixes.length || !selector.path_prefixes.every(safePath)
        || !Array.isArray(selector.command_ids) || !selector.command_ids.length
        || !unique(selector.command_ids) || !selector.command_ids.every(id => commandIds.has(id))) {
      fail(selectorIds.has(selector?.id) ? 'policy_ambiguous' : 'policy_malformed');
    }
    selectorIds.add(selector.id);
  }
  const pathGroups = [policy.non_executable_prefixes, policy.broadening_prefixes, policy.dependency_inputs];
  if (!pathGroups.flat().every(safePath) || !pathGroups.every(unique) || !policy.required_environment.every(name =>
    boundedId(name, idLimit) && /^[A-Z][A-Z0-9_]*$/.test(name))
      || !unique(policy.required_environment)) fail('policy_malformed');
  const allowed = policy.risk_input_policy.allowed_boolean_keys;
  const broad = policy.risk_input_policy.exhaustive_when_true;
  if (!Array.isArray(allowed) || !Array.isArray(broad) || !unique(allowed) || !unique(broad)
      || !allowed.every(key => boundedId(key, idLimit) && /^[a-z][a-z0-9_]*$/.test(key))
      || !broad.every(key => allowed.includes(key))) fail('policy_malformed');
  return commandIds;
}

function normalizeDiff(raw, maxPaths) {
  let decoded;
  try { decoded = new TextDecoder('utf-8', { fatal: true }).decode(raw); }
  catch { fail('diff_malformed'); }
  const tokens = decoded.split('\0');
  if (tokens.at(-1) === '') tokens.pop();
  const entries = [];
  for (let index = 0; index < tokens.length;) {
    const status = tokens[index++];
    if (!/^(A|M|D|T|U|X|B|R[0-9]+)$/.test(status)) fail('diff_malformed');
    if (status.startsWith('R')) entries.push({ status, from: tokens[index++], to: tokens[index++] });
    else entries.push({ status, path: tokens[index++] });
    if (Object.values(entries.at(-1)).some(value => value === undefined)) fail('diff_malformed');
  }
  if (!entries.length) fail('empty_candidate_diff');
  if (entries.length > maxPaths) fail('diff_too_large');
  const paths = [...new Set(entries.flatMap(entry => entry.path ? [entry.path] : [entry.from, entry.to]))].sort();
  if (!paths.every(safePath)) fail('diff_malformed');
  return { entries, paths };
}

export function resolveLocalAdmission({ repo, baseRef, baseSha, headSha, policyPath, riskInputs,
  environment = process.env }) {
  try {
    if (!text(repo) || !text(baseRef) || !/^[0-9a-f]{40}$/.test(baseSha)
        || !/^[0-9a-f]{40}$/.test(headSha) || !safePath(policyPath) || !object(riskInputs))
      fail('input_invalid');
    runGit(repo, ['check-ref-format', `refs/heads/${baseRef}`]);
    const policyRaw = runGit(repo, ['show', `${baseSha}:${policyPath}`], undefined, 'policy_missing');
    let policy;
    try { policy = JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(policyRaw)); }
    catch { fail('policy_malformed'); }
    validatePolicy(policy, policyRaw.length, baseRef);
    if (!boundedId(baseRef, policy.limits.max_identifier_bytes)) fail('policy_malformed');
    const max = policy.limits.max_diff_bytes;
    const actualHead = runGit(repo, ['rev-parse', 'HEAD'], max).toString().trim();
    const actualBase = runGit(repo, ['rev-parse', `refs/remotes/origin/${baseRef}`], max).toString().trim();
    const remote = runGit(repo, ['remote', 'get-url', 'origin'], max).toString().trim();
    if (actualHead !== headSha || actualBase !== baseSha) fail('candidate_stale');
    if (remote !== policy.repository.remote) fail('repository_mismatch');
    if (runGit(repo, ['status', '--porcelain=v1', '--untracked-files=all'], max).length) fail('candidate_unsealed');
    const rawDiff = runGit(repo, ['diff', '--name-status', '-M', '-z', baseSha, headSha], max, 'diff_unresolvable');
    if (rawDiff.length > max) fail('diff_too_large');
    const { entries, paths } = normalizeDiff(rawDiff, policy.limits.max_changed_paths);
    const allowedRisk = policy.risk_input_policy.allowed_boolean_keys;
    const riskKeys = Object.keys(riskInputs);
    if (riskKeys.length !== allowedRisk.length || !riskKeys.every(key => allowedRisk.includes(key))
        || !allowedRisk.every(key => typeof riskInputs[key] === 'boolean')) fail('risk_input_unresolved');
    const broadRisk = policy.risk_input_policy.exhaustive_when_true.some(key => riskInputs[key]);
    const broadPath = paths.some(path => policy.broadening_prefixes.some(prefix => hasPrefix(path, prefix)));
    const broadDependency = paths.some(path => policy.dependency_inputs.includes(path));
    const exhaustive = broadRisk || broadPath || broadDependency;
    const selected = new Set(exhaustive ? policy.exhaustive_command_ids : []);
    const surfaces = new Set(exhaustive ? ['exhaustive'] : []);
    for (const path of paths) {
      let matched = policy.non_executable_prefixes.some(prefix => hasPrefix(path, prefix))
        || policy.broadening_prefixes.some(prefix => hasPrefix(path, prefix))
        || policy.dependency_inputs.includes(path);
      for (const selector of policy.selectors) if (selector.path_prefixes.some(prefix => hasPrefix(path, prefix))) {
        matched = true; surfaces.add(selector.id); selector.command_ids.forEach(id => selected.add(id));
      }
      if (!matched) fail('unknown_executable_surface', safeDetail(path));
    }
    if (!selected.size) fail('empty_executable_selection');
    const gitDigest = path => {
      const entry = runGit(repo, ['ls-tree', '-z', headSha, '--', `:(literal)${path}`], max,
        'configuration_unresolved').toString();
      if (!entry) fail('configuration_unresolved');
      const match = /^(100644|100755) blob ([0-9a-f]{40})\t(.+)\0$/.exec(entry);
      if (!match || match[3] !== path) fail('configuration_unsafe');
      return digest(runGit(repo, ['cat-file', 'blob', match[2]], max, 'configuration_unresolved'));
    };
    const dependencies = policy.dependency_inputs.map(path => [digest(path), gitDigest(path)]);
    const missingFacts = policy.required_environment.filter(name => !Object.hasOwn(environment, name));
    if (missingFacts.length) fail('environment_fact_missing', { fact_digests: missingFacts.map(digest) });
    const facts = policy.required_environment.slice().sort().map(name => [name, digest(environment[name])]);
    const commands = policy.commands.filter(command => selected.has(command.id)).map(command => ({
      id: command.id, argv: command.argv, timeout_seconds: command.timeout_seconds,
      output_limit_bytes: command.output_limit_bytes, descriptor_digest: digest(canonical(command)),
      configuration_digest: digest(canonical(command.config_paths.map(path => [digest(path), gitDigest(path)])))
    }));
    const binding = { repository_digest: digest(remote), base_ref: baseRef, base_sha: baseSha,
      head_sha: headSha, normalized_diff_digest: digest(canonical(entries)),
      dependency_digest: digest(canonical(dependencies)), risk_digest: digest(canonical(riskInputs)),
      policy_version: policy.policy_version, policy_digest: digest(canonical(policy)),
      selector_digest: digest(canonical({ selectors: policy.selectors, exhaustive: policy.exhaustive_command_ids,
        non_executable: policy.non_executable_prefixes, broadening: policy.broadening_prefixes })),
      environment_digest: digest(canonical({ platform: `${process.platform}/${process.arch}`, facts })),
      command_digests: commands.map(({ id, descriptor_digest, configuration_digest }) =>
        ({ id, descriptor_digest, configuration_digest })) };
    const summary = { schema_version: VERSION, outcome: 'resolved', repository_digest: binding.repository_digest,
      base_ref: baseRef, base_sha: baseSha, head_sha: headSha, binding_digest: digest(canonical(binding)),
      changed_path_count: paths.length, rename_count: entries.filter(item => item.status.startsWith('R')).length,
      selected_surface_ids: [...surfaces].sort(), selected_command_ids: commands.map(item => item.id) };
    return { status: 'resolved', binding, binding_digest: summary.binding_digest, selected_commands: commands, summary };
  } catch (error) {
    const reason = error instanceof AdmissionError ? error.reason : 'resolver_error';
    return { status: 'rejected', reason, summary: { schema_version: VERSION, outcome: reason,
      ...(error instanceof AdmissionError ? error.details : {}) } };
  }
}

function parseArgs(argv) {
  const allowed = ['repo', 'base-ref', 'base-sha', 'head-sha', 'policy', 'risk-inputs', 'output'];
  if (argv.length !== allowed.length * 2) fail('input_invalid');
  const options = {};
  for (let index = 0; index < argv.length; index += 2) {
    const key = argv[index]?.slice(2);
    if (!argv[index]?.startsWith('--') || !allowed.includes(key) || Object.hasOwn(options, key)
        || argv[index + 1] === undefined) fail('input_invalid');
    options[key] = argv[index + 1];
  }
  return options;
}

async function main() {
  let args;
  try { args = parseArgs(process.argv.slice(2)); }
  catch { process.stderr.write('{"status":"rejected","reason":"input_invalid"}\n'); process.exitCode = 2; return; }
  let riskInputs;
  try { riskInputs = JSON.parse(await readFile(args['risk-inputs'], 'utf8')); }
  catch { riskInputs = null; }
  const result = resolveLocalAdmission({ repo: args.repo, baseRef: args['base-ref'],
    baseSha: args['base-sha'], headSha: args['head-sha'], policyPath: args.policy, riskInputs });
  if (!args.output) { process.stderr.write('{"status":"rejected","reason":"input_invalid"}\n'); process.exitCode = 2; return; }
  await writeFile(args.output, `${JSON.stringify(result)}\n`, { mode: 0o600, flag: 'wx' });
  process.stdout.write(`${JSON.stringify(result.summary)}\n`);
  if (result.status !== 'resolved') process.exitCode = 3;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) main().catch(() => {
  process.stderr.write('{"status":"rejected","reason":"resolver_error"}\n'); process.exitCode = 2;
});
