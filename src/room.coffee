"user strict"

Room = (options) ->
  @server = options.server
  @name = options.name
  @key = "room:#{@name}"

  @getClients = (cb) ->  
    if typeof(cb) isnt 'function'
      cb = () ->
    @server.clientRedis.smembers @key, cb

  @add = (socket) ->
    socket_id = socket.id
    if @server.clientRedis.sadd @key, socket_id
      socket.rooms.push @name

  @remove = (socket) ->
    socket_id = socket.id
    if @server.clientRedis.srem @key, socket_id
      index = socket.rooms.indexOf @name
      socket.rooms.splice(index, 1) if index >= 0

  @emit = (label, data) ->
    @server.sendMessage @server.MSG_TYPES.ROOM_EMIT, 
      room: @name
      label: label
      data: data
  @



module.exports = Room