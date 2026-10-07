import assert from 'node:assert/strict';
import { mkdtempSync, symlinkSync, rmSync, readdirSync, readFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { resolve, join } from 'node:path';
import { pathToFileURL } from 'node:url';
import test from 'node:test';

// Exercise the pinned package's consumer, not a home-grown frontmatter parser.
const packageDir = process.env.PI_SUBAGENTS_PACKAGE;
if (!packageDir) throw new Error('Set PI_SUBAGENTS_PACKAGE to the installed pi-subagents@0.76.0 directory');
const { discoverAgents } = await import(pathToFileURL(resolve(packageDir, 'src/agents/agents.js')));
const root = resolve(import.meta.dirname, '..');

test('Pi discovers every specialist with context and no hardcoded model', () => {
  const home = mkdtempSync(join(tmpdir(), 'pi-agent-catalog-'));
  const previous = process.env.PI_CODING_AGENT_DIR;
  try {
    symlinkSync(join(root, 'pi/agents'), join(home, 'agents'));
    process.env.PI_CODING_AGENT_DIR = home;
    const { agents, agentDiagnostics } = discoverAgents(home, 'user');
    assert.equal(agentDiagnostics?.length ?? 0, 0);
    const names = [...readdirSync(join(root, 'opencode/agents')).filter(f => f.endsWith('.md')).map(f => f.slice(0, -3)), 'worker', 'scout', 'reviewer', 'oracle', 'text'];
    for (const name of names) {
      const agent = agents.find(a => a.name === name && a.source === 'user');
      assert.ok(agent, `missing ${name}`);
      assert.equal(agent.model, undefined, `${name}: parent chooses model`);
      assert.equal(agent.inheritProjectContext, true, name);
      assert.equal(agent.inheritGlobalContext, true, name);
      assert.equal(agent.inheritSkills, true, name);
      assert.equal(agent.systemPromptMode, 'append', name);
      if (!['worker', 'project-memory-manager', 'skills-architect', 'tdd-micronaut-v2'].includes(name)) {
        assert.ok(!agent.tools?.includes('edit') && !agent.tools?.includes('write'), `${name}: no editor tools`);
      }
      if (name === 'text') assert.deepEqual(agent.tools, []);
      const originalPath = join(root, 'opencode/agents', `${name}.md`);
      if (names.indexOf(name) < names.length - 5) {
        const originalBody = readFileSync(originalPath, 'utf8').split('\n---\n').slice(1).join('\n---\n').trim();
        assert.ok(agent.systemPrompt.includes(originalBody), `${name}: preserve specialist body`);
      }
    }
  } finally {
    if (previous === undefined) delete process.env.PI_CODING_AGENT_DIR;
    else process.env.PI_CODING_AGENT_DIR = previous;
    rmSync(home, { recursive: true, force: true });
  }
});
