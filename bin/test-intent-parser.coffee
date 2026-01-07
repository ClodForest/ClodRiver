#!/usr/bin/env coffee

fs       = require 'node:fs'
Core     = require '../lib/core'
TextDump = require '../lib/text-dump'

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

intentSource = fs.readFileSync 'clod/core/intent/index.clod', 'utf8'
intentDump   = TextDump.fromString intentSource, 'intent.clod'
intentDump.apply core

$intent = core.toobj '$intent'
$parser = core.toobj '$intent_parser'

core.addMethod $sys, 'setup_parser', (connect_llm, send, create) ->
  (ctx, args) ->
    parser = create $parser

    connect_llm parser, {
      baseURL: 'http://localhost:11434/v1'
      model:   'gpt-oss:latest'
    }

    send parser, 'configure', {
      available_verbs: ['take', 'drop', 'look', 'go', 'open', 'close', 'attack', 'give', 'say', 'examine']
    }

    parser

testHandler = core.create $root
core.addMethod testHandler, 'receive_intent', ->
  (ctx, args) ->
    [intent, subject] = args
    console.log "Received intent for #{subject}:"
    console.log JSON.stringify intent, null, 2

parser = core.call $sys, 'setup_parser'
core.call parser, 'configure', [{intent_handler: testHandler}]

input   = process.argv[2] ? 'take the sword'
subject = process.argv[3] ? '$player'

console.log "Input: \"#{input}\""
console.log "Subject: #{subject}"
console.log "Parsing..."
console.log ""

core.call parser, 'parse', [input, subject]

setTimeout (-> process.exit 0), 30000
