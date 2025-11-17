module.exports = (CoreAPI) ->
  class $llm_client extends root
    receiveAPI: (ctx, @api) ->

    complete_chat: (ctx, prompt) ->
      response = await @api.llm_responses_create, prompt

  CoreAPI.register $llm_client

  class $llm extends $root
    @clientClass: $llm_client

    @DEFAULT_CONFIG:
      baseURL: 'http://localhost:11434/v1'
      apiName: 'openai'
      apiVersion: '1'
      apiKey: process.ENV.OPENAI_API_KEY
      model: 'hf.co/bartowski/TheDrummer_Cydonia-24B-v4.2.0-GGUF:Q6_K_L'

    constructor: ->
      super arguments...

      @set config: $llm.DEFAULT_CONFIG
        
    set_config: (ctx, config) ->
      # XXX: Is there a shorthand for this way of limiting object copying to a
      # subset?
      newConfig = {}
      for key in Object.getOwnPropertyNames $llm.DEFAULT_CONFIG
        newConfig[key] = config[key]

      @set config: @get('config'), newConfig

    spawn_client: (ctx) ->
      { apiKey, baseURL } = @get 'config'

      newClient = @call ($llm.clientClass), 'spawn'
      @call $sys, 'llm_new_client', newClient, { apiKey, baseURL }

      return newClient

