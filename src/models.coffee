# models.coffee
_ = require 'underscore'
util = require 'util'
backbone = require 'backbone'
{attr} = require './strongly'

class Issue extends backbone.Model
  constructor: ->
    super
    @urlRoot = "#{exports.baseUrl}/issue/"

  save: (attrs, options={}) ->
    options.username = exports.config.username
    options.password = exports.config.passwords
    super

  parse: (attributes) ->
    @url = attributes.self
    attrs = _.clone attributes.fields
    attrs.key = attributes.key
    attrs.id = attributes.id
    attrs

  attr @, 'summary',
    type: 'string'

  attr @, 'description',
    type: 'string'


class Project extends backbone.Model

class Status extends backbone.Model

class Priority extends backbone.Model

class IssueType extends backbone.Model

class User extends backbone.Model
  idAttribute: 'name'

class JiraCollection extends backbone.Collection
  fetch: (options={}) ->
    options.username = exports.config.username
    options.password = exports.config.password
    super

class ProjectCollection extends JiraCollection
  model: Project
  constructor: ->
    super
    @url = "#{exports.baseUrl}/project/"

class StatusCollection extends JiraCollection
  model: Status
  constructor: ->
    super
    @url = "#{exports.baseUrl}/status/"

class PriorityCollection extends JiraCollection
  model: Priority
  constructor: ->
    super
    @url = "#{exports.baseUrl}/priority/"

class IssueTypeCollection extends JiraCollection
  model: IssueType
  constructor: ->
    super
    @url = "#{exports.baseUrl}/issuetype/"

class UserCollection extends JiraCollection
  model: User
  constructor: ->
    super
    @url = "#{exports.baseUrl}/user/search?username=n"

  parse: (resp) ->
    console.log util.inspect resp
    resp

class IssueCollection extends JiraCollection
  model: Issue
  constructor: ->
    super
    @url = "#{exports.baseUrl}/search?jql=order+by+updated"

  parse: (response) ->
    response.issues


exports.Issue = Issue
exports.Project = Project
exports.Status = Status
exports.Priority = Priority
exports.IssueType = IssueType
exports.User = User
exports.IssueCollection = IssueCollection
exports.ProjectCollection = ProjectCollection
exports.StatusCollection = StatusCollection
exports.PriorityCollection = PriorityCollection
exports.IssueTypeCollection = IssueTypeCollection
exports.UserCollection = UserCollection
exports.baseUrl = null
exports.config = {}
exports.setup = (baseUrl, config) ->
  exports.baseUrl = baseUrl
  exports.config = config
