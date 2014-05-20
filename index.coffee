"use strict"

sockjs = require('sockjs')
Rsocket = require("./lib/socket")
Rserver = require("./lib/server")
crypto = require('crypto')
cookie = require('cookie')
winston = require('winston')
MongoDB = require('winston-mongodb').MongoDB


  
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
    sessionField = req.session[moduleOptions.auth.sessionField]
    redis.set(key, sessionField) if sessionField
    next()

  createServer: (httpServer, cb) ->
    transports = [new (winston.transports.Console)(), new MongoDB({
      level: 'info',
      db: 'rootty_logs',
      collection: 'rsocket',
    })]
    if moduleOptions.logFile
      transports.push(new (winston.transports.File)({ 
        filename: moduleOptions.logFile,
        maxsize: 1024 * 1000,
        maxFiles: 30
      }))
    logger = new (winston.Logger)({
      transports: transports
    })
    db = moduleOptions.redis.db

    @sockjsServer = sockjs.createServer(moduleOptions)
    redisClient = moduleOptions.redis.client
    moduleOptions.server.redis.client = redisClient
    
    redisClient.select db, (err, result) =>
      if err
        logger.error(err)
        throw new Error err 
      redisClient.flushdb()   
      logger.info('Redis db cleared.')
      rserver = new Rserver moduleOptions.server
      rserver.logger = logger
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
      cb rserver

    return this


