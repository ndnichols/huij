# strongly.coffee
plainTypes = ['string', 'float', 'bool', 'int']

qget = (attr) ->
  attrSchema = @constructor.prototype.attrSchema[attr]
  value = @get attr
  if attrSchema.type in plainTypes
    if attrSchema.type is 'string'
      value = String value
    else if attrSchema.type is 'float'
      value = parseFloat value
    else if attrSchema.type is 'bool'
      value = Boolean value
    else if attrSchema.type is 'int'
      value = parseInt value
  value

qset = (key, value, options={}) ->
  # qset can be called like `qset('bar', baz)` or `qset({'bar':baz})`, so
  # first we adjust our arguments until attrs is dictionary of objects to set
  if _.isObject(key)
    attrs = key
    options = value || {}
  else
    attrs = {}
    attrs[key] = value

  shouldTrigger = false

  for key, value of attrs
    # Get the schema
    attrSchema = @constructor.attributeSchema[key]
    throw new Error "No schema for #{key} in #{util.inspect @constructor.attributeSchema}" if not attrSchema?
    if isValidAttrValue value, attrSchema
      value = normalize @njs, value, attrSchema
      options.changes = {}
      @set key, value, options
      # We also hand-maintain a set of changed attributes to pequod can be
      # smart about what to recompile.
      # if key is 'name' and value in ['ParentAngle', 'NIF']
      if @_changedAttributeKeys? and key isnt '_changedAttributeKeys' and not _.isEmpty options.changes
        _changedAttributeKeys = @_changedAttributeKeys
        _changedAttributeKeys.push key
        @set({'_changedAttributeKeys': _.uniq _changedAttributeKeys}, silent:true)
        shouldTrigger = true
    else
      throw new Error "Setting #{key} to #{util.inspect value} does not meet schema #{util.inspect attrSchema}"
    shouldTrigger = false if options.qsilent
    if shouldTrigger then @trigger? "qchange"

buildOne = (klass, attrName, schema) ->
  klass.prototype.attrSchema[attrName] = schema
  buildGetter = (name) ->
    ->
      @qget name
  buildSetter = (name) ->
    (value) -> @qset name, value
  Object.defineProperty klass.prototype, attrName,
    get: buildGetter attrName
    set: buildSetter attrName

exports.attr = (klass, attrName, schema) ->
  if not klass.prototype.qget?
    klass.prototype.qget = qget
    klass.prototype.qset = qset
    klass.prototype.attrSchema = {}
  buildOne arguments...
