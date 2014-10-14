"use strict"

sockjs = require('sockjs')
Rsocket = require("./lib/socket")
Rserver = require("./lib/server")
crypto = require('crypto')
cookie = require('cookie')
winston = require('winston')
MongoDB = require('winston-mongodb').MongoDB
async = require('async')


  
moduleOptions = {

}

checkToken = (token, cb) ->
  if typeof(cb) isnt 'function'
    cb = () ->
  redisClient = moduleOptions.redis.client
  redisClient.get token, (err, result) ->
    return cb err if err
    return cb null, false if not result
    return cb null, result


module.exports = 
  configure: (options) ->
    if options
      moduleOptions = options


  authenticate: (req, res, next) ->
    hash = crypto.createHash('sha1')
    hash.update(moduleOptions.auth.secret)
    hash.update('' + (new Date).getTime())
    key = hash.digest('hex')
    res.cookie(moduleOptions.auth.key, key)
    redis = moduleOptions.redis.client
    sessionFieldName = moduleOptions.auth.sessionField
    if (req.session.passport) 
      sessionField = req.session.passport[sessionFieldName];
    else
      sessionField = req.session[sessionFieldName];
    redis.set(key, sessionField) if sessionField
    next()

  createLogger: (options) ->
    options = options || {}
    transports = [new (winston.transports.Console)(), new MongoDB({
      level: 'info',
      db: 'rootty_logs',
      collection: 'rsocket',
    })]
    logFile = options.file
    if logFile
      transports.push(new (winston.transports.File)({ 
        filename: logFile,
        maxsize: 1024 * 1000,
        maxFiles: 30
      }))
    return logger = new (winston.Logger)({
      transports: transports
    })

  createServer: (httpServer, cb) ->
    if typeof(cb) is 'undefined'
      cb = httpServer
      httpServer = false

    # Create logger
    logger = @createLogger(moduleOptions.log)
    # Create servers
    async.waterfall [
      # Create redis server
      (next) =>
        redisOptions = moduleOptions.redis
        db = redisOptions.clientDb
        redisClient = redisOptions.client
        # Connect redis client to specified db
        redisClient.select db, (err, result) ->
          return next err if err
          rserver = new Rserver 
            redis: 
              client: redisClient
              sub: redisOptions.sub
              pub: redisOptions.pub
          # Link logger to rserver 
          rserver.logger = logger
          next null, rserver

      # Create rsocket server
      (rserver, next) =>
        if not httpServer
          console.log 'Virtual sockets only.'
          return next null, rserver 

        console.log 'Listen real sockets.'
        # Clear
        rserver.clientRedis.flushdb() # TODO: related flush

        sockjsOptions = moduleOptions.socket
        @sockjsServer = sockjs.createServer(sockjsOptions)

        onOriginalConnection = (conn) =>
          rsocket = new Rsocket conn, rserver
          rserver.addSocket rsocket
          
          rsocket.conn.once 'data', (cookies) =>
            cookies = cookie.parse(cookies)
            authKey = cookies[moduleOptions.auth.key]

            checkToken cookies[moduleOptions.auth.key], (err, result) ->
              if err
                logger.error(err)
                throw new Error err
              if result
                logger.info('AUTH SUCCESS',  {
                  authKey: authKey,
                  socket: rsocket.id
                })
                rserver.activateSocket rsocket, result 
                return rserver.emit 'connection', rsocket
              logger.info('AUTH FAILED',  {
                authKey: authKey,
                socket: rsocket.id
              })
              return rsocket.conn.close(403, 'Not authorized')
        @sockjsServer.on 'connection', onOriginalConnection
        @sockjsServer.installHandlers httpServer
        return next null, rserver
    ], (err, rserver) ->
      if err
        logger.error(err)
        throw new Error err 
      cb rserver
