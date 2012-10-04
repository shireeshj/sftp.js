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
    this.destroy()

  destroy: (callback) ->
    @queue.enqueue =>
      @pty.removeAllListeners()
      @pty.write "bye\n"
      @pty.destroy()
      delete @queue
      delete @pty
      callback()

  runCommand: (command, callback) ->
    @queue?.enqueue =>
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
    tmp.dir (err, tmpDirPath) =>
      this.runCommand "get #{filePath} #{tmpDirPath}", (data) ->
        lines = data.split "\n"
        if lines.length != 3
          lines.shift()
          lines.pop()
          callback lines.join "\n"
        else
          tmpFilePath = "#{tmpDirPath}/#{path.basename filePath}"
          fs.readFile tmpFilePath, (err, data) ->
            fs.unlink tmpFilePath
            if err
              callback err, null
            else
              callback null, data

  put: (remoteFilePath, fileBuffer, callback) ->
    tmp.dir (err, tmpDirPath) =>
      tmpFilePath = "#{tmpDirPath}/tempfile"
      fs.writeFile tmpFilePath, fileBuffer, (err) =>
        if err
          callback err
        else
          this.runCommand "put #{tmpFilePath} #{remoteFilePath}", (data) ->
            lines = data.split "\n"
            lines.shift()
            lines.pop()
            fs.unlink tmpFilePath
            if /^Uploading\s/.test lines[0]
              callback null
            else
              callback lines.join "\n"

  rm: (filePath, callback) ->
    this.runCommand "rm #{filePath}", (data) ->
      lines = data.split "\n"
      if lines.length == 3 && lines[2] == 'sftp> ' && /^Removing\s/.test lines[1]
        callback null
      else
        lines.shift()
        lines.pop()
        callback lines.join "\n"
