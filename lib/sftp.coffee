_ = require 'underscore'
fs = require 'fs'
tmp = require 'tmp'
pty = require 'pty.js'
CommandQueue = require './command_queue'

module.exports = class SFTP
  constructor: (login) ->
    @host = login.host
    @port = login.port
    @user = login.user
    @key = login.key
    @queue = new CommandQueue

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
      @pty.on 'close', _.bind(@onPTYClose, this)
      callback null

  onPTYClose: (hadError) ->

  runCommand: (command, callback) ->
    @queue.enqueue =>
      buffer = []
      dataListener = (data) =>
        data = data.replace /\r/g, ''
        buffer.push data
        if data.indexOf("\nsftp> ") != -1
          @pty.removeListener 'data', dataListener
          callback buffer.join ''
          @queue.dequeue()
      @pty.on 'data', dataListener
      @pty.write command + "\n"

  @escape: (string) ->
    if typeof string == 'string'
      return "'" + string.replace(/'/g, "'\"'\"'") + "'"
    null

  ls: (filePath, callback) ->
    this.runCommand "ls -l #{@constructor.escape filePath}", (data) ->
      lines = data.split "\n"
      lines.shift()
      lines.pop()
      if lines[0].match /No\ssuch\sfile\sor\sdirectory/
        callback lines.join("\n"), null
      else
        files = lines.map (line) ->
          match = line.match /^(\S+\s+){8}(.+)$/
          name = match[2]
          isDir = line[0] == 'd'
          [name, isDir]
        callback null, files
