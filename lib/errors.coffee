class MethodNotFoundError extends Error
  constructor: (objId, methodName) ->
    super "Method '#{methodName}' not found on object ##{objId}"
    @name = 'MethodNotFoundError'
    @objId = objId
    @methodName = methodName

class InvalidMethodError extends Error
  constructor: (message) ->
    super message
    @name = 'InvalidMethodError'

class InvalidObjectError extends Error
  constructor: (message) ->
    super message
    @name = 'InvalidObjectError'

class NoParentMethodError extends Error
  constructor: (objId, methodName) ->
    super "No parent implementation of '#{methodName}' for object ##{objId}"
    @name = 'NoParentMethodError'
    @objId = objId
    @methodName = methodName

module.exports = {
  MethodNotFoundError
  InvalidMethodError
  InvalidObjectError
  NoParentMethodError
}
