// Generated by CoffeeScript 1.7.1
(function() {
  "use strict";
  var MongoDB, Rserver, Rsocket, checkToken, cookie, crypto, moduleOptions, sockjs, winston;

  sockjs = require('sockjs');

  Rsocket = require("./lib/socket");

  Rserver = require("./lib/server");

  crypto = require('crypto');

  cookie = require('cookie');

  winston = require('winston');

  MongoDB = require('winston-mongodb').MongoDB;

  moduleOptions = {};

  checkToken = function(token, cb) {
    var redisClient;
    if (typeof cb !== 'function') {
      cb = function() {};
    }
    redisClient = moduleOptions.redis.client;
    return redisClient.get(token, function(err, result) {
      if (err) {
        return cb(err);
      }
      if (!result) {
        return cb(null, false);
      }
      return cb(null, result);
    });
  };

  module.exports = {
    configure: function(options) {
      if (options) {
        return moduleOptions = options;
      }
    },
    authenticate: function(req, res, next) {
      var hash, key, redis, sessionField, sessionFieldName;
      hash = crypto.createHash('sha1');
      hash.update(moduleOptions.auth.secret);
      hash.update('' + (new Date).getTime());
      key = hash.digest('hex');
      res.cookie(moduleOptions.auth.key, key);
      redis = moduleOptions.redis.client;
      sessionFieldName = moduleOptions.auth.sessionField;
      if (req.session.passport) {
        sessionField = req.session.passport[sessionFieldName];
      } else {
        sessionField = req.session[sessionFieldName];
      }
      sessionField = req.session[moduleOptions.auth.sessionField];
      if (sessionField) {
        redis.set(key, sessionField);
      }
      return next();
    },
    createServer: function(httpServer, cb) {
      var db, logger, redisClient, transports;
      transports = [
        new winston.transports.Console(), new MongoDB({
          level: 'info',
          db: 'rootty_logs',
          collection: 'rsocket'
        })
      ];
      if (moduleOptions.logFile) {
        transports.push(new winston.transports.File({
          filename: moduleOptions.logFile,
          maxsize: 1024 * 1000,
          maxFiles: 30
        }));
      }
      logger = new winston.Logger({
        transports: transports
      });
      db = moduleOptions.redis.db;
      this.sockjsServer = sockjs.createServer(moduleOptions);
      redisClient = moduleOptions.redis.client;
      moduleOptions.server.redis.client = redisClient;
      redisClient.select(db, (function(_this) {
        return function(err, result) {
          var onOriginalConnection, rserver;
          if (err) {
            logger.error(err);
            throw new Error(err);
          }
          redisClient.flushdb();
          logger.info('Redis db cleared.');
          rserver = new Rserver(moduleOptions.server);
          rserver.logger = logger;
          onOriginalConnection = function(conn) {
            var rsocket;
            rsocket = new Rsocket(conn, rserver);
            rserver.addSocket(rsocket);
            return rsocket.conn.once('data', function(cookies) {
              var authKey;
              cookies = cookie.parse(cookies);
              authKey = cookies[moduleOptions.auth.key];
              return checkToken(cookies[moduleOptions.auth.key], function(err, result) {
                if (err) {
                  logger.error(err);
                  throw new Error(err);
                }
                if (result) {
                  logger.info('AUTH SUCCESS', {
                    authKey: authKey,
                    socket: rsocket.id
                  });
                  rserver.activateSocket(rsocket, result);
                  return rserver.emit('connection', rsocket);
                }
                logger.info('AUTH FAILED', {
                  authKey: authKey,
                  socket: rsocket.id
                });
                return rsocket.conn.close(403, 'Not authorized');
              });
            });
          };
          _this.sockjsServer.on('connection', onOriginalConnection);
          _this.sockjsServer.installHandlers(httpServer);
          return cb(rserver);
        };
      })(this));
      return this;
    }
  };

}).call(this);
