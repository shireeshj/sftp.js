_ = require 'underscore'
fs = require 'fs'
tmp = require 'tmp'
pty = require 'pty.js'

module.exports = class SFTP
  constructor: (login) ->
    @host = login.host
    @port = login.port
    @user = login.user
    @key = login.key
    @commandStack = []

  writeKeyFile: (callback) -> # callback(err, sshArgs, deleteKeyFile)
    tmp.file (err, path, fd) =>
      if err
        callback err
        return
      b = new Buffer @key
      fs.write fd, b, 0, b.length, 0, (err, written, buffer) =>
        if err
          fs.unlink path, -> callback(err)
          return
        sshArgs = [
          '-i', path
          '-o', 'UserKnownHostsFile=/dev/null'
          '-o', 'StrictHostKeyChecking=no'
          '-o', 'PubkeyAuthentication=yes'
          '-o', 'PasswordAuthentication=no'
          '-o', 'LogLevel=FATAL'
          '-P', "#{@port}"
          "#{@user}@#{@host}"
        ]
        deleteKeyFile = (callback) ->
          fs.unlink path, ->
            callback?()
        callback null, sshArgs, deleteKeyFile

  connect: (callback) -> # callback(err)
    this.writeKeyFile (err, sshArgs, deleteKeyFile) =>
      if err
        callback(err)
        return
      try
        @pty = pty.spawn '/usr/bin/sftp', sshArgs
      catch err
        deleteKeyFile ->
          callback err
        return
      @pty.once 'data', ->
        deleteKeyFile()
      @pty.on 'data',  _.bind(@onPTYData, this)
      @pty.on 'close', _.bind(@onPTYClose, this)
      callback null

  onPTYData: (data) ->

  onPTYClose: (hadError) ->

