fs       = require 'node:fs'
path     = require 'node:path'
yaml     = require 'js-yaml'
Core     = require './core'
TextDump = require './text-dump'

class MudGame
  constructor: (options = {}) ->
    @core = new Core()
    @llmConfig = options.llmConfig ? {
      baseURL: process.env.LLM_URL   ? 'http://localhost:11434/v1'
      model:   process.env.LLM_MODEL ? 'hf.co/bartowski/TheDrummer_Precog-24B-v1-GGUF:Q6_K_L'
    }

    @transcript = []
    @maxTranscript = options.maxTranscript ? 10
    @pendingInput = null
    @waiting = false

    @onNarrative = options.onNarrative ? (text) ->
    @onError     = options.onError     ? (error) ->
    @onReady     = options.onReady     ? ->

    @_setupLogging options.logFile
    @_setupCore()

  _setupLogging: (logFile) ->
    if logFile
      @logFile = logFile
      timestamp = new Date().toISOString()
      @_log {type: 'session_start', timestamp, llmConfig: @llmConfig}
    else
      @logFile = null

  _log: (entry) ->
    return unless @logFile?
    entry.timestamp ?= new Date().toISOString()
    yamlDoc = yaml.dump entry, {lineWidth: 120, noRefs: true}
    fs.appendFileSync @logFile, "---\n#{yamlDoc}"

  _setupCore: ->
    $sys  = @core.toobj '$sys'
    $root = @core.toobj '$root'

    @core.addMethod $root, 'spawn', (create) ->
      (ctx, args) ->
        newObj = create @
        newObj.init?()
        newObj

    @core.addMethod $root, 'init', ->
      (ctx, args) ->

    @_loadModules()
    @_createInstances()
    @_configureHandlers()

  _loadModules: ->
    loadModule = (modulePath) =>
      source = fs.readFileSync modulePath, 'utf8'
      dump   = TextDump.fromString source, modulePath
      dump.apply @core

    loadModule 'clod/core/facts/index.clod'
    loadModule 'clod/core/intent/index.clod'
    loadModule 'clod/core/action/index.clod'
    loadModule 'clod/core/render/index.clod'
    loadModule 'clod/core/d20/index.clod'

  _createInstances: ->
    $sys = @core.toobj '$sys'

    @$facts_proto    = @core.toobj '$facts'
    @$parser_proto   = @core.toobj '$intent_parser'
    @$action_proto   = @core.toobj '$action_interpreter'
    @$renderer_proto = @core.toobj '$renderer'
    @$d20_proto      = @core.toobj '$d20'
    @$dice           = @core.toobj '$dice'

    @facts    = @core.call @$facts_proto, 'spawn'
    @parser   = @core.call @$parser_proto, 'spawn'
    @action   = @core.call @$action_proto, 'spawn'
    @renderer = @core.call @$renderer_proto, 'spawn'
    @d20      = @core.call @$d20_proto, 'spawn'

    @core.addMethod $sys, 'setup', (connect_llm, send) =>
      (ctx, args) =>
        connect_llm @parser, @llmConfig
        connect_llm @action, @llmConfig
        connect_llm @renderer, @llmConfig

        send @action, 'configure', {facts: @facts, d20: @d20}
        send @renderer, 'configure', {facts: @facts, style: 'classic'}
        send @d20, 'configure', {facts: @facts}

    @core.call $sys, 'setup'

  _configureHandlers: ->
    $root = @core.toobj '$root'

    @narrativeHandler = @core.create $root
    @core.addMethod @narrativeHandler, 'receive_narrative', =>
      (ctx, args) =>
        [narrative] = args
        if narrative.error?
          @_log {type: 'error', error: narrative.error, input: @pendingInput}
          @onError narrative.error
          @_addToTranscript @pendingInput, "[Error: #{narrative.error}]" if @pendingInput?
        else
          text = @_stripThinkTags narrative.text
          @_log {
            type: 'narrative'
            input: @pendingInput
            text: text
            new_facts: narrative.new_facts ? []
          }
          @onNarrative text
          @_addToTranscript @pendingInput, text if @pendingInput?
        @pendingInput = null
        @waiting = false
        @onReady()

    @resultHandler = @core.create $root
    @core.addMethod @resultHandler, 'action_completed', (send) =>
      (ctx, args) =>
        [result, gameContext] = args
        gameContext ?= {}
        @_log {type: 'action', result}

        if not result.success and result.error?
          if result.error.includes('parse error')
            @onError "Action parsing failed: #{result.error}"
            @_addToTranscript @pendingInput, "[Parse error]" if @pendingInput?
            @pendingInput = null
            @waiting = false
            @onReady()
            return

        send @renderer, 'render', result, result.subject, gameContext

    @core.call @renderer, 'configure', [{narrative_handler: @narrativeHandler}]
    @core.call @action, 'configure', [{result_handler: @resultHandler}]

    @intentHandler = @core.create $root
    @core.addMethod @intentHandler, 'receive_intent', (send) =>
      (ctx, args) =>
        [intent, subject, context] = args
        context ?= {}

        @_log {type: 'intent', input: @pendingInput, intent}

        if intent.type is 'unknown'
          reason = intent.reason ? ''
          if reason.includes('ECONNREFUSED') or reason.includes('fetch') or reason.includes('LLM error')
            @onError 'system_down'
            @_addToTranscript @pendingInput, "[System unavailable]" if @pendingInput?
          else
            @onError 'not_understood'
            @_addToTranscript @pendingInput, "[Not understood]" if @pendingInput?
          @pendingInput = null
          @waiting = false
          @onReady()
          return

        send @action, 'execute', intent, subject, context

    @core.call @parser, 'configure', [{intent_handler: @intentHandler}]

  loadWorld: (worldPath) ->
    absolutePath = path.resolve worldPath
    require(absolutePath)(@facts, @core)
    @_log {type: 'world_loaded', worldPath: absolutePath}

  processInput: (input) ->
    return if @waiting
    @waiting = true
    @pendingInput = input
    @_log {type: 'input', input}
    @core.call @parser, 'parse', [input, '$player', {transcript: @transcript}]

  isWaiting: -> @waiting

  getPlayerLocation: ->
    @core.call @facts, 'get', ['$player', 'location']

  getFact: (subject, predicate) ->
    @core.call @facts, 'get', [subject, predicate]

  getFactsAbout: (entity) ->
    @core.call @facts, 'about', [entity]

  getEntitiesAt: (location) ->
    @core.call @facts, 'subjects_where', ['location', location]

  _addToTranscript: (input, output) ->
    @transcript.push {input, output}
    @transcript.shift() while @transcript.length > @maxTranscript

  _stripThinkTags: (text) ->
    text?.replace(/<think>[\s\S]*?<\/think>\s*/g, '').trim()

module.exports = MudGame
