# strongly is a more-strongly typed class system.  You defined class schemas
# such that they are accessible from ../schema_manager.  When you create a
# strongly class, it automatically sets defaults specified in the yaml.  It
# also then builds a bunch of getter and setter methods that internally use
# qset and qget, which internally use get and set.  Strongly also does auto
# normalization and denormalization.  So if you set foo.bar = baz, and bar
# is specified in the schema as a ConfigItemId, then the id of that baz will
# actually be stored in foo.bar.  This is really nice, because you can be
# setting them like you would expect, but when they are persisted and restored
# from backbone, they get wired up correctly.
# strongly is a mixin, setup by doing
#     strongly this
# within a class definition
_ = require 'underscore'
util = require 'util'

{isEmbeddedType, getAttributeSchema} = require '../schema_manager'

klasses = {}

# schema will be a dictionary representing the schema for a specific feature
# on a specific model.  This method returns true or false if value meets that
# schema.  (E.g., if schema.type is 'bool', we assert that value is indeed a
# bool.)
isValidAttrValue = (value, schema) ->
  if schema.allowUndefined and not value?
    return true
  if schema.type is 'bool'
    _.isBoolean value
  else if schema.type in ['int', 'float']
    _.isNumber value
  else if schema.type is 'string'
    _.isString value
  else if schema.type is 'object'
    _.isObject value
  # If it's an array, we need to recursively go over the elements of the array
  else if schema.type is 'array'
    (_.isArray value) and _.all value, (v) -> isValidAttrValue(v, type:schema.arrayValueType)
  else if schema.type is 'enum'
    value in schema.enumValues
  # These are allowed to be undefined, a ConfigItemType, or a string that is
  # probably a mongo id
  else if schema.type is 'ConfigItemId'
    ret = not value? or value instanceof klasses.ConfigItemType or value.match /[\w\d]{24}/
    ret
  else if schema.type is 'anything'
    true
  # These have special constructors and will die anyway if bad,
  # so we'll let them through here
  else if isEmbeddedType schema.type
    true
  else
    throw new Error "Unknown type #{schema.type}, getting type from #{schema}"

# This is called when setting a value, and "normalizes" it.  Takes the
# original value, and returns what should actually be stored on the object.
normalize = (njs, value, schema) ->
  attrType = schema.type
  # If we allow undefined and it is such, just return undefined
  if schema.allowUndefined and not value?
    return undefined
  # Recurse over arrays
  if attrType is 'array'
    value = (normalize(njs, v, type:schema.arrayValueType) for v in value)
  # If it's a config item and we have a pointer to it, grab the id and store
  # that instead
  else if schema.type is 'ConfigItemId'
    if value instanceof klasses.ConfigItemType
      value = value.qid
  else if isEmbeddedType schema.type
    embeddedKlass = klasses[schema.type]
    # If it's already the right embedded class, do nothing
    if value instanceof embeddedKlass
      # instanceof does not negate in any normal way!
      null
    else
      # Turn it into the right kind of embedded type
      value = njs.newEmbeddedType schema.type, value
  # Make sure its an int
  else if attrType is 'int'
    value = parseInt value, 10
  value

# This takes a constructor function, and adds the appropriate getters and
# setters based on the schema.  All of getters and setters are just thin
# wrappers around qget and qset
buildGettersAndSetters = (func) ->
  for attrName of func.attributeSchema
    # We skip building them for id and url so they don't overwrite those
    # necessary functions
    continue if attrName in ['id', 'url']
    buildGetter = (name) ->
      ->
        @qget name
    buildSetter = (name) ->
      (value) -> @qset name, value
    Object.defineProperty func.prototype, attrName,
      get: buildGetter attrName
      set: buildSetter attrName

# This is a simple getter method.  It uses @get to get the actual value, and
# then if it's a ConfigItemId or a list of ConfigItemIds, looks up and returns
# the actual config item instead of its stored id.
qget = (attr) ->
  attrSchema = @constructor.attributeSchema[attr]
  value = @get attr
  if attrSchema.type is 'ConfigItemId'
    value = @njs.getByQid value
  else if attrSchema.type is 'array' and attrSchema.arrayValueType is 'ConfigItemId'
    value = (@njs.getByQid v for v in value)
  value

# qset is a pretty beefy setter method.  It has the same signature as
# backbone's set.  This uses the isValidAttrValue and normalize methods above
# to possibly change what is being set on the model and throw an error if its
# not a valid object.
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

# checkRequireds loops through all the attributes.  If they're required and
# not present, this adds an error to them
checkRequireds = ->
  for attrName, attrInfo of @constructor.attributeSchema
    if attrInfo.required
      err = ''
      if not @[attrName] or _.isEmpty @[attrName]
        # hack(nnichols): I don't know a better way to get just the base class
        # to not require a parent
        if attrName isnt 'parent' or @name isnt 'BaseModel'
          err = "#{@} is missing required attribute #{attrName}"
      else if (isEmbeddedType attrInfo.type) and @[attrName]?.broken
        err = "Required embedded attribute #{attrName} on #{@} is broken"
      (@addError 'updateError', err) if err

# strongly is the one exposed method.
strongly = (klass) ->
  klasses[klass.name] = klass
  klass.prototype.qset = qset
  klass.prototype.qget = qget
  klass.prototype.checkRequireds = checkRequireds
  buildGettersAndSetters klass

exports.strongly = strongly