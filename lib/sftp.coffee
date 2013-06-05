_ = require 'underscore'
fs = require 'fs'
path = require 'path'
tmp = require 'tmp'
childProcess = require 'child_process'
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
    @ssh.end()
    @ssh = new Connection()
    @sftp = null
    @ready = false

  connect: (callback) -> # callback(err)
    @ssh.connect host: @host, port: @port, username: @user, privateKey: @key
    @ssh.on 'error', (err) =>
      this.destroy()
      callback? err
    @ssh.on 'ready', =>
      @ssh.sftp (err, sftp) =>
        return callback?(err) if err
        @ready = true
        @sftp = sftp
        callback?()

  ls: (filePath, callback) ->
    return callback?(new Error("NotReady")) unless @ready
    filePath = if filePath == "" then "~" else @constructor.escape filePath
    this.output "ls -la #{filePath}", (err, data, code, signal) ->
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
    return callback?(new Error("NotReady")) unless @ready
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

  put: (localPath, remotePath, callback) ->
    return callback?(new Error("NotReady")) unless @ready
    fs.stat localPath, (err, stats) =>
      return callback(err) if err
      return callback(new Error("local path does not point to a file")) unless stats.isFile()
      @sftp.fastPut localPath, remotePath, callback

  putData: (remotePath, content, callback) ->
    return callback?(new Error("NotReady")) unless @ready
    @sftp.writeFile remotePath, content, callback

  rm: (remotePath, callback) ->
    return callback?(new Error("NotReady")) unless @ready
    @sftp.unlink remotePath, callback

  rename: (remotePath, newRemotePath, callback) ->
    return callback?(new Error("NotReady")) unless @ready
    @sftp.rename remotePath, newRemotePath, callback

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
