{exec} = require 'child_process'
fs = require 'fs'
util = require 'util'
rest = require 'restler'
cypress = require './cypress'
_ = require 'underscore'
jira = require 'jira'
colors = require 'colors'

POINTS_REMAINING = 'customfield_10105'
POINTS_TOTAL = 'customfield_10122'
API_BASE_URL = 'https://jira.n-s.us/rest/api/2'


exports.callback = (msg='') =>
  # Takes a message and returns a callback that takes a restler response.
  # If the response was an error, prints the error message, otherwise prints
  # message
  (result) ->
    if result instanceof Error
      console.log "Error: #{result.message}"
    else if msg
      console.log msg
      console.log util.inspect result

toTitleCase = (str) ->
  str.replace /\w\S*/g, (txt) -> "#{txt[0].toUpperCase()}#{txt[1..]}"

humanSortValue = (issue) ->
  fields = issue.get 'fields'
  if not fields.status?
    return -2000
  else if fields.status.name is 'In Progress'
    ret = -1000
  else if fields.status.name is 'Reopened'
    ret = 0
  else if fields.status.name is 'Open'
    ret = 1000
  else if fields.status.name is 'Resolved'
    ret = 2000
  else if fields.status.name is 'Closed'
    ret = 3000
  ret += fields.summary.charCodeAt(0)
  ret

