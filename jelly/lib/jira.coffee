fs = require 'fs'
util = require 'util'
backbone = require 'backbone'
_ = require 'underscore'
rest = require 'restler'
$ = require 'jquery'
xmlhttprequest = require 'xmlhttprequest'
$.support.cors = true
$.ajaxSettings.xhr = ->
  new xmlhttprequest.XMLHttpRequest
backbone.setDomLibrary $

get = (url, options={}) ->
  options.username = exports.auth.username
  options.password = exports.auth.password
  rest.get url, options

class Issue extends backbone.Model
  constructor: ->
    super
    @urlRoot = "#{exports.baseUrl}/issue/"

  humanUrl: ->
    baseUrl = @urlRoot[0...@urlRoot.indexOf('/rest/')]
    "#{baseUrl}/browse/#{@.get 'key'}"

  fetch: (options={}) ->
    options.username = exports.auth.username
    options.password = exports.auth.password
    super options

  transitionTo: (transitionId, fetchOptions={}) ->
    url = "#{@url()}/transitions"
    data =
      transition:
        id: transitionId
    options = {}
    options.username = exports.auth.username
    options.password = exports.auth.password
    options.headers = {'Content-Type': 'application/json'}
    options.data = JSON.stringify data
    (rest.post url, options).on 'complete', (response) =>
      @fetch fetchOptions

  save: (attrs, options={}) ->
    options.username = exports.auth.username
    options.password = exports.auth.password
    super attrs, options

class IssueCollection extends backbone.Collection
  model: Issue
  constructor: ->
    super
    @url = "#{exports.baseUrl}/search?jql=order+by+updated"

  fetch: (options={}) ->
    options.username = exports.auth.username
    options.password = exports.auth.password
    super options

  parse: (response) ->
    response.issues

class IssueTypeCache
  constructor: (@cache={}) ->

  setup: ->
    url = "#{exports.baseUrl}/issuetype"
    (get url).on 'complete', (response) =>
      if response instanceof Error
        throw response
      for status in response
        @cache[status.id] = status.name
        @cache[status.name] = status.id

  getId: (name) ->
    console.log "Getting name for #{name}, @cache is #{util.inspect @cache}"
    @cache[name]
  getName: (id) -> @cache[id]


class IssueStatusCache
  constructor: (@cache={}) ->

  setup: ->
    url = "#{exports.baseUrl}/status"
    (get url).on 'complete', (response) =>
      if response instanceof Error
        throw response
      for type in response
        @cache[type.id] = type.name
        @cache[type.name] = type.id

  getId: (name) -> @cache[name]
  getName: (id) -> @cache[id]


class FixVersionCache
  constructor: (@versions={})->

  setup: ->
    # Gets all the version ids
    url = "#{exports.baseUrl}/project/"

    (get url).on 'complete', (versions) =>
      if versions instanceof Error
        throw versions
      for project in versions
        key = project.key
        @versions[key] = {}
        @_getId key

  _getId: (key) ->
    url = "#{exports.baseUrl}/project/#{key}/versions"
    (get url).on 'complete', (response) =>
      if response instanceof Error
        console.log util.inspect response
        throw response
      return if not response?.length
      for version in response
        {id, name} = version
        @versions[key][name] = id
        @versions[id] = name

  getId: (projectKey, versionName) ->
    @versions[projectKey][versionName]

  getName: (versionId) ->
    @versions[versionId]


exports.IssueCollection = IssueCollection
exports.Issue = Issue
exports.versions = new FixVersionCache()

exports.baseUrl = null
exports.auth = {}
exports.setup = (baseUrl, auth) ->
  exports.baseUrl = baseUrl
  exports.auth = auth
  exports.versions = new FixVersionCache()
  exports.versions.setup()
  exports.types = new IssueTypeCache()
  exports.types.setup()
  exports.statuses = new IssueStatusCache()
  exports.statuses.setup()
