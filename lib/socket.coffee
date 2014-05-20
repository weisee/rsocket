"user strict"

util = require("util")
events = require("events")

Socket = (conn, server) ->
  @conn = conn
  @server = server
  @id = @conn.id
  @_emit = @emit
  @rooms = []
  @session = {}

  @onElapsedTime = (socket) ->
    socket.server.logger.warn('Time elapsed for %s and socket %s', socket.session, socket.id, {
      session: socket.session,
      socket: socket.id,
      conn_id: socket.conn.id,
    })
    socket.conn.close(408, 'Ping timeout')

  @_updateTimeout = () ->
    clearTimeout @pingTimeout if @pingTimeout
    @pingTimeout = setTimeout @onElapsedTime, 60 * 1000, @


  @_onConnectionData = (message) =>
    @_updateTimeout()
    if message is 'ping:request'
      return false
    message = @_parseMessage message
    args = [message.label].concat message.data
    @_emit.apply @, args
  @_onDisconnect = () =>
    clearTimeout @pingTimeout if @pingTimeout
    transaction  = @server.clientRedis.multi()
    for room in @rooms
      transaction.srem 'room:' + room, @id
    transaction.exec (err, replies) =>
      throw new Error if err
      @_emit 'disconnect'
      @server.logger.warn('DISCONNECT',{
        session: @session,
        socket: @id,
      })
  @_parseMessage = (message) ->
    message = JSON.parse message
    return {
      label: message._label
      data: message.data
    }
  @_generateMessage = (label, data) ->
    return JSON.stringify {
      _label: label
      data: data
    }
  @emit = (label, args) ->
    if arguments.length > 2
      args = []
      for arg, i in arguments 
        args.push arg if i isnt 0
    message = @_generateMessage label, args
    @conn.write message


  @join = (room) =>
    @server.addToRoom @, room

  @leave = (room) =>
    @server.removeFromRoom @, room

  @_activate = (sessionData) =>
    @session = sessionData || {}
    @conn.on 'data', @_onConnectionData
    @_updateTimeout()

  @conn.on 'close', @_onDisconnect
  @

util.inherits Socket, events.EventEmitter

module.exports = Socket