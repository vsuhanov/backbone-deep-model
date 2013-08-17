define ['underscore', 'chaplin'], (_, Chaplin) ->
  objToPaths = (obj) ->
    ret = {}
    separator = DeepModel.keyPathSeparator

    for key, val of obj
      if val and val.constructor == Object and not _.isEmpty val
        obj2 = objToPaths(val)
        for key2, val2 of obj2
          ret[key + separator + key2] = val2
      else
        ret[key] = val;
    ret


  getNested = (obj, path, return_exists) ->
    separator = DeepModel.keyPathSeparator

    fields = path.split(separator)
    result = obj
    return_exists || (return_exists == false)
    n = fields.length
    for i in [0...n]
      if return_exists and !_.has(result, fields[i]) then return false
      result = result[fields[i]]
      if result == null && i < n - 1
        result = {}

      if typeof result == 'undefined'
        if return_exists then return true
        return result

    if return_exists then return true
    result

  setNested = (obj, path, val, options) ->
    options = options || {};
    separator = DeepModel.keyPathSeparator
    fields = path.split(separator)
    result = obj
    n = fields.length
    for i in [0...n]
      if result == undefined then break
      field = fields[i]
      if i == n - 1
        if options.unset then delete result[field] else result[field] = val
      else
        if typeof result[field] == 'undefined' || !_.isObject(result[field])
          result[field] = {}
        result = result[field]

  deleteNested = (obj, path) ->
    setNested obj, path, null, unset: true


  class DeepModel extends Chaplin.Model
    constructor: (attributes, options) ->
      attrs = attributes || {}
      this.cid = _.uniqueId('c')
      this.attributes = {}
      if options and options.collection then @collection = options.collection
      if options and options.parse then attrs = @parse attrs, options or {}
      if defaults = _.result(this, 'defaults')
        attrs = _.deepExtend {}, defaults, attrs
      @set attrs, options
      @changed = {}
      @initialize.apply @, arguments

    toJSON: (options)->
      _.deepClone(this.attributes)

    get: (attr) ->
      getNested this.attributes, attr

    set: (key, val, options) ->
      if key == null then return this

      if typeof key == 'object'
        attrs = key;
        options = val || {};
      else
        (attrs = {})[key] = val

      options || options = {}
      if !this._validate(attrs, options) then return false

      unset = options.unset
      silent = options.silent
      changes = []
      changing = @_changing
      @_changing = true

      if not changing
        @_previousAttributes = _.deepClone this.attributes
        @changed = {}

      current = this.attributes
      prev = this._previousAttributes
      if  this.idAttribute of attrs then this.id = attrs[this.idAttribute]

      attrs = objToPaths attrs


      for attr, val of attrs
        if not _.isEqual(getNested(current, attr), val) then changes.push(attr)
        if not _.isEqual(getNested(prev, attr), val)
          setNested(this.changed, attr, val);
        else
          deleteNested(this.changed, attr);
        if unset then deleteNested(current, attr) else setNested(current, attr, val)

      if not silent
        if (changes.length) then @_pending = true
        separator = DeepModel.keyPathSeparator
        alreadyTriggered = {}

        for i in [0...changes.length]
          key = changes[i]

          if not alreadyTriggered.hasOwnProperty(key) || not alreadyTriggered[key]
            alreadyTriggered[key] = true;
            this.trigger('change:' + key, this, getNested(current, key), options);

          fields = key.split separator


          for n in [(fields.length - 1)...0]
            parentKey = _.first(fields, n).join(separator)
            wildcardKey = parentKey + separator + '*'

            if not alreadyTriggered.hasOwnProperty(wildcardKey) or not alreadyTriggered[wildcardKey]
              alreadyTriggered[wildcardKey] = true
              @trigger('change:' + wildcardKey, this, getNested(current, parentKey), options)

            if not alreadyTriggered.hasOwnProperty(parentKey) or not alreadyTriggered[parentKey]
              alreadyTriggered[parentKey] = true;
              @trigger('change:' + parentKey, this, getNested(current, parentKey), options)

      if changing then return this

      if not silent
        while (this._pending)
          @_pending = false
          @trigger 'change', this, options
      @_pending = false
      @_changing = false
      this

    clear: (options) ->
      attrs = {}
      shallowAttributes = objToPaths(this.attributes)
      attrs[key] = undefined for key in shallowAttributes
      this.set(attrs, _.extend({}, options, {unset: true}))

    hasChanged: (attr) ->
      if not attr? then return !_.isEmpty(this.changed)
      getNested(this.changed, attr) != undefined

    changedAttributes: (diff) ->
      if (!diff) then return (if this.hasChanged() then objToPaths(this.changed) else false)

      old = if this._changing then this._previousAttributes else this.attributes

      diff = objToPaths(diff)
      old = objToPaths(old)

      val = changed = false;
      for attr of diff
        if _.isEqual(old[attr], (val = diff[attr])) then continue
        (changed || (changed = {}))[attr] = val
      changed

    previous: (attr) ->
      if attr == null || !this._previousAttributes then return null
      getNested(this._previousAttributes, attr)

    previousAttributes: ->
      _.deepClone(this._previousAttributes)

  DeepModel.keyPathSeparator = '.'

  Chaplin.DeepModel = DeepModel
  if typeof module != undefined then module.exports = DeepModel
  Chaplin

