_ = require 'underscore'
fs = require 'fs'
path = require 'path'
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
          '-q'
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
      return "'" + string.replace(/\'/g, "'\"'\"'") + "'"
    null

  ls: (filePath, callback) ->
    this.runCommand "ls -l #{@constructor.escape filePath}", (data) ->
      lines = data.split "\n"
      lines.shift()
      lines.pop()
      files = []
      errors = null
      for line in lines
        if !errors && (match = line.match /^\s*([drwx-]+)\s+([\d]+)\s+([\w]+)\s+([\w]+)\s+([\d]+)\s+([\w\s\d]+)([\d]{2}\:[\d]{2})\s+(.*)$/)
          name = match[8]
          isDir = line[0] == 'd'
          files.push [name, isDir]
        else
          files = null
          errors ?= []
          errors.push line
      errors = errors.join '\n' if errors
      callback errors, files

  mkdir: (dirPath, callback) ->
    this.runCommand "mkdir #{dirPath}", (data) ->
      lines = data.split "\n"
      if lines.length == 2
        callback null
      else
        lines.shift()
        lines.pop()
        callback lines.join "\n"

  rmdir: (dirPath, callback) ->
    this.runCommand "rmdir #{dirPath}", (data) ->
      lines = data.split "\n"
      if lines.length == 2
        callback null
      else
        lines.shift()
        lines.pop()
        callback lines.join "\n"

  get: (filePath, callback) ->
    tmp.dir (err, tmpdirPath) =>
      this.runCommand "get #{filePath} #{tmpdirPath}", (data) ->
        lines = data.split "\n"
        if lines.length != 3
          lines.shift()
          lines.pop()
          callback lines.join "\n"
        else
          tmpfilePath = "#{tmpdirPath}/#{path.basename(filePath)}"
          fs.readFile tmpfilePath, (err, data) ->
            if err
              callback err, null
            else
              fs.unlinkSync tmpfilePath
              callback null, data

  put: (filePath, callback) ->
    this.runCommand "put #{filePath}", (data) ->
      lines = data.split "\n"
      lines.shift()
      lines.pop()
      if /^Uploading\s/.test lines[0]
        callback null
      else
        callback lines.join "\n"
