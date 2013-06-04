_ = require 'underscore'
fs = require 'fs'
path = require 'path'
tmp = require 'tmp'
pty = require 'pty.js'
childProcess = require 'child_process'
CommandQueue = require './command_queue'
Connection = require 'ssh2'

module.exports = class SFTP
  constructor: (login) ->
    @host = login.host
    @port = login.port
    @user = login.user
    @key = login.key
    @ssh = new Connection()
    @ready = false

  destroy: ->
    @ssh = new Connection()
    @sftp = null
    @ready = false

  connect: (callback) -> # callback(err)
    @ssh.connect host: @host, port: @port, username: @user, privateKey: @key
    @ssh.on 'error', (err) -> callback? err
    @ssh.on 'end', => @destroy()
    @ssh.on 'ready', =>
      @ssh.sftp (err, sftp) =>
        return callback?(err) if err
        @ready = true
        @sftp = sftp
        callback?()

  ls: (filePath, callback) ->
    return callback?(new Error("NotReady")) unless @ready
    this.output "ls -la #{@constructor.escape filePath}", (err, data, code, signal) ->
      return callback?(new Error(data)) if code != 0

      lines = data.split "\n"
      lines.shift()
      lines.pop()
      files = []
      errors = null
      for line in lines
        if !errors && (match = line.match /^\s*([a-z\-])([rwx\-]+)\s+([\d]+)\s+([\w]+)\s+([\w]+)\s+([\d]+)\s+([\w\s\d]+)([\d]{2}\:?[\d]{2})\s+(.*)$/)
          name = match[9]
          if name != '.' && name != '..'
            isDir = match[1] == 'd'
            fileSize = parseInt match[6], 10
            files.push [name, isDir, fileSize]
        else
          files = null
          errors ?= []
          errors.push line
      errors = new Error(errors.join '\n') if errors
      callback errors, files

  mkdir: (dirPath, callback) ->
    return callback?(new Error("NotReady")) unless @ready
    @sftp.mkdir dirPath, callback

  rmdir: (dirPath, callback) ->
    return callback?(new Error("NotReady")) unless @ready
    @sftp.rmdir dirPath, callback

  get: (filePath, callback) ->
    tmp.file (err, tmpFilePath, fd) =>
      fs.close(fd) if fd
      return callback err if err
      @sftp.fastGet filePath, tmpFilePath, (err) =>
        if err
          fs.unlink tmpFilePath
          return callback(err) if err
        childProcess.exec "file -b #{@constructor.escape tmpFilePath}", (err, fileType) ->
          if err
            fs.unlink tmpFilePath
            return callback err
          fs.readFile tmpFilePath, (err, data) ->
            fs.unlink tmpFilePath
            return callback err if err
            callback null, data, fileType

#  _runPutCommand: (localPath, remotePath, deleteAfterPut, callback) ->
#    this._runCommand "put #{@constructor.escape localPath} #{@constructor.escape remotePath}", (data) ->
#      lines = data.split "\n"
#      lines.shift()
#      lines.pop()
#      fs.unlink localPath if deleteAfterPut
#      if /^Uploading\s/.test lines.slice(-1)
#        callback()
#      else
#        callback new Error(lines.join "\n")

#  put: (localPath, remotePath, callback) ->
#    fs.stat localPath, (err, stats) =>
#      if err
#        callback err
#        return
#      unless stats.isFile()
#        callback new Error('local path does not point to a file')
#        return
#      this._runPutCommand localPath, remotePath, false, callback

#  putData: (remotePath, contentData, callback) ->
#    tmp.file (err, tmpFilePath, fd) =>
#      fs.close(fd) if fd
#      if err
#        callback err
#        return
#      fs.writeFile tmpFilePath, contentData, (err) =>
#        if err
#          callback err
#          return
#        this._runPutCommand tmpFilePath, remotePath, true, callback

#  rm: (filePath, callback) ->
#    this._runCommand "rm #{@constructor.escape filePath}", (data) ->
#      lines = data.split "\n"
#      lines.shift()
#      lines.pop()
#      if /^Removing\s/.test lines.slice(-1)
#        callback()
#      else
#        callback new Error(lines.join "\n")

