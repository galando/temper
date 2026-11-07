// The run driver's calls as argument lists (core/argv.ts, 9.8.1): the mod runs only the plugin's own CLI, by its path,
// with the words of the call the CLI wrote, and never through a shell.
import { describe, expect, test } from 'claude-code/testing'

import { cliArgv, splitCall } from '../../hooks/temper-mod/core/argv'

const CLI = '/plug/scripts/temper'

describe('the words of a call', () => {
  test('plain words, single quotes and the quote inside a value', () => {
    expect(splitCall(`${CLI} state init refunds --feature 'Add refunds'`)).toEqual([CLI, 'state', 'init', 'refunds', '--feature', 'Add refunds'])
    expect(splitCall(`${CLI} intent answer 'it'\\''s' 'a "b"'`)).toEqual([CLI, 'intent', 'answer', "it's", 'a "b"'])
    // Python's shlex.quote writes a quote inside a value as '"'"'.
    expect(splitCall(`${CLI} park --reason 'the person'"'"'s call'`)).toEqual([CLI, 'park', '--reason', "the person's call"])
    expect(splitCall(`${CLI} x ''`)).toEqual([CLI, 'x', ''])
  })

  test('a line that needs a shell is not read', () => {
    for (const c of [`${CLI} go; rm -rf x`, `${CLI} go | tee x`, `${CLI} go > x`, `${CLI} go && echo`, `${CLI} $(id)`, `${CLI} \`id\``, `${CLI} "$HOME"`, `${CLI} 'open`, `${CLI} go\nid`, `${CLI} go &`])
      expect(splitCall(c)).toBeNull()
  })

  test('shell characters inside quotes are plain text', () => {
    expect(splitCall(`${CLI} evidence add --reason 'a | b; c > d $e'`)).toEqual([CLI, 'evidence', 'add', '--reason', 'a | b; c > d $e'])
  })
})

describe('only the Temper CLI is run', () => {
  test('the plugin CLI, by its path or as the CLI resolved it', () => {
    expect(cliArgv(`${CLI} go`, CLI)).toEqual([CLI, 'go'])
    expect(cliArgv('/real/plug/scripts/temper gate plan', CLI)).toEqual(['/real/plug/scripts/temper', 'gate', 'plan'])
  })

  test('any other program, the setup lines of old and a shell are not', () => {
    expect(cliArgv('bash -c id', CLI)).toBeNull()
    expect(cliArgv(`bash /plug/scripts/guards/install.sh`, CLI)).toBeNull()
    expect(cliArgv('mkdir -p .claude && cp /plug/templates/temper.config.default .claude/temper.config', CLI)).toBeNull()
    expect(cliArgv('/plug/scripts/temperx go', CLI)).toBeNull()
    expect(cliArgv('', CLI)).toBeNull()
  })
})
