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

$facts_proto  = core.toobj '$facts'
$parser_proto = core.toobj '$intent_parser'
$action_proto = core.toobj '$action_interpreter'

facts  = core.call $facts_proto, 'spawn'
parser = core.call $parser_proto, 'spawn'
action = core.call $action_proto, 'spawn'

core.addMethod $sys, 'setup', (connect_llm, send) ->
  (ctx, args) ->
    connect_llm parser, LLM_CONFIG
    connect_llm action, LLM_CONFIG

    send parser, 'configure', {
      available_verbs: ['take', 'drop', 'look', 'go', 'open', 'close', 'attack', 'give', 'put', 'examine']
    }

    send action, 'configure', {
      facts: facts
    }

core.call $sys, 'setup'

console.log "=== Setting up world ==="
core.call facts, 'assert', ['$room', 'type', 'location']
core.call facts, 'assert', ['$room', 'name', 'a dusty cellar']
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

console.log "World initialized with #{core.call facts, 'count'} facts"
console.log ""

resultHandler = core.create $root
core.addMethod resultHandler, 'action_completed', ->
  (ctx, args) ->
    [result] = args
    console.log "\n=== Action Result ==="
    console.log "Success: #{result.success}"
    console.log "Description: #{result.description}"
    if result.operations?.length > 0
      console.log "Operations:"
      for op in result.operations
        console.log "  #{JSON.stringify op}"
    if result.error?
      console.log "Error: #{result.error}"
    console.log ""
    console.log "=== World state after ==="
    console.log core.call facts, 'dump'

core.call action, 'configure', [{result_handler: resultHandler}]

intentHandler = core.create $root
core.addMethod intentHandler, 'receive_intent', (send) ->
  (ctx, args) ->
    [intent, subject] = args
    console.log "\n=== Parsed Intent ==="
    console.log JSON.stringify intent, null, 2
    console.log "\nExecuting via LLM..."
    send action, 'execute', intent, subject

core.call parser, 'configure', [{intent_handler: intentHandler}]

core.call action, 'set_debug', [false]

input   = process.argv[2] ? 'take the sword'
subject = '$player'

console.log "Input: \"#{input}\""
console.log "Parsing..."

core.call parser, 'parse', [input, subject]

setTimeout (-> process.exit 0), 60000
