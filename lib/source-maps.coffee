sourceMapSupport = require 'source-map-support'

class SourceMaps
  constructor: ->
    @maps = {}
    @installed = false

  install: ->
    return if @installed
    @installed = true

    sourceMapSupport.install {
      retrieveSourceMap: (source) =>
        if @maps[source]?
          { url: source, map: @maps[source] }
        else
          null
    }

  register: (filename, sourceMap) ->
    @maps[filename] = sourceMap

  unregister: (filename) ->
    delete @maps[filename]

module.exports = new SourceMaps()
