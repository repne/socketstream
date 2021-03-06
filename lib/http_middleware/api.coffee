# Middleware: HTTP API
# --------------------
# Automatically makes all public methods within /app/server accesible over a HTTP request-based API
# This module will only be loaded if SS.config.api.enabled == true

# EXAMPLES:

# /api/app/square.json?5 is the same as calling remote('app.square', 5, console.log) from the browser
# To see the output on screen type type .html instead of .json
# Pass objects in the query string: E.g. /api/user/add.json?name=Tom&age=21 is the same as remote('user.add',{name: 'Tom', age: 21},cb)
# Note: Make sure your application code casts strings into the type of value you're expecting when using the HTTP API

url_lib = require('url')
Session = require('../session.coffee').Session
Request = require('../request.coffee')
base64 = require('../utils/base64.js')
server = require('../utils/server.coffee')
RTM = require('../realtime_models') if SS.config.rtm.enabled

exports.call = (request, response, next) ->
  
  if request.ss.parsedURL.initialDir == SS.config.api.prefix
    url = url_lib.parse(request.url, true)
    path = url.pathname.split('.')
    action = path[0]
    actions = request.ss.parsedURL.actions

    # Browse API if viewing root
    if actions.length <= 1
      server.deliver(response, 200, 'text/html', 'Browse public API. Coming soon.')
    # Or attempt to process request
    else
      process(request, response, url, actions)
  else
    next()


# PRIVATE


# Process an API Request
process = (request, response, url, actions) ->

  # Create new session instance. This won't be stored in Redis as no client object is passed
  session = new Session
  
  try
    params = parseParams(url)
    format = request.ss.parsedURL.extension || 'html'
      
    # Check format is supported
    throw new Error('Invalid output format. Supported formats: ' + output_formats.keys().join(', ')) unless output_formats.keys().include(format)

    # Rest is highly experimental / testing
    if RTM and actions[0] == '_rest'
      actions = actions.slice(1) # remove prefix
      RTM.rest.processRequest actions, params, request, format, (data) -> reply(data, response, format)
      SS.log.incoming.rest(actions, params, format, request.method)
  
    # Serve regular request to /app/server
    else
      authenticate request, response, actions, session, (success) ->
        if success
          Request.process actions, params, session, (data, options) -> reply(data, response, format)
          SS.log.incoming.api(actions, params, format)
  catch e
    server.showError(response, e)
        
# Formats and deliver the object
reply = (data, response, format) ->
  out = output_formats[format](data)
  server.deliver(response, 200, out.content_type, out.output)

# Attempts to make sense of the params passed in the query string
parseParams = (url) ->
  try
    if url.search
      if url.search.match('=')        # Test to see if we're trying to pass an object
        url.query
      else
        url.search.split('?')[1]      # Or just a string/number
    else
      undefined
  catch e
    throw new Error('Unable to parse params. Check syntax.')


# Authenticate. Only Basic Auth is supported at the moment, but this can and should run over HTTPs
authenticate = (request, response, actions, session, cb) ->
  mod_path = actions.slice(0,-1).join('.')
  if SS.internal.authenticate[mod_path]
    if request.headers.authorization
      
      auth = request.headers.authorization.split(' ')
      details = base64.decode(auth[1]).split(':')
      params = {}
      [params.username, params.password] = details

      # Try to authenticate user
      session.authenticate SS.config.api.auth.basic.module_name, params, (reply) ->
        if reply.success
          session.setUserId(reply.user_id)
          cb(true)
        else
          server.showError(response, 'Invalid username or password')
          cb(false)
      
    else
      response.writeHead(401, {'WWW-Authenticate': 'Basic realm="' + SS.config.api.auth.basic.realm + '"', 'Content-type': 'text/html'})
      response.end('Not authorized')
      cb(false)
  else
    cb(true) 


# Formats data for output
output_formats =

  json: (data) ->
    {output: JSON.stringify(data), content_type: 'text/json'}

  # TODO: improve with syntax highlighting
  html: (data) ->
    {output: JSON.stringify(data), content_type: 'text/html'}
    
  # TODO: add XML once we find a great lightweight object.toXML() library
