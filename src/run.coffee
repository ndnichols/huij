# run.coffee
fs = require 'fs'
util = require 'util'
models = require './models'
require './nsutil'

config = JSON.parse(fs.readFileSync "#{process.env['HOME']}/.huij")
API_BASE_URL = 'https://jira.n-s.us/rest/api/2'

models.setup API_BASE_URL, config

# WORKS
issues = new models.IssueCollection()
issues.fetch
  data: startAt: 0
  success: ->
    console.log "SUCCESS LOADING!"
    console.log util.inspect (issues.at 0).attributes
    console.log issues.at(0).summary
    console.log issues.at(0).description
  error: -> console.log "ERROR LOADING!"
# /WORKS

# projects = new models.ProjectCollection()
# projects.fetch
#   success: ->
#     console.log "Projects good!"
#     console.log util.inspect (projects.at 0).attributes
#   error: -> console.log "projects error! #{util.inspect arguments}"

# statuses = new models.StatusCollection()
# statuses.fetch
#   success: ->
#     console.log "statuses good!"
#     console.log util.inspect (statuses.at 0).attributes
#   error: -> console.log "statuses error! #{util.inspect arguments}"

# priorities = new models.PriorityCollection()
# priorities.fetch
#   success: ->
#     console.log "priorities good!"
#     console.log util.inspect (priorities.at 0).attributes
#   error: -> console.log "priorities error! #{util.inspect arguments}"

# issuetypes = new models.IssueTypeCollection()
# issuetypes.fetch
#   success: ->
#     console.log "issuetypes good!"
#     console.log util.inspect (issuetypes.at 0).attributes
#   error: -> console.log "issuetypes error! #{util.inspect arguments}"

# users = new models.UserCollection()
# users.fetch
#   success: ->
#     console.log "users good!"
#     console.log util.inspect (users.at 0).attributes
#   error: -> console.log "users error! #{util.inspect arguments}"