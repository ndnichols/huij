util = require 'util'
readline = require 'readline'
_ = require 'underscore'

CLEAR_STATUS_DELAY = 3000

class CLI
  constructor: ->
    @debugMode = false
    @prompt = 'cypress> '
    @status = ''
    @introMessage = "Beep boop bip"
    @exitMessage = 'Goodbye'
    @matches = []
    @helpMessages = []
    @multilineCallback = null
    @emptyLineCount = 0
    @multilines = []
    @clearStatusTimeout = null
    @rl = readline.createInterface process.stdin, process.stdout
    @rl.on 'line', (line) =>
      @process line

  showPrompt: ->
    prompt = @prompt
    prompt = "[#{@status}] #{@prompt}" if @status
    @rl.setPrompt(prompt, prompt.length)
    @rl._refreshLine() #Ohhh, undocumented APIs!

  updateStatus: (@status='', clear) ->
    clearTimeout @clearStatusTimeout if @clearStatusTimeout
    @clearStatusTimeout = null
    @showPrompt()
    if clear
      callback = =>
        @updateStatus()
      @clearStatusTimeout = setTimeout callback, CLEAR_STATUS_DELAY

  close: ->
    console.log @exitMessage
    @rl.close();
    process.stdin.destroy();
    process.exit(0)

  process: (line) ->
    handled = false
    helping = false
    if @multilineCallback
      # We're in multiline mode
      if not line.trim()
        @emptyLineCount++
        if @emptyLineCount >= 2
          lines = @multilines
          callback = @multilineCallback
          # clean up
          @multilines = []
          @emptyLineCount = 0
          @multilineCallback = null
          # and call
          callback lines
      else
        @emptyLineCount = 0
        @multilines.push line.trim()
    else
      if not line.trim()
        return @showPrompt()
      if line[0...4] is 'help'
        helping = true
        line = line[5..].trim()
        if not line
          console.log "\nAvailable commands:"
          for [pattern, helpMessage, callback] in @matches
            console.log "#{pattern}: #{helpMessage}"
          console.log ""
          @showPrompt()
          return
      for [pattern, helpMessage, callback] in @matches
        if _.isString pattern
          if line[0...pattern.length] is pattern
            if helping
              console.log "#{pattern}: #{helpMessage}"
            else
              args = [line[pattern.length+1..]]
            handled = true
          else if @debugMode
            console.log "#{line} does not begin with string #{pattern}"
        else if _.isRegExp pattern
          match = line.match pattern
          if match
            if helping
              console.log "#{pattern}: #{helpMessage}"
            else
              args = match[1..]
            handled = true
          else if @debugMode
            console.log "#{line} does not match #{pattern}"
        else if _.isArray pattern
          if line.match pattern[0]
            args = []
            for subPattern in pattern
              match = subPattern.exec line
              if @debugMode
                console.log "match for #{subPattern} in #{line} is #{match}"
              args.push match?[1]
            handled = true
          else if @debugMode
            console.log "#{line} does not match first pattern #{pattern[0]}"
        if handled
          args.push line
          response = callback.call @, args...
          break
      console.log "Command #{line} not recognized" if not handled
    @showPrompt()

  on: (pattern, msg, callback) ->
    @matches.push [pattern, msg, callback]

  listen: ->
    @introMessage
    @showPrompt()

  every: (ms, callback) ->
    setInterval (=> callback.call(@)), ms

  write: (msg) ->
    console.log msg

createCLI = ->
  ret = new CLI()
  # ret.on /^help$/, ->
  #   console.log "\nCommands:"
  #   for [pattern, msg] in @helpMessages
  #     console.log "#{pattern}: #{msg}"
  #   console.log


exports.createCLI = -> new CLI()

# cli = new CLI()

# cli.on /hello ([\w]+)/, "Greets the user by name", (name)->
#   "Goodbye #{name}!"

# cli.on /[quit|exit]/, "Exits the app", ->
#   cli.close()

# cli.listen()