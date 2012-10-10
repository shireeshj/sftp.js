_ = require 'underscore'
fs = require 'fs'
path = require 'path'
tmp = require 'tmp'
pty = require 'pty.js'
childProcess = require 'child_process'
CommandQueue = require './command_queue'

module.exports = class SFTP
  constructor: (login) ->
    @host = login.host
    @port = login.port
    @user = login.user
    @key = login.key

  writeKeyFile: (callback) -> # callback(err, sshArgs, deleteKeyFile)
    tmp.file (err, path, fd) =>
      if err
        callback err
        return
      keyBuf = new Buffer @key
      fs.writeFile path, keyBuf, (err, written, buffer) =>
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

  bufferDataUntilPrompt: (callback) ->
    buffer = ''
    dataListener = (data) =>
      data = data.replace /\r/g, ''
      buffer += data
      if data.match /(^|\n)sftp> $/
        @pty.removeListener 'data', dataListener
        callback buffer
    @pty.on 'data', dataListener

  connect: (callback) -> # callback(err)
    this.writeKeyFile (err, sshArgs, deleteKeyFile) =>
      if err
        callback? err
        return
      try
        @pty = pty.spawn '/usr/bin/sftp', sshArgs
      catch err
        deleteKeyFile ->
          callback? err
        return
      this.bufferDataUntilPrompt =>
        @queue = new CommandQueue
        deleteKeyFile()
        callback?()
      @pty.on 'close', _.bind(@onPTYClose, this)

  onPTYClose: (hadError) ->
    this.destroy()

  destroy: (callback) ->
    if @queue
      @queue.enqueue =>
        @pty.removeAllListeners()
        @pty.write "bye\n"
        @pty.destroy()
        delete @queue
        delete @pty
        callback?()
    else
      callback?()

  runCommand: (command, callback) ->
    @queue?.enqueue =>
      this.bufferDataUntilPrompt (data) =>
        callback data
        @queue.dequeue()
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
          fileSize = parseInt match[5], 10
          name = match[8]
          isDir = line[0] == 'd'
          files.push [name, isDir, fileSize]
        else
          files = null
          errors ?= []
          errors.push line
      errors = errors.join '\n' if errors
      callback errors, files

  doBlankResponseCmd: (command, dirPath, callback) ->
    this.runCommand "#{command} #{@constructor.escape dirPath}", (data) ->
      lines = data.split "\n"
      if lines.length == 2
        callback()
      else
        lines.shift()
        lines.pop()
        callback lines.join "\n"

  mkdir: (dirPath, callback) ->
    this.doBlankResponseCmd 'mkdir', dirPath, callback

  rmdir: (dirPath, callback) ->
    this.doBlankResponseCmd 'rmdir', dirPath, callback

  get: (filePath, callback) ->
    tmp.dir (err, tmpDirPath) =>
      this.runCommand "get #{@constructor.escape filePath} #{@constructor.escape tmpDirPath}", (data) ->
        lines = data.split "\n"
        if lines.length != 3
          lines.shift()
          lines.pop()
          callback lines.join "\n"
        else
          tmpFilePath = "#{tmpDirPath}/#{path.basename filePath}"
          childProcess.exec "file #{tmpFilePath}", (err, fileType) ->
            if err
              fs.unlink tmpFilePath
              callback err
            else
              fs.readFile tmpFilePath, (err, data) ->
                fs.unlink tmpFilePath
                if err
                  callback err
                else
                  callback null, data, fileType

  put: (remoteFilePath, fileBuffer, callback) ->
    tmp.file (err, tmpFilePath) =>
      if err
        callback err
        return
      fs.writeFile tmpFilePath, fileBuffer, (err) =>
        if err
          callback err
          return
        this.runCommand "put #{@constructor.escape tmpFilePath} #{@constructor.escape remoteFilePath}", (data) ->
          lines = data.split "\n"
          lines.shift()
          lines.pop()
          fs.unlink tmpFilePath
          if /^Uploading\s/.test lines[0]
            callback()
          else
            callback lines.join "\n"

  rm: (filePath, callback) ->
    this.runCommand "rm #{@constructor.escape filePath}", (data) ->
      lines = data.split "\n"
      if lines.length == 3 && lines[2] == 'sftp> ' && /^Removing\s/.test lines[1]
        callback()
      else
        lines.shift()
        lines.pop()
        callback lines.join "\n"
