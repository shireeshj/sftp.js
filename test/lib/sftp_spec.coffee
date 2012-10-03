SFTP = require '../../lib/sftp'
fs = require 'fs'
tmp = require 'tmp'
pty = require 'pty.js'
EventEmitter = require('events').EventEmitter

describe 'SFTP', ->
  sftp = null

  beforeEach ->
    sftp = new SFTP host: 'localhost', port: 2222, user: 'peter', key: 'some rsa private key'

  it 'stores the login information in ivars', ->
    expect(sftp.host).to.equal 'localhost'
    expect(sftp.port).to.equal 2222
    expect(sftp.user).to.equal 'peter'
    expect(sftp.key).to.equal 'some rsa private key'

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
          sinon.stub sftp, 'onPTYData'
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

          context 'data', ->
            it 'is handled by #onPTYData', ->
              mockPty.emit 'data'
              expect(sftp.onPTYData).to.have.been.called

          context 'close', ->
            it 'is handled by #onPTYClose', ->
              mockPty.emit 'close'
              expect(sftp.onPTYClose).to.have.been.called

  describe '#ls', ->
    context 'when the path is invalid', ->
      it 'should return an empty array', ->
        sftp.ls '', (err, fileList) ->
          expect(err).to.eql(null)
          expect(fileList).to.deep.equal([])

    context 'when there are no files or directories in the current directory', ->
      it 'should return an empty array', ->

    context 'when there are only files in the current directory', ->
      it 'should return the files in an array'

    context 'when there are only directories in the current directory', ->
      it 'should return the directories in an array'

    context 'when there are files and directories in the current directory', ->
      it 'should return the files and directories in an array'
