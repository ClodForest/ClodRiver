#!/usr/bin/env coffee

path   = require 'path'
Server = require '../lib/server'

rootDir  = path.resolve __dirname, '..'
corePath = path.join rootDir, 'db', 'minimal', 'core.clod'

server = new Server()

try
  server.loadCore corePath
  server.start 7777, 'localhost'
catch error
  console.error "Failed to start:", error
  process.exit 1

process.on 'SIGTERM', ->
  console.log "Shutting down..."
  server.stop()
  process.exit 0

process.on 'SIGINT', ->
  console.log "Shutting down..."
  server.stop()
  process.exit 0
