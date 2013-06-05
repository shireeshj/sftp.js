SFTP = require '../../lib/sftp'
_ = require 'underscore'
fs = require 'fs'
childProcess = require 'child_process'
tmp = require 'tmp'
pty = require 'pty.js'
fs = require 'fs'
path = require 'path'
EventEmitter = require('events').EventEmitter
CommandQueue = require '../../lib/command_queue'

describe 'SFTP', ->
  @timeout 5000
  sftp = null
  privateKey = null
  testDir = null

  beforeEach ->
    privateKey = fs.readFileSync '/home/action/.ssh/nopass_id_rsa', 'utf8'
    testDir = path.resolve(__dirname, "..")
    sftp = new SFTP host: 'localhost', port: 65100, user: 'action', key: privateKey

  it 'stores the login information in ivars', ->
    expect(sftp.host).to.equal 'localhost'
    expect(sftp.port).to.equal 65100
    expect(sftp.user).to.equal 'action'
    expect(sftp.key).to.equal privateKey

  describe '.escape', ->
    context 'when given a string', ->
      it 'replaces single quotes with single quotes surrounded by double quotes surrounded by single quotes and encloses the entire string in single quotes', ->
        expect(SFTP.escape "3'o clock at harry's").to.equal "'3'\"'\"'o clock at harry'\"'\"'s'"

    context 'when given a non-string object', ->
      it 'returns null', ->
        expect(SFTP.escape()).to.be.null
        expect(SFTP.escape null).to.be.null
        expect(SFTP.escape undefined).to.be.null
        expect(SFTP.escape true).to.be.null
        expect(SFTP.escape 123).to.be.null
        expect(SFTP.escape {}).to.be.null

  describe '#connect', ->
    it 'establish ssh and sftp connection', (done) ->
      sftp.connect (err) ->
        expect(sftp.ssh).not.to.be.nil
        expect(sftp.sftp).not.to.be.nil
        expect(sftp.ready).to.be.true
        sftp.output "whoami", (err, output) ->
          expect(output).to.eql "action\n"
          done()

    context 'when failed to connect', ->
      beforeEach ->
        sftp.user = 'invalid-user'

      it 'returns an error', (done) ->
        sftp.connect (err) ->
          expect(err).not.to.be.nil
          done()

  describe '#ls', ->
    beforeEach (done) -> sftp.connect -> done()

    it 'parses the output and generates an array of directories and files', (done) ->
      sftp.ls testDir, (err, data) ->
        expect(data).to.eql [
          ['fixtures', true, 4096],
          ['lib', true, 4096],
          ['mocha.opts', false, 92],
          ['spec_helper.coffee', false, 431],
        ]
        done()

    context 'when no such file or directory', ->
      it 'returns an error', (done) ->
        sftp.ls testDir + "/hahaha", (err, data) ->
          expect(err).to.be.an.instanceOf Error
          expect(err.message).to.equal "ls: cannot access #{testDir}/hahaha: No such file or directory\n"
          done()

  describe '#mkdir', ->
    beforeEach (done) -> sftp.connect -> done()

    it 'creates a new directory', (done) ->
      sftp.mkdir '/tmp/hello', (err) ->
        expect(fs.existsSync('/tmp/hello')).to.be.true
        fs.rmdirSync '/tmp/hello'
        done()

    context 'when it can not create a new directory', ->
      it 'returns an error', (done) ->
        sftp.mkdir '/whatever', (err) ->
          expect(err).to.be.an.instanceOf Error
          expect(err.message).to.eql "Permission denied"
          done()

  describe '#rmdir', ->
    beforeEach (done) ->
      fs.mkdirSync "/tmp/hello"
      sftp.connect -> done()

    it 'removes the directory', (done) ->
      sftp.rmdir '/tmp/hello', (err) ->
        expect(fs.existsSync('/tmp/hello')).to.be.false
        done()

    context 'when it can not remove the directory', ->
      it 'returns an error', (done) ->
        sftp.rmdir '/haha-failed', (err) ->
          expect(err).to.be.an.instanceOf Error
          expect(err.message).to.eql "No such file"
          done()

  describe '#get', ->
    beforeEach (done) ->
      sftp.connect -> done()

    it 'gets the content and file type given a file path', (done) ->
      sftp.get testDir + "/fixtures/test.txt", (err, data, fileType) ->
        expect(data.toString()).to.eql "This is a test file\n"
        expect(fileType).to.eql "ASCII text\n"
        done()

    context 'when trying to read a non-existing file', ->
      it 'returns an error', (done) ->
        sftp.get testDir + "/fixtures/invalid-file.txt", (err, data, fileType) ->
          expect(err).to.be.an.instanceOf Error
          expect(err.message).to.eql("No such file")
          done()

  describe '#put', ->
    localPath = null
    remotePath = null

    beforeEach (done) ->
      localPath = testDir + "/fixtures/test.txt"
      remotePath = testDir + "/fixtures/tmp.txt"
      sftp.connect -> done()

    afterEach (done) ->
      fs.unlink remotePath, -> done()

    it 'put the local file to a remote destination', (done) ->
      sftp.put localPath, remotePath, (err) ->
        expect(err).to.be.nil
        expect(fs.readFileSync(localPath)).to.eql(fs.readFileSync(remotePath))
        done()

    context 'when the local path does not exist', ->
      beforeEach -> localPath = testDir + "/fixtures/hahawathever"

      it 'returns error', (done) ->
        sftp.put localPath, remotePath, (err) ->
          expect(err).to.be.an.instanceOf Error
          expect(err.message).to.include "ENOENT"
          expect(fs.existsSync(remotePath)).to.be.false
          done()

    context 'when the local path is not a file', ->
      beforeEach -> localPath = testDir

      it 'returns error', (done) ->
        sftp.put localPath, remotePath, (err) ->
          expect(err).to.be.an.instanceOf Error
          expect(fs.existsSync(remotePath)).to.be.false
          expect(err.message).to.eql "local path does not point to a file"
          done()

  describe '#putData', ->
    remotePath = null

    beforeEach (done) ->
      remotePath = testDir + "/fixtures/tmp.txt"
      sftp.connect -> done()

    afterEach (done) ->
      fs.unlink remotePath, -> done()

    it 'writes the content to the remote destination', (done) ->
      sftp.putData remotePath, "tmp content", (err) ->
        expect(err).to.be.nil
        expect(fs.readFileSync(remotePath).toString()).to.eql "tmp content"
        done()

    context "when the remote path is not writable", ->
      beforeEach -> remotePath = testDir + "/fixtures"

      it 'returns an error', (done) ->
        sftp.putData remotePath, "tmp content", (err) ->
          expect(err).to.be.an.instanceOf Error
          done()

  describe '#destroy', ->
    it 'ends the ssh connection', ->

  #describe '#rm', ->
  #  cbSpy = null

  #  beforeEach ->
  #    cbSpy = sinon.spy()
  #    sinon.stub sftp, '_runCommand'

  #  it 'calls _runCommand with rm command', ->
  #    sftp.rm 'remote-file', cbSpy
  #    expect(sftp._runCommand).to.have.been.calledWith "rm 'remote-file'"

  #  context 'when _runCommand succeeds', ->
  #    beforeEach ->
  #      output = '''
  #        rm remote-file
  #        Removing remote-file
  #      ''' + '\nsftp> '
  #      sftp._runCommand.callsArgWith 1, output

  #    it 'returns no errors', (done) ->
  #      sftp.rm 'remote-file', (err) ->
  #        expect(err).not.to.exist
  #        done()

  #  context 'when _runCommand fails with bad path', ->
  #    beforeEach ->
  #      output = '''
  #        rm unknown-file
  #        Couldn't stat remote file: No such file or directory
  #        Removing /home/foo/unknown-file
  #        Couldn't delete file: No such file or directory
  #      ''' + '\nsftp> '
  #      sftp._runCommand.callsArgWith 1, output

  #    it 'returns an error', (done) ->
  #      sftp.rm 'unknown-file', (err) ->
  #        expect(err).to.be.an.instanceOf Error
  #        expect(err.message).to.equal '''
  #          Couldn't stat remote file: No such file or directory
  #          Removing /home/foo/unknown-file
  #          Couldn't delete file: No such file or directory
  #        '''
  #        done()

  #  context 'when _runCommand fails with bad path', ->
  #    beforeEach ->
  #      output = '''
  #        rm unknown-file
  #        Failed to remove /home/foo/unknown-file
  #      ''' + '\nsftp> '
  #      sftp._runCommand.callsArgWith 1, output

  #    it 'returns an error', (done) ->
  #      sftp.rm 'unknow-file', (err) ->
  #        expect(err).to.be.an.instanceOf Error
  #        expect(err.message).to.equal '''
  #          Failed to remove /home/foo/unknown-file
  #        '''
  #        done()

  #  context 'when there are some other types of error', ->
  #    beforeEach ->
  #      output = '''
  #        rm remote-file
  #        Removing /home/foo/unknown-file
  #        some random
  #        error message
  #      ''' + '\nsftp> '
  #      sftp._runCommand.callsArgWith 1, output

  #    it 'returns an error', (done) ->
  #      sftp.rm 'remote-file', (err) ->
  #        expect(err).to.be.an.instanceOf Error
  #        expect(err.message).to.equal '''
  #          Removing /home/foo/unknown-file
  #          some random
  #          error message
  #        '''
  #        done()

  #describe '#rename', ->
  #  cbSpy = null

  #  beforeEach ->
  #    cbSpy = sinon.spy()
  #    sinon.stub sftp, '_runCommand'

  #  it 'calls _runCommand with mv command', ->
  #    sftp.rename 'path/current', 'path/new', cbSpy
  #    expect(sftp._runCommand).to.have.been.calledWith "rename 'path/current' 'path/new'"

  #  context 'when _runCommand succeeds', ->
  #    beforeEach ->
  #      output = '''
  #        rename path/current path/new 
  #      ''' + '\nsftp> '
  #      sftp._runCommand.callsArgWith 1, output

  #    it 'returns no errors', (done) ->
  #      sftp.rename 'path/current', 'path/new', (err) ->
  #        expect(err).not.to.exist
  #        done()

  #  context 'when _runCommand fails with bad path', ->
  #    beforeEach ->
  #      output = '''
  #        rename path/current path/new 
  #        Couldn't rename file "path/current" to "path/new": No such file or directory
  #      ''' + '\nsftp> '
  #      sftp._runCommand.callsArgWith 1, output

  #    it 'returns an error', (done) ->
  #      sftp.rename 'path/current', 'path/new', (err) ->
  #        expect(err).to.be.an.instanceOf Error
  #        expect(err.message).to.equal 'Couldn\'t rename file "path/current" to "path/new": No such file or directory'
  #        done()

  #  context 'when there are some other types of error', ->
  #    beforeEach ->
  #      output = '''
  #        rename path/current path/new
  #        some random
  #        error message
  #      ''' + '\nsftp> '
  #      sftp._runCommand.callsArgWith 1, output

  #    it 'returns an error', (done) ->
  #      sftp.rename 'path/current', 'path/new', (err) ->
  #        expect(err).to.be.an.instanceOf Error
  #        expect(err.message).to.equal '''
  #          some random
  #          error message
  #        '''
  #        done()
