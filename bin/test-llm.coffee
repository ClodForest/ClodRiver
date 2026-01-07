#!/usr/bin/env coffee

fs       = require 'node:fs'
Core     = require '../lib/core'
TextDump = require '../lib/text-dump'

source = fs.readFileSync 'clod/experimental/llm-test/index.clod', 'utf8'
dump   = TextDump.fromString source, 'llm-test.clod'
core   = new Core()
dump.apply core

$sys = core.toobj '$sys'

arg = process.argv[2] ? 'Hello! What is 2+2?'

if process.argv.includes '--stream'
  console.log 'Testing streaming LLM...'
  core.call $sys, 'test_llm_stream', [arg]
else
  console.log 'Testing LLM...'
  core.call $sys, 'test_llm', [arg]

setTimeout (-> process.exit 0), 30000