class Jelly
  constructor: (@config) ->
    @maxResults = 500
    @view = null
    @issues = new jira.IssueCollection()
    @refreshingConfigs = false
    @auth =
      username: @config.username
      password: @config.password
    @transitions =
      Close: 2
      Reopen: 3
      Start: 4
      Resolve: 5

  getWeek: (date) =>
    'Returns the week number of the date.  Thanks, Internet!'
    jan1 = new Date date.getFullYear(), 0, 1
    ret = Math.round Math.ceil( ((date - jan1) / 86400000) + jan1.getDay() + 2) / 7
    console.log "#{ret} is ret"
    ret


  getSprintName: (delta) ->
    num = (@getWeek new Date()) + delta
    "Sprint 1#{num}"

  refreshConfigs:  =>
    onAdd = =>
      @view.updateStatus "#{parseInt(@issues.length*100/@maxResults, 10)}% loaded..."
      if @issues.length >= @maxResults
        @issues.off 'add', onAdd
        @view.updateStatus ""
    @issues.on 'add', onAdd
    @issues.reset()
    @view.updateStatus 'Updating issues, please wait...'
    for i in [0 ... @maxResults / 50]
      @issues.fetch
        error: ->  console.log "There was an error loading stories!"
        add: true
        data: startAt: i*50

  formatIssue: (issue, skipFields=['description']) ->
    ret = []
    data = issue.get('fields')
    key = "#{issue.get('key')}: "
    ret.push key.yellow
    ret.push "#{jira.types.getName data.issuetype.id} "
    console.log "data.status?.id is #{data.status?.id}"
    ret.push "#{jira.statuses.getName data.status?.id} "
    if data[POINTS_REMAINING]? or data[POINTS_TOTAL]?
      ret.push '('
      if data[POINTS_REMAINING]?
        ret.push "#{data[POINTS_REMAINING]} points remaining, "
      if data[POINTS_TOTAL]?
        ret.push "#{data[POINTS_TOTAL]} points total"
      ret.push ')'
    fixVersions = data?.fixVersions or []
    fixVersions = _.map fixVersions, (version) -> jira.versions.getName version.id
    ret.push "[#{fixVersions.join ', '}] "
    ret.push "\n\t\"#{data.summary}\" "
    ret.push "(#{data.assignee.name}) " if data.assignee? and 'assignee' not in skipFields
    ret.push "\n#{data.description} " if data.description? and 'description' not in skipFields
    msg = (ret.join '').trim()
    @view.write msg

  listIssues: (name, openFlag, delta, unit) =>
    return 'no issues loaded' if not @issues? or _.isEmpty @issues
    ret = []
    filters = []
    skipFields = ['description']
    if name
      name = name.trim()
      name = name.replace /'$/, ''
      name = name.replace /'s$/, ''
      name = @auth.username if name is 'my'
      filters.push (issue) ->
        issue.get('fields').assignee?.name is name
      skipFields.push 'assignee'
    if unit is 'week' or unit is 'sprint'
      sprintDelta = -1 if delta is 'last'
      sprintDelta = 0 if delta is 'this'
      sprintDelta = 1 if delta is 'next'
      sprintName = @getSprintName sprintDelta
      filters.push (issue) =>
        for version in issue.get('fields').fixVersions
          return true if sprintName is jira.versions.getName version.id
        false
    if openFlag is 'open'
      filters.push (issue) ->
        statusName = jira.statuses.getName issue.get('fields').status?.id
        statusName not in ['Resolved', 'Closed']

    filter = (issue) =>
      for subfilter in filters
        return false if not subfilter issue
      true

    issues = @issues.filter filter
    if _.isEmpty issues
      return 'No issues'

    for issue in _.sortBy issues, humanSortValue
      ret.push @formatIssue issue, skipFields
    ret.join '\n'

  getVersionsForString: (projectKey, string) ->
    # string will be like "this sprint" or "next quarter"
    # returns a list of all the versions we should add
    [delta, unit] = string.split ' '
    delta = -1 if delta is 'last'
    delta = 0 if delta is 'this'
    delta = 1 if delta is 'next'
    if unit in ['week', 'sprint']
      sprintName = @getSprintName delta
      sprintId = jira.versions.getId projectKey, sprintName
      return [sprintId]
    else
      throw new Error "Quarters don't work yet"

  createIssue: (__, points, issueType, user, project, due, title, ellipsis) =>
    return "I need a summary" if not title?
    issueId = jira.types.getId toTitleCase(issueType or 'task')
    user = user or @auth.username
    user = @auth.username if user is 'me'
    project = project or @config.defaultProject
    title = title or ""
    fixVersions = if due? then @getVersionsForString project, due else []
    console.log "issueType #{issueType}, points #{points}, user #{user}, project #{project}, due #{due}, title #{title}"
    console.log "fixVersions are #{fixVersions}"
    attrs =
      fields:
        assignee: {name: user}
        project:
          key: project
        summary: title
        description: ""
        fixVersions:
          id: id for id in fixVersions
        issuetype:
          id: issueId
    if points?
      attrs.fields[POINTS_REMAINING] = points
      attrs.fields[POINTS_TOTAL] = points
    # issue = @issues.create attrs, wait:true
    issue = new jira.Issue attrs
    @issues.add issue
    issue.on 'sync', (issue, issues) =>
      console.log "@ is #{console.log util.inspect @}"
      @view.updateStatus "#{issue.get('key')} saved", true
      id = issue.id
      console.log "id is #{id}, getting on collection is #{@issues.get id}"
      console.log "key is #{issue.get 'key'}"
      issue.off 'sync'

    saveOptions =
      error: (issue, msg) => @view.updateStatus "There was an error: #{util.inspect msg}"
    if ellipsis?
      @view.multilineCallback = (lines) =>
        issue.set 'description', lines.join '\n'
        issue.save {}, saveOptions
      console.log  'Type your description, followed by two blank lines'
    else
      issue.save {}, saveOptions
    true

  updatePoints: (issue, points) ->
    console.log "Points is #{points} on #{issue.get('key')}"
    return
    @view.updateStatus "Updating #{issue.get('key')}..."
    fields = issue.get 'fields'
    if points >= 0
      # We'll set it
      fields[POINTS_REMAINING] = points
    else
      fields[POINTS_REMAINING] -= fields[POINTS_REMAINING]
    issue.set 'fields', fields
    issue.save {},
      success: (issue, msg) => @view.updateStatus "#{issue.get('key')} saved", true
      error: (issue, msg) => @view.updateStatus "There was an error: #{util.inspect msg}"

  _transition: (issue, state, openingTest, closedText) =>
    @view.updateStatus "#{openingTest} #{issue.get('key')}..."
    transitionId = @transitions[state]
    issue.transitionTo transitionId,
      success: => @view.updateStatus "#{issue.get('key')} #{closedText}", true
      error: => @view.updateStatus "There was an error", true

  reopen: (issue) =>
    @_transition issue, "Reopen", 'Reopening', 'Reopened'

  close: (issue) =>
    @_transition issue, "Close", 'Closing', 'Closed'

  resolve: (issue) =>
    @_transition issue, "Resolve", 'Resolving', 'Resolved'

  start: (issue) =>
    @_transition issue, "Start", 'Starting', 'Started'

  test: =>
    url = "https://jira.n-s.us/rest/api/2/issuetype"
    console.log url
    (rest.get url, @auth).on 'complete', (result) ->
      console.log util.inspect result

  getIssue: (issueId) =>
    # Takes a human writeable issue id (maybe a number, maybe a word, maybe
    # something else, returns the issue blob thing
    if issueId.match /^[A-Z]-\d+$/
      # Already a key
      key = issueId
    else if issueId.match /^\d+$/
      key = "#{@config.defaultProject}-#{issueId}"
    else
      console.log "I don't know what \"#{issueId}\""
      return
    @issues.find (issue) -> issue.get('key') is key

