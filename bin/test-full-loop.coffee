#!/usr/bin/env coffee

fs       = require 'node:fs'
Core     = require '../lib/core'
TextDump = require '../lib/text-dump'

LLM_CONFIG =
  baseURL: 'http://localhost:11435/v1'
  model:   'hf.co/bartowski/TheDrummer_Precog-24B-v1-GGUF:Q6_K_L'

core = new Core()

$sys  = core.toobj '$sys'
$root = core.toobj '$root'

core.addMethod $root, 'spawn', (create) ->
  (ctx, args) ->
    newObj = create @
    newObj.init?()
    newObj

core.addMethod $root, 'init', ->
  (ctx, args) ->

loadModule = (path) ->
  source = fs.readFileSync path, 'utf8'
  dump   = TextDump.fromString source, path
  dump.apply core

loadModule 'clod/core/facts/index.clod'
loadModule 'clod/core/intent/index.clod'
loadModule 'clod/core/action/index.clod'
loadModule 'clod/core/render/index.clod'

$facts_proto    = core.toobj '$facts'
$parser_proto   = core.toobj '$intent_parser'
$action_proto   = core.toobj '$action_interpreter'
$renderer_proto = core.toobj '$renderer'

facts    = core.call $facts_proto, 'spawn'
parser   = core.call $parser_proto, 'spawn'
action   = core.call $action_proto, 'spawn'
renderer = core.call $renderer_proto, 'spawn'

core.addMethod $sys, 'setup', (connect_llm, send) ->
  (ctx, args) ->
    connect_llm parser, LLM_CONFIG
    connect_llm action, LLM_CONFIG
    connect_llm renderer, LLM_CONFIG

    send parser, 'configure', {
      available_verbs: ['take', 'drop', 'look', 'go', 'open', 'close', 'attack', 'give', 'put', 'examine']
    }

    send action, 'configure', {
      facts: facts
    }

    send renderer, 'configure', {
      facts: facts
      style: 'classic'
    }

core.call $sys, 'setup'

console.log "=== ClodMUD Full Loop Test ===\n"

core.call facts, 'assert', ['$room', 'type', 'location']
core.call facts, 'assert', ['$room', 'name', 'Dusty Cellar']
core.call facts, 'assert', ['$room', 'description', 'A damp stone cellar with cobwebs in the corners.']

core.call facts, 'assert', ['$sword', 'type', 'weapon']
core.call facts, 'assert', ['$sword', 'name', 'rusty sword']
core.call facts, 'assert', ['$sword', 'portable', 'true']
core.call facts, 'assert', ['$sword', 'location', '$room']

core.call facts, 'assert', ['$player', 'type', 'person']
core.call facts, 'assert', ['$player', 'name', 'adventurer']
core.call facts, 'assert', ['$player', 'location', '$room']

core.call facts, 'assert', ['$piano', 'type', 'furniture']
core.call facts, 'assert', ['$piano', 'name', 'grand piano']
core.call facts, 'assert', ['$piano', 'portable', 'false']
core.call facts, 'assert', ['$piano', 'weight', '500kg']
core.call facts, 'assert', ['$piano', 'location', '$room']

core.call facts, 'assert', ['$rat', 'type', 'creature']
core.call facts, 'assert', ['$rat', 'name', 'mangy rat']
core.call facts, 'assert', ['$rat', 'hostile', 'true']
core.call facts, 'assert', ['$rat', 'location', '$room']

console.log "World initialized with #{core.call facts, 'count'} facts\n"

printNarrative = (narrative) ->
  console.log "\n╔══════════════════════════════════════════════════════════════╗"
  console.log "║                         NARRATIVE                            ║"
  console.log "╚══════════════════════════════════════════════════════════════╝"
  console.log ""
  console.log narrative.text
  console.log ""
  if narrative.error?
    console.log "(Renderer error: #{narrative.error})"
  console.log "─".repeat 64
  console.log ""

narrativeHandler = core.create $root
core.addMethod narrativeHandler, 'receive_narrative', ->
  (ctx, args) ->
    [narrative] = args
    printNarrative narrative

resultHandler = core.create $root
core.addMethod resultHandler, 'action_completed', (send) ->
  (ctx, args) ->
    [result] = args
    console.log "\n[Action: #{if result.success then 'SUCCESS' else 'FAILED'}]"
    if result.operations?.length > 0
      for op in result.operations
        if op.op is 'fail'
          console.log "  → #{op.reason}"
        else
          console.log "  → #{op.op}(#{op.s}, #{op.p}, #{op.o})"

    send renderer, 'render', result, result.subject

core.call renderer, 'configure', [{narrative_handler: narrativeHandler}]
core.call action, 'configure', [{result_handler: resultHandler}]

intentHandler = core.create $root
core.addMethod intentHandler, 'receive_intent', (send) ->
  (ctx, args) ->
    [intent, subject] = args
    console.log "[Intent: #{intent.verb ? intent.type}]"
    send action, 'execute', intent, subject

core.call parser, 'configure', [{intent_handler: intentHandler}]

input   = process.argv[2] ? 'take the sword'
subject = '$player'

console.log "┌────────────────────────────────────────────────────────────────┐"
console.log "│ Player input: \"#{input}\"#{' '.repeat Math.max(0, 46 - input.length)}│"
console.log "└────────────────────────────────────────────────────────────────┘"
console.log ""
console.log "Processing...\n"

core.call parser, 'parse', [input, subject]

setTimeout (-> process.exit 0), 120000