#  rename: (filePath, newFilePath, callback) ->
#    this._doBlankResponseCmd 'rename', filePath, newFilePath, callback

  output: (cmd, callback) ->
    return callback?(new Error("NotReady")) unless @ready
    @ssh.exec cmd, (err, stream) ->
      return callback?(err) if err
      data = ""
      stream.on 'data', (d) => data += d.toString()
      stream.on 'exit', (code, signal) -> callback?(null, data, code, signal)

  @escape: (string) ->
    if typeof string == 'string'
      return "'" + string.replace(/\'/g, "'\"'\"'") + "'"
    null

#module.exports = class SFTP

#  _writeKeyFile: (callback) -> # callback(err, sshArgs, deleteKeyFile)
#    tmp.file (err, path, fd) =>
#      fs.close(fd) if fd
#      if err
#        callback err
#        return
#      keyBuf = new Buffer @key
#      fs.writeFile path, keyBuf, (err, written, buffer) =>
#        if err
#          fs.unlink path, -> callback(err)
#          return
#        sshArgs = [
#          '-i', path
#          '-o', 'UserKnownHostsFile=/dev/null'
#          '-o', 'StrictHostKeyChecking=no'
#          '-o', 'PubkeyAuthentication=yes'
#          '-o', 'PasswordAuthentication=no'
#          '-o', 'LogLevel=FATAL'
#          '-P', "#{@port}"
#          '-q'
#          "#{@user}@#{@host}"
#        ]
#        deleteKeyFile = (callback) ->
#          fs.unlink path, ->
#            callback?()
#        callback null, sshArgs, deleteKeyFile

#  _bufferDataUntilPrompt: (callback) ->
#    buffer = ''
#    dataListener = (data) =>
#      data = data.replace /\r/g, ''
#      buffer += data
#      if data.match /(^|\n)sftp> $/
#        @pty.removeListener 'data', dataListener
#        callback buffer
#    @pty.on 'data', dataListener

#  connect: (callback) -> # callback(err)
#    this._writeKeyFile (err, sshArgs, deleteKeyFile) =>
#      if err
#        callback? err
#        return
#      try
#        @pty = pty.spawn '/usr/bin/sftp', sshArgs
#      catch err
#        deleteKeyFile ->
#          callback? err
#        return
#      this._bufferDataUntilPrompt =>
#        @queue = new CommandQueue
#        deleteKeyFile()
#        callback?()
#      @pty.on 'close', _.bind(@_onPTYClose, this)

#  _onPTYClose: (hadError) ->
#    this.destroy()

#  destroy: (callback) ->
#    if @queue
#      @queue.enqueue =>
#        @pty.removeAllListeners()
#        @pty.write "bye\n"
#        @pty.destroy()
#        delete @queue
#        delete @pty
#        callback?()
#    else
#      callback?()

#  _runCommand: (command, callback) ->
#    @queue?.enqueue =>
#      this._bufferDataUntilPrompt (data) =>
#        callback data
#        @queue.dequeue()
#      @pty.write command + "\n"



#  ls: (filePath, callback) ->
#    this._runCommand "ls -la #{@constructor.escape filePath}", (data) ->
#      lines = data.split "\n"
#      lines.shift()
#      lines.pop()
#      files = []
#      errors = null
#      for line in lines
#        if !errors && (match = line.match /^\s*([a-z\-])([rwx\-]+)\s+([\d]+)\s+([\w]+)\s+([\w]+)\s+([\d]+)\s+([\w\s\d]+)([\d]{2}\:?[\d]{2})\s+(.*)$/)
#          name = match[9]
#          if name != '.' && name != '..'
#            isDir = match[1] == 'd'
#            fileSize = parseInt match[6], 10
#            files.push [name, isDir, fileSize]
#        else
#          files = null
#          errors ?= []
#          errors.push line
#      errors = new Error(errors.join '\n') if errors
#      callback errors, files

#  _doBlankResponseCmd: (command, paths..., callback) ->
#    escapedPaths = []
#    escapedPaths.push @constructor.escape(path) for path in paths
#    this._runCommand "#{command} #{escapedPaths.join(' ')}", (data) ->
#      lines = data.split "\n"
#      if lines.length == 2
#        callback()
#      else
#        lines.shift()
#        lines.pop()
#        callback new Error(lines.join "\n")


