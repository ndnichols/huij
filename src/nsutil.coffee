# Has various generally useful functions.
_ = require 'underscore'
# Jquery is a little wonky.  We want it to work from node or after being
# browserified.  So we expose a $ here that hides some of that logic

# It's already global, just used that
if $?
  exports.$ = $
# Require jQuery, which does not like to be browserified.  So we hide from
# browserify with a shady eval
else
  exports.$ = eval "require('jquery')"
  if not process.browser
    # Have to swizzle around some stuff here to make $.ajax work properly in
    # node
    exports.$.support.cors = true
    xmlhttprequest = eval "require('xmlhttprequest')"
    exports.$.ajaxSettings.xhr = ->
      new xmlhttprequest.XMLHttpRequest
    cached = exports.$
    cached

# Setup backbone to use our jquery, which is safe to do in the browser because
# it will already be global.
backbone = require 'backbone'
backbone.setDomLibrary exports.$