config = JSON.parse(fs.readFileSync "#{process.env['HOME']}/.jelly")

jira.setup(API_BASE_URL, config)

jelly = new Jelly config
cli = cypress.createCLI()
jelly.view = cli
cli.prompt = 'jelly> '
cli.on /^(?:list)?(?:\s*)(?:([\w']*) )?(?:(open) )?issues(?:\s(this|next|last)\s(sprint|week))?$/, 'Lists issues', jelly.listIssues
cli.on [/new/, /(\d+) point?/, /(story|bug|feature|improvement|task)/, /(?: for (\w+))/, /(?: in (\w+))/, /(?: due ((?:in|this|next) \w+))/, /"(.*)?"/, /(\.\.\.)/], 'Creates a new task', jelly.createIssue
cli.on /^close ([\w\d]+)$/, 'Closes issue', (issueId) ->
  issue = jelly.getIssue issueId.trim()
  jelly.close issue
  true
cli.on /^resolve ([\w\d]+)$/, 'Resolves an issue', (issueId) ->
  issue = jelly.getIssue issueId.trim()
  jelly.resolve issue
  true
cli.on /^reopen ([\w\d]+)$/, 'Reopens an issue', (issueId) ->
  issue = jelly.getIssue issueId.trim()
  jelly.reopen issue
  true
cli.on /^start ([\w\d]+)$/, 'Starts an issue', (issueId) ->
  issue = jelly.getIssue issueId.trim()
  jelly.start issue
  true
cli.on /^show ([\w\d]+)$/, 'Shows the full issue', (issueId) ->
  issue = jelly.getIssue issueId.trim()
  if issue
    jelly.formatIssue issue, []
  else
    console.log "Don't know issue"
cli.on /^open ([\w\d]+)$/, 'Opens the issue in a browser', (issueId) ->
  issue = jelly.getIssue issueId.trim()
  open = if config.browser? then config.browser else 'open'
  s = "#{open} \"#{issue.humanUrl()}\""
  jelly.view.updateStatus s, true
  exec s
cli.on /^(?:did|finished|completed) (\d+) (?:point|points)? on ([\w\d]+)$/, "Marks points done", (points, issueId) ->
  issue = jelly.getIssue issueId.trim()
  points = -parseInt(points)
  jelly.updatePoints issue, points
cli.on /^(\d+) (?:point|points)?(?:\s*)left on ([\w\d]+)$/, "Sets points left", (points, issueId) ->
  issue = jelly.getIssue issueId.trim()
  points = parseInt(points)
  jelly.updatePoints issue, points


cli.on 'test', 'Messing around', -> debuggger

cli.on /^(?:q|quit|exit)$/, "Exits the app", ->
  cli.close()

cli.every 300000, jelly.refreshConfigs

jelly.refreshConfigs()
cli.listen()


# new issue "fo"

