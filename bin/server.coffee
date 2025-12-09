#!/usr/bin/env coffee

path   = require 'path'
Server = require '../lib/server'

rootDir = path.resolve __dirname, '..'

clodFiles = process.argv[2..]

if clodFiles.length is 0
  clodFiles = [path.join rootDir, 'db', 'minimal', 'core.clod']
else
  clodFiles = clodFiles.map (f) ->
    if path.isAbsolute f then f else path.resolve rootDir, f

server = new Server()

try
  for clodFile in clodFiles
    server.loadCore clodFile
  server.start 7777, '127.0.0.1'
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
