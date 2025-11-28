fs           = require 'node:fs'
CoffeeScript = require 'coffeescript'

Core         = require './core'
Compiler     = require './compiler'

class Server
  constructor: ->
    @core     = new Core()
    @compiler = new Compiler @core
    @server   = null

  loadCore: (corePath) ->
    source = fs.readFileSync corePath, 'utf8'

    @compiler.compile source
    operations = @compiler.getOperations()

    objRefs = {}

    for op in operations
      try
        switch op.type
          when 'create_object'
            parent = if op.parent? then objRefs[op.parent] else null
            obj = @core.create parent, op.name
            objRefs[op.id] = obj
            @core.objectIDs[op.id] = obj

          when 'add_method'
            obj = objRefs[op.objectId]
            unless obj?
              throw new Error "Object #{op.objectId} not found"

            flags = if op.disallowOverrides then {disallowOverrides: true} else {}
            @core.addMethod obj, op.methodName, op.fn, op.source, flags

          when 'set_data'
            obj = objRefs[op.objectId]
            unless obj?
              throw new Error "Object #{op.objectId} not found"

            # Create a minimal execution context for data block
            ExecutionContext = require './execution-context'
            dummyMethod = {definer: obj, name: '_data_loader'}
            ctx = new ExecutionContext @core, obj, dummyMethod

            # Execute data function with ctx
            stateData = op.fn ctx

            # Apply state data to object, remapping namespace IDs
            for oldNamespaceId, data of stateData
              # Map old object ID to new object ID
              newObj = objRefs[parseInt(oldNamespaceId)]
              if newObj?
                newNamespaceId = newObj._id
                obj._state[newNamespaceId] = data
              else
                # No mapping found, use original ID (shouldn't happen in valid dumps)
                obj._state[oldNamespaceId] = data

          else
            throw new Error "Unknown operation type: #{op.type}"

      catch error
        console.error "\nError at line #{op.lineNum} in #{corePath}:"
        console.error "  Operation: #{op.type}"
        if op.type is 'create_object'
          console.error "  Object: ##{op.id} (#{op.name or 'unnamed'})"
        else if op.type is 'add_method'
          console.error "  Method: ##{op.objectId}.#{op.methodName}"
        else if op.type is 'set_data'
          console.error "  Data: ##{op.objectId}"
        console.error "  Error: #{error.message}"
        console.error ""
        throw error

    @core

  start: (port = 7777, addr = '127.0.0.1') ->
    # Call $sys.startup which will use listen BIF to create the TCP server
    $sys = @core.toobj '$sys'
    @core.call $sys, 'startup', [port, addr]
    console.log "ClodRiver started via $sys.startup on #{addr}:#{port}"

  stop: ->
    # TODO: implement graceful shutdown via $sys.shutdown
    console.log "Server stop requested"

module.exports = Server
