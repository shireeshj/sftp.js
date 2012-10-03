SFTP = require '../../lib/sftp'
fs = require 'fs'
tmp = require 'tmp'
pty = require 'pty.js'
EventEmitter = require('events').EventEmitter
CommandQueue = require '../../lib/command_queue'

describe 'SFTP', ->
  sftp = null

  beforeEach ->
    sftp = new SFTP host: 'localhost', port: 2222, user: 'peter', key: 'some rsa private key'

  it 'stores the login information in ivars', ->
    expect(sftp.host).to.equal 'localhost'
    expect(sftp.port).to.equal 2222
    expect(sftp.user).to.equal 'peter'
    expect(sftp.key).to.equal 'some rsa private key'

  it 'initializes a command queue', ->
    expect(sftp.queue).to.be.an.instanceOf CommandQueue

  describe '#writeKeyFile', ->
    err = cbSpy = null

    context 'when temp file failed to get created', ->
      beforeEach ->
        err = new Error
        sinon.stub tmp, 'file', (cb) ->
          cb(err)
        cbSpy = sinon.spy()
        sftp.writeKeyFile cbSpy

      afterEach ->
        tmp.file.restore()

      it 'makes a callback with the error', ->
        expect(cbSpy).to.have.been.calledWith err

    context 'when temp file is successfully created', ->
      fakeFd = null

      beforeEach ->
        err = new Error
        fakeFd = {}
        sinon.stub tmp, 'file', (cb) ->
          cb null, '/tmp/tmpfile', fakeFd
        sinon.stub fs, 'unlink', (path, cb) ->
          cb()

      afterEach ->
        tmp.file.restore()
        fs.unlink.restore()

      context 'when the key failed to be written to the temp file', ->
        beforeEach ->
          fs.write = sinon.stub fs, 'write', (fd, buf, offset, len, pos, cb) ->
            expect(fd).to.equal fakeFd
            cb err
          cbSpy = sinon.spy()
          sftp.writeKeyFile cbSpy
          expect(fs.write).to.have.been.called

        afterEach ->
          fs.write.restore()

        it 'deletes the temp file', ->
          expect(fs.unlink).to.have.been.called
          expect(fs.unlink.args[0][0]).to.equal '/tmp/tmpfile'

        it 'makes a callback with the error', ->
          expect(cbSpy).to.have.been.calledWith err

      context 'when the key is successfully written to the temp file', ->
        beforeEach ->
          fs.write = sinon.stub fs, 'write', (fd, buf, offset, len, pos, cb) ->
            expect(fd).to.equal fakeFd
            cb()
          cbSpy = sinon.spy()
          sftp.writeKeyFile cbSpy
          expect(fs.write).to.have.been.called

        afterEach ->
          fs.write.restore()

        it 'makes a callback with ssh arguments as the first argument', ->
          expect(cbSpy).to.have.been.called
          sshArgs = cbSpy.args[0][1].join ' '
          expect(sshArgs).to.match /^-i \/tmp\/tmpfile/
          expect(sshArgs).to.match /-o UserKnownHostsFile=\/dev\/null/
          expect(sshArgs).to.match /-o StrictHostKeyChecking=no/
          expect(sshArgs).to.match /-o PubkeyAuthentication=yes/
          expect(sshArgs).to.match /-o PasswordAuthentication=no/
          expect(sshArgs).to.match /-o LogLevel=FATAL/
          expect(sshArgs).to.match /-P 2222/
          expect(sshArgs).to.match /peter@localhost/

        describe 'deleteKeyFile function', ->
          context 'with a callback', ->
            it 'deletes the temp key file and then calls the callback', (done) ->
              expect(cbSpy).to.have.been.called
              cbSpy.args[0][2] ->
                expect(fs.unlink).to.have.been.called
                expect(fs.unlink.args[0][0]).to.equal '/tmp/tmpfile'
                done()

          context 'without a callback', ->
            it 'deletes the temp key file', ->
              expect(cbSpy).to.have.been.called
              cbSpy.args[0][2]()
              expect(fs.unlink).to.have.been.called
              expect(fs.unlink.args[0][0]).to.equal '/tmp/tmpfile'

  describe '#connect', ->
    err = cbSpy = null

    context 'when writeKeyFile fails with error', ->
      beforeEach ->
        err = new Error
        cbSpy = sinon.spy()
        sinon.stub sftp, 'writeKeyFile', (callback) ->
          callback(err)

        sftp.connect cbSpy
        expect(sftp.writeKeyFile).to.have.been.called

      it 'makes a callback with the error', ->
        expect(cbSpy).to.have.been.calledWith err

    context 'when writeKeyFile succeeds', ->
      deleteKeyFileSpy = doAction = null

      beforeEach ->
        deleteKeyFileSpy = sinon.spy (cb) -> cb?()
        cbSpy = sinon.spy()
        sinon.stub sftp, 'writeKeyFile', (callback) ->
          callback null, ['sshArg1', 'sshArg2'], deleteKeyFileSpy

        doAction = ->
          sftp.connect cbSpy
          expect(sftp.writeKeyFile).to.have.been.called

      context 'when spawning a new pty fails with exception', ->
        error = null

        beforeEach ->
          error = new Error 'pty error'
          sinon.stub pty, 'spawn', (cmd, args) ->
            throw error
          doAction()

        afterEach ->
          pty.spawn.restore()

        it 'deletes the key file', ->
          expect(deleteKeyFileSpy).to.have.been.called

        it 'calls callback with error', ->
          expect(cbSpy).to.have.been.calledWith error

      context 'when spawning a new pty succeeds', ->
        mockPty = null

        beforeEach ->
          mockPty = new EventEmitter()
          sinon.stub sftp, 'onPTYClose'
          sinon.stub pty, 'spawn', (cmd, args) ->
            expect(cmd).to.equal '/usr/bin/sftp'
            expect(args).to.deep.equal ['sshArg1', 'sshArg2']
            mockPty
          doAction()

        afterEach ->
          pty.spawn.restore()

        it 'calls callback with no error', ->
          expect(cbSpy).to.have.been.calledWith null

        describe 'pty events', ->
          context "the first time 'data' event is received", ->
            it 'deletes they key file', ->
              expect(deleteKeyFileSpy).not.to.have.been.called
              mockPty.emit 'data'
              expect(deleteKeyFileSpy).to.have.been.calledOnce
              mockPty.emit 'data'
              expect(deleteKeyFileSpy).to.have.been.calledOnce # only gets called once

          context 'close', ->
            it 'is handled by #onPTYClose', ->
              mockPty.emit 'close'
              expect(sftp.onPTYClose).to.have.been.called

  describe '#runCommand', ->
    cbSpy = null

    beforeEach ->
      cbSpy = sinon.spy()
      sftp.pty = new EventEmitter
      sftp.pty.write = ->

    it 'enqueues a function', ->
      sftp.runCommand 'ls', cbSpy
      expect(sftp.queue.items).to.have.length 1

    describe 'the enqueued function', ->
      beforeEach ->
        sinon.stub sftp.queue, 'dequeue'
        sinon.stub sftp.pty, 'write'
        sftp.runCommand 'ls -l', cbSpy

      it 'creates a event handler for "data" event on @pty that buffers' +
         'the output from the server and then makes a callback and dequeues' +
         'the command queue when it is done', ->
        expect(cbSpy).not.to.have.been.called
        expect(sftp.queue.dequeue).not.to.have.been.called
        sftp.pty.emit 'data', 'ls'
        sftp.pty.emit 'data', " -l\r\n"
        sftp.pty.emit 'data', "foo\r\n"
        sftp.pty.emit 'data', "bar\r\nbaz"
        sftp.pty.emit 'data', "\r\nqux\r\nsftp> "
        expect(cbSpy).to.have.been.calledOnce
        expect(cbSpy).to.have.been.calledWith '''
          ls -l
          foo
          bar
          baz
          qux
        ''' + "\nsftp> "
        expect(sftp.queue.dequeue).to.have.been.calledOnce

      it 'writes the command to @pty', ->
        expect(sftp.pty.write).to.have.been.calledWith "ls -l\n"

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

  describe '#ls', ->
    cbSpy = null

    beforeEach ->
      cbSpy = sinon.spy()
      sinon.stub sftp, 'runCommand'

    it 'calls runCommand with ls command', ->
      sftp.ls 'path/to/dir', cbSpy
      expect(sftp.runCommand).to.have.been.calledWith "ls -l 'path/to/dir'"

    context 'when runCommand succeeds', ->
      beforeEach ->
        output = '''
          ls -l 'path/to/dir'
          -rw-rw-r--    1 ubuntu   ubuntu         63 Oct  2 07:10 Makefile
          -rw-rw-r--    1 ubuntu   ubuntu       1315 Oct  2 09:14 README.md
          -rw-rw-r--    1 ubuntu   ubuntu         67 Oct  2 08:03 index.js
          drwxrwxr-x    2 ubuntu   ubuntu       4096 Oct  3 04:22 lib
          drwxrwxr-x   12 ubuntu   ubuntu       4096 Oct  2 08:08 node_modules
          -rw-rw-r--    1 ubuntu   ubuntu        615 Oct  2 07:10 package.json
          drwxrwxr-x    3 ubuntu   ubuntu       4096 Oct  2 08:04 test
          -rwxrwxr-x    3 ubuntu   ubuntu       4096 Oct  2 08:04 test file
        ''' + '\nsftp> '
        sftp.runCommand.callsArgWith 1, output

      it 'parses the output and generates an array of directories and files', (done) ->
        sftp.ls 'path/to/dir', (err, data) ->
          expect(err).not.to.exist
          expect(data).to.deep.equal [
            [ 'Makefile',    false ]
            [ 'README.md',   false ]
            [ 'index.js',    false ]
            [ 'lib',         true  ]
            [ 'node_modules',true  ]
            [ 'package.json',false ]
            [ 'test',        true  ]
            [ 'test file',   false ]
          ]
          done()

    context 'when runCommand fails', ->
      beforeEach ->
        output = '''
          ls -l '/path/to/dir'
          Couldn't stat remote file: No such file or directory
          Can't ls: "/home/ubuntu/path/to/dir" not found
        ''' + '\nsftp> '
        sftp.runCommand.callsArgWith 1, output

      it 'returns an error', (done) ->
        sftp.ls '/path/to/dir', (err, data) ->
          expect(err).to.equal '''
            Couldn't stat remote file: No such file or directory
            Can't ls: "/home/ubuntu/path/to/dir" not found
          '''
          done()
