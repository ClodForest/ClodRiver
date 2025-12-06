class Decompiler
  @decompile: (source) ->
    result = source

    # Apply transformation repeatedly for nested calls
    loop
      prev = result

      # Transform _dispatch(obj, 'method', args) back to obj.method(args)
      # Pattern: _dispatch(obj, 'method') or _dispatch(obj, 'method', args)
      # Use non-greedy matching for args to handle nesting
      result = result.replace /_dispatch\(([^,]+),\s*['"](\w+)['"]\s*(?:,\s*([^)]*))?\)/g,
        (match, obj, method, args) ->
          obj = obj.trim()
          if args?.trim()
            "#{obj}.#{method}(#{args.trim()})"
          else
            "#{obj}.#{method}()"

      # Special case: @.method(args) -> @method(args) (cleaner form)
      result = result.replace /\@\.(\w+)\(/g, '@$1('

      break if result is prev  # No more changes

    result

module.exports = Decompiler
