"user strict"

util = require("util")
events = require("events")
Room = require("./room")


Server = (options) ->
  options = options || {}
  redisOptions = options.redis || null

  if not redisOptions
    redisOptions  = 
      client: null
      sub: null
      pub: null

  @clientRedis = redisOptions.client
  @subRedis = redisOptions.sub
  @pubRedis = redisOptions.pub
  serverSubscribeChannelName = "rsocket_vent"

  @rooms = {
    "": {}
  }

  @MSG_TYPES = 
    'ROOM_EMIT': 1
    'SOCKET_EMIT': 2
    'SOCKET_REMOVE_FROM_ROOM': 3
    'SOCKET_REMOVE_FROM_ROOMS': 4
    'SOCKET_LEAVE_ROOM_BY_REG': 5
    'SOCKET_ADD_TO_ROOM': 6



  @sockets = 
    getClients: (roomName, cb) =>
      @clientRedis.smembers "room:#{roomName}", cb

    in: (roomName) =>
      room = @rooms[roomName]
      if not room
        room = _createRoom roomName
      return room
    
    removeSocketFromRoom: (socketId, room) =>
      @.sendMessage @.MSG_TYPES.SOCKET_REMOVE_FROM_ROOM, 
        socket: socketId
        room: room

    removeSocketFromRooms: (socketId, rooms) =>
      @.sendMessage @.MSG_TYPES.SOCKET_REMOVE_FROM_ROOMS, 
        socket: socketId
        rooms: rooms

    emitTo: (socketId, label, data) =>
      @.sendMessage @.MSG_TYPES.SOCKET_EMIT, 
        socket: socketId
        label: label
        data: data

    leaveRoomsByReg: (socketId, regStr) =>
      @.sendMessage @.MSG_TYPES.SOCKET_LEAVE_ROOM_BY_REG, 
        socket: socketId
        regStr: regStr

    addSocketToRoom: (socketId, room) =>
      @.sendMessage @.MSG_TYPES.SOCKET_ADD_TO_ROOM, 
        socket: socketId
        room: room

  @subRedis.subscribe(serverSubscribeChannelName)
  console.log "Socket redis connected to #{@subRedis.host}:#{@subRedis.port}"
  @subRedis.on 'message', (channel, message) =>
    message = JSON.parse message
    switch message.type

      when @MSG_TYPES.ROOM_EMIT

        body = message.data
        roomName = body.room
        room = @rooms[roomName]
        return false if not room
        clients = room.getClients (err, clients) =>
          throw new Error if err
          defaultRoom = @rooms[""]
          messageLabel = body.label
          messageData = body.data
          for client in clients
            socket = defaultRoom[client]
            continue if not socket
            socket.emit(messageLabel, messageData)

      when @MSG_TYPES.SOCKET_EMIT

        body = message.data
        socketId = body.socket
        socket = @rooms[""][socketId]
        return false if not socket
        messageLabel = body.label
        messageData = body.data
        socket.emit(messageLabel, messageData)

      when @MSG_TYPES.SOCKET_REMOVE_FROM_ROOM

        body = message.data
        socketId = body.socket
        room = body.room
        @removeFromRoom socketId, room

      when @MSG_TYPES.SOCKET_REMOVE_FROM_ROOMS

        body = message.data
        socketId = body.socket
        rooms = body.rooms
        for room in rooms
          @removeFromRoom socketId, room

      when @MSG_TYPES.SOCKET_LEAVE_ROOM_BY_REG
        body = message.data
        socketId = body.socket
        regStr = body.regStr
        @leaveRoomByReg socketId, regStr

      when @MSG_TYPES.SOCKET_ADD_TO_ROOM
        body = message.data
        socketId = body.socket
        roomName = body.room
        @addSocketToRoom socketId, roomName

  @activateSocket = (socket, sessionData) ->
    socket._activate(sessionData)

  @sendMessage = (type, data) ->
    message = 
      type: type
      data: data
    message = JSON.stringify message
    @pubRedis.publish(serverSubscribeChannelName, message)

  @addSocket = (socket) =>
    @rooms[""][socket.id] = socket

                                                                            # Actions with rooms

  _createRoom = (name) =>
    return new Room name: name, server: @

  @addSocketToRoom = (socketId, roomName) =>
    socket = @rooms[""][socketId]
    return false if not socket
    @addToRoom socket, roomName

  @addToRoom = (socket, roomName) =>
    room = @rooms[roomName]
    if not room
      room = @rooms[roomName] = _createRoom roomName
    room.add socket

  @removeFromRoom = (socket, roomName) =>
    socket = @rooms[""][socket] if not socket.id
    return false if not socket
    room = @rooms[roomName]
    if not room
      room = @rooms[roomName] = _createRoom roomName
    room.remove socket

  @leaveRoomByReg = (socketId, regStr) =>
    socket = @rooms[""][socketId]
    return false if not socket
    regExp = new RegExp regStr
    socket.leaveByReg regExp , () ->
      console.log 'removed from room by reg ' + regStr

  @

util.inherits Server, events.EventEmitter

module.exports = Server