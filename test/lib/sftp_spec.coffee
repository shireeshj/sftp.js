SFTP = require '../../lib/sftp'
_ = require 'underscore'
fs = require 'fs'
childProcess = require 'child_process'
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

  describe '#writeKeyFile', ->
    err = cbSpy = null

    context 'when temp file failed to get created', ->
      beforeEach ->
        err = new Error
        cbSpy = sinon.spy()
        sinon.stub tmp, 'file'
        tmp.file.yields err
        sftp.writeKeyFile cbSpy

      afterEach ->
        tmp.file.restore()

      it 'makes a callback with the error', ->
        expect(cbSpy).to.have.been.calledWith err

    context 'when temp file is successfully created', ->
      beforeEach ->
        err = new Error
        sinon.stub tmp, 'file'
        sinon.stub fs, 'writeFile'
        sinon.stub fs, 'unlink'
        tmp.file.yields null, '/tmp/tmpfile'
        fs.unlink.callsArg 1

      afterEach ->
        tmp.file.restore()
        fs.writeFile.restore()
        fs.unlink.restore()

      it 'writes the key to the temp file', ->
        sftp.writeKeyFile cbSpy
        expect(fs.writeFile).to.have.been.calledWith '/tmp/tmpfile'
        expect(fs.writeFile.args[0][1].toString 'utf8').to.equal sftp.key

      context 'when the key failed to be written to the temp file', ->
        beforeEach ->
          fs.writeFile.callsArgWith 2, err
          cbSpy = sinon.spy()
          sftp.writeKeyFile cbSpy

        it 'deletes the temp file', ->
          expect(fs.unlink).to.have.been.calledWith '/tmp/tmpfile'

        it 'makes a callback with the error', ->
          expect(cbSpy).to.have.been.calledWith err

      context 'when the key is successfully written to the temp file', ->
        beforeEach ->
          fs.writeFile.callsArg 2
          cbSpy = sinon.spy()
          sftp.writeKeyFile cbSpy

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
          expect(sshArgs).to.match /-q/
          expect(sshArgs).to.match /peter@localhost/

        describe 'deleteKeyFile function', ->
          context 'with a callback', ->
            it 'deletes the temp key file and then calls the callback', (done) ->
              expect(cbSpy).to.have.been.called
              cbSpy.args[0][2] ->
                expect(fs.unlink).to.have.been.calledWith '/tmp/tmpfile'
                done()

          context 'without a callback', ->
            it 'deletes the temp key file', ->
              expect(cbSpy).to.have.been.called
              cbSpy.args[0][2]()
              expect(fs.unlink).to.have.been.calledWith '/tmp/tmpfile'

  describe '#bufferDataUntilPrompt', ->
    cbSpy = null

    beforeEach ->
      cbSpy = sinon.spy()
      sftp.pty = new EventEmitter

    it 'creates a event handler for "data" event on @pty that buffers' +
       'the output from the server until sftp prompt is received', ->
      expect(cbSpy).not.to.have.been.called
      sftp.bufferDataUntilPrompt cbSpy
      sftp.pty.emit 'data', 'ls'
      sftp.pty.emit 'data', " -la\r\n"
      sftp.pty.emit 'data', "foo\r\n"
      sftp.pty.emit 'data', "bar\r\nbaz"
      sftp.pty.emit 'data', "\r\nqux\r\nsftp> "
      expect(cbSpy).to.have.been.called
      expect(cbSpy).to.have.been.calledWith '''
        ls -la
        foo
        bar
        baz
        qux
      ''' + "\nsftp> "

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
          sinon.stub sftp, 'bufferDataUntilPrompt'
          doAction()

        afterEach ->
          pty.spawn.restore()

        context 'before sftp> prompt is received', ->
          it 'does not invoke callback yet', ->
            expect(cbSpy).not.to.have.been.called

          it 'does not initialize a command queue yet', ->
            expect(sftp.queue).not.to.exist

          it 'does not delete the key file yet', ->
            expect(deleteKeyFileSpy).not.to.have.been.called

        context 'after sftp> prompt is received', ->
          beforeEach ->
            sftp.bufferDataUntilPrompt.yield 'sftp> '

          it 'calls callback with no error', ->
            expect(cbSpy).to.have.been.calledWith undefined

          it 'initializes a command queue', ->
            expect(sftp.queue).to.be.an.instanceOf CommandQueue

          it 'deletes the key file', ->
            expect(deleteKeyFileSpy).to.have.been.calledOnce

        context 'pty event close', ->
          it 'is handled by #onPTYClose', ->
            mockPty.emit 'close'
            expect(sftp.onPTYClose).to.have.been.called

  describe '#destroy', ->
    cbSpy = mockPty = null

    context 'when @queue does not exist', ->
      beforeEach ->
        cbSpy = sinon.spy()
        sftp.destroy cbSpy

      it 'just calls callback', ->
        expect(cbSpy).to.have.been.called

    context 'when @queue exists', ->
      beforeEach ->
        sftp.queue = new CommandQueue
        cbSpy = sinon.spy()
        mockPty = sftp.pty = new EventEmitter
        sinon.stub mockPty, 'removeAllListeners'
        _.extend mockPty,
          write: ->
          destroy: ->
        sinon.stub mockPty, 'write'
        sinon.stub mockPty, 'destroy'
        sinon.stub sftp.queue, 'enqueue'
        sftp.queue.enqueue.yields()
        sftp.destroy cbSpy

      it 'removes all listeners on pty', ->
        expect(mockPty.removeAllListeners).to.have.been.called

      it 'writes "bye" command to pty', ->
        expect(mockPty.write).to.have.been.calledWith "bye\n"

      it 'calls #destroy on pty', ->
        expect(mockPty.destroy).to.have.been.called

      it 'deletes the queue and pty', ->
        expect(sftp.queue).not.to.exist
        expect(sftp.pty).not.to.exist

      it 'calls callback', ->
        expect(cbSpy).to.have.been.called

  describe 'onPTYClose', ->
    beforeEach ->
      sinon.stub sftp, 'destroy'
      sftp.onPTYClose()

    it 'calls #destroy', ->
      expect(sftp.destroy).to.have.been.called

  describe '#runCommand', ->
    cbSpy = null

    beforeEach ->
      sftp.queue = new CommandQueue
      cbSpy = sinon.spy()
      sftp.pty = new EventEmitter
      sftp.pty.write = ->

    it 'enqueues a function', ->
      sftp.runCommand 'ls', cbSpy
      expect(sftp.queue.items).to.have.length 1

    context 'when the command queue is deleted', ->
      beforeEach ->
        delete sftp.queue

      it 'does nothing', ->
        sftp.runCommand 'ls', cbSpy

    describe 'the enqueued function', ->
      beforeEach ->
        sinon.stub sftp.queue, 'enqueue'
        sftp.queue.enqueue.yields()
        sinon.stub sftp.queue, 'dequeue'
        sinon.stub sftp.pty, 'write'
        sinon.stub sftp, 'bufferDataUntilPrompt'
        sftp.runCommand 'ls -la', cbSpy

      it 'receives data from data then makes a callback and dequeues the command', ->
        expect(cbSpy).not.to.have.been.called
        expect(sftp.queue.dequeue).not.to.have.been.called
        sftp.bufferDataUntilPrompt.yield '''
          ls -la
          foo bar baz
        ''' + "\nsftp> "
        expect(cbSpy).to.have.been.calledOnce
        expect(cbSpy).to.have.been.calledWith '''
          ls -la
          foo bar baz
        ''' + "\nsftp> "
        expect(sftp.queue.dequeue).to.have.been.calledOnce

      it 'writes the command to @pty', ->
        expect(sftp.pty.write).to.have.been.calledWith "ls -la\n"

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
      expect(sftp.runCommand).to.have.been.calledWith "ls -la 'path/to/dir'"

    context 'when runCommand succeeds', ->
      context 'when the directory is empty', ->
        beforeEach ->
          output = "ls -la 'path/to/dir'\nsftp> "
          sftp.runCommand.callsArgWith 1, output

        it 'parses the output and generates an array of directories and files', (done) ->
          sftp.ls 'path/to/dir', (err, data) ->
            expect(err).not.to.exist
            expect(data).to.deep.equal []
            done()

      context 'when the directory is not empty', ->
        beforeEach ->
          output = '''
            ls -la 'path/to/dir'
            drwxr-xr-x   27 ubuntu   ubuntu       4096 Oct 11 11:49 .
            drwxr-xr-x    3 root     root         4096 Jun 16 13:40 ..
            -rw-r--r--    1 ubuntu   ubuntu       4120 Feb 21  2012 .bashrc
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
              [ '.bashrc',      false, 4120 ]
              [ 'Makefile',     false,   63 ]
              [ 'README.md',    false, 1315 ]
              [ 'index.js',     false,   67 ]
              [ 'lib',          true,  4096 ]
              [ 'node_modules', true,  4096 ]
              [ 'package.json', false,  615 ]
              [ 'test',         true,  4096 ]
              [ 'test file',    false, 4096 ]
            ]
            done()

    context 'when runCommand fails', ->
      context 'no such file or directory error', ->
        beforeEach ->
          output = '''
            ls -la 'path/to/dir'
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

      context 'other errors', ->
        beforeEach ->
          output = '''
            ls -la 'path/to/dir'
            some random
            error message
          ''' + '\nsftp> '
          sftp.runCommand.callsArgWith 1, output

        it 'returns an error', (done) ->
          sftp.ls '/path/to/dir', (err, data) ->
            expect(err).to.equal '''
              some random
              error message
            '''
            done()

  describe '#mkdir', ->
    cbSpy = null

    beforeEach ->
      cbSpy = sinon.spy()
      sinon.stub sftp, 'runCommand'

    it 'calls runCommand with mkdir command', ->
      sftp.mkdir 'tmp', cbSpy
      expect(sftp.runCommand).to.have.been.calledWith "mkdir 'tmp'"

    context 'when runCommand succeeds', ->
      beforeEach ->
        output = '''
          mkdir tmp
        ''' + '\nsftp> '
        sftp.runCommand.callsArgWith 1, output

      it 'returns no errors', (done) ->
        sftp.mkdir 'tmp', (err) ->
          expect(err).not.to.exist
          done()

    context 'when runCommand fails with bad path', ->
      beforeEach ->
        output = '''
          mkdir tmp/bin
          Couldn't create directory: No such file or directory
        ''' + '\nsftp> '
        sftp.runCommand.callsArgWith 1, output

      it 'returns an error', (done) ->
        sftp.mkdir 'tmp/bin', (err) ->
          expect(err).to.equal 'Couldn\'t create directory: No such file or directory'
          done()

    context 'when runCommand fails with existing path', ->
      beforeEach ->
        output = '''
          mkdir tmp/bin
          Couldn't create directory: Failure
        ''' + '\nsftp> '
        sftp.runCommand.callsArgWith 1, output

      it 'returns an error', (done) ->
        sftp.mkdir 'tmp/bin', (err) ->
          expect(err).to.equal 'Couldn\'t create directory: Failure'
          done()

    context 'when there are some other types of error', ->
      beforeEach ->
        output = '''
          mkdir tmp/bin
          some random
          error message
        ''' + '\nsftp> '
        sftp.runCommand.callsArgWith 1, output

      it 'returns an error', (done) ->
        sftp.mkdir 'tmp/bin', (err) ->
          expect(err).to.equal '''
            some random
            error message
          '''
          done()

  describe '#rmdir', ->
    cbSpy = null

    beforeEach ->
      cbSpy = sinon.spy()
      sinon.stub sftp, 'runCommand'

    it 'calls runCommand with rmdir command', ->
      sftp.rmdir 'tmp', cbSpy
      expect(sftp.runCommand).to.have.been.calledWith "rmdir 'tmp'"

    context 'when runCommand succeeds', ->
      beforeEach ->
        output = '''
          rmdir tmp
        ''' + '\nsftp> '
        sftp.runCommand.callsArgWith 1, output

      it 'returns no errors', (done) ->
        sftp.rmdir 'tmp', (err) ->
          expect(err).not.to.exist
          done()

    context 'when runCommand fails with bad path', ->
      beforeEach ->
        output = '''
          rmdir tmp/bin
          Couldn't remove directory: No such file or directory
        ''' + '\nsftp> '
        sftp.runCommand.callsArgWith 1, output

      it 'returns an error', (done) ->
        sftp.rmdir 'tmp/bin', (err) ->
          expect(err).to.equal 'Couldn\'t remove directory: No such file or directory'
          done()

    context 'when there are some other types of error', ->
      beforeEach ->
        output = '''
          rmdir tmp/bin
          some random
          error message
        ''' + '\nsftp> '
        sftp.runCommand.callsArgWith 1, output

      it 'returns an error', (done) ->
        sftp.rmdir 'tmp/bin', (err) ->
          expect(err).to.equal '''
            some random
            error message
          '''
          done()

  describe '#get', ->
    cbSpy = null

    beforeEach ->
      cbSpy = sinon.spy()
      sinon.stub tmp, 'file'

    afterEach ->
      tmp.file.restore()

    doAction = ->
      sftp.get 'path/to/remote-file', cbSpy

    context 'when temp file creation fails', ->
      err = null

      beforeEach ->
        err = new Error 'some error'
        tmp.file.yields err
        doAction()

      it 'makes a callback with error', ->
        expect(cbSpy).to.have.been.calledWith err

    context 'when temp file creation succeeds', ->
      beforeEach ->
        tmp.file.yields null, '/tmp/action/tempfile'
        sinon.stub sftp, 'runCommand'

      it 'calls runCommand with get command', ->
        doAction()
        expect(sftp.runCommand).to.have.been.calledWith "get 'path/to/remote-file' '/tmp/action/tempfile'"

      context 'when runCommand succeeds', ->
        beforeEach ->
          output = '''
            get 'path/to/remote-file' '/tmp/action/tempfile'
            Fetching /home/foo/path/to/remote-file to remote-file
          ''' + '\nsftp> '
          sinon.stub fs, 'readFile'
          sinon.stub fs, 'unlink'
          sinon.stub childProcess, 'exec'
          sftp.runCommand.callsArgWith 1, output

        afterEach ->
          fs.readFile.restore()
          fs.unlink.restore()
          childProcess.exec.restore()

        context 'when exec succeeds', ->
          beforeEach ->
            childProcess.exec.callsArgWith 1, null, 'some file type'

          it 'reads the temp file', ->
            doAction()
            expect(fs.readFile).to.have.been.calledWith '/tmp/action/tempfile'
            expect(fs.unlink).not.to.have.been.called

          context 'when readFile succeeds', ->
            beforeEach ->
              fs.readFile.callsArgWith 1, null, new Buffer 'some file content'

            it 'returns no errors', (done) ->
              sftp.get 'path/to/remote-file', (err, data, fileType) ->
                expect(err).not.to.exist
                expect(data).to.be.an.instanceOf Buffer
                expect(fileType).to.equal 'some file type'
                expect(data.toString 'utf8').to.equal 'some file content'
                expect(fs.unlink).to.have.been.calledWith '/tmp/action/tempfile'
                done()

          context 'when readFile fails with error', ->
            beforeEach ->
              childProcess.exec.callsArgWith 1, null, 'some file type'
              fs.readFile.callsArgWith 1, new Error 'some error'

            it 'returns error', (done) ->
              sftp.get 'path/to/remote-file', (err, data, fileType) ->
                expect(err.toString()).to.contain 'some error'
                expect(data).not.to.exist
                expect(fileType).not.to.exist
                expect(fs.unlink).to.have.been.calledWith '/tmp/action/tempfile'
                done()

        context 'when exec fails with error', ->
          beforeEach ->
            childProcess.exec.callsArgWith 1, new Error 'mega error', null

          it 'returns error', (done) ->
            sftp.get 'path/to/remote-file', (err, data, fileType) ->
              expect(err.toString()).to.contain 'mega error'
              expect(data).not.to.exist
              expect(fileType).not.to.exist
              expect(fs.unlink).to.have.been.calledWith '/tmp/action/tempfile'
              done()

      context 'when runCommand fails with bad path', ->
        beforeEach ->
          output = '''
            get 'path/to/remote-file' '/tmp/action/tempfile'
            Couldn't stat remote file: No such file or directory
            File "/home/ubuntu/remote-file" not found
          ''' + '\nsftp> '
          sftp.runCommand.callsArgWith 1, output

        it 'returns an error', (done) ->
          sftp.get 'path/to/remote-file', (err) ->
            expect(err).to.equal '''
              Couldn\'t stat remote file: No such file or directory
              File "/home/ubuntu/remote-file" not found
            '''
            done()

      context 'when there are some other types of error', ->
        beforeEach ->
          output = '''
            get 'path/to/remote-file' '/tmp/action/tempfile'
            some random
            error message
            which spans more than 2 lines
          ''' + '\nsftp> '
          sftp.runCommand.callsArgWith 1, output

        it 'returns an error', (done) ->
          sftp.get 'path/to/remote-file', (err) ->
            expect(err).to.equal '''
              some random
              error message
              which spans more than 2 lines
            '''
            done()

  describe '#put', ->
    cbSpy = null
    buf = new Buffer 'some text'

    beforeEach ->
      cbSpy = sinon.spy()
      sinon.stub tmp, 'file'

    afterEach ->
      tmp.file.restore()

    doAction = ->
      sftp.put '/path/to/remote-file', buf, cbSpy

    context 'when temp file creation fails', ->
      err = null

      beforeEach ->
        err = new Error 'some error'
        tmp.file.yields err
        doAction()

      it 'makes a callback with error', ->
        expect(cbSpy).to.have.been.calledWith err

    context 'when temp file creation succeeds', ->
      beforeEach ->
        tmp.file.yields null, '/tmp/action/tempfile'
        sinon.stub fs, 'writeFile'

      afterEach ->
        fs.writeFile.restore()

      it 'attempts to write a given buffer into the temp file', ->
        doAction()
        expect(fs.writeFile).to.have.been.calledWith '/tmp/action/tempfile', buf

      context 'when writing a given buffer into the temp file succeeds', ->
        beforeEach ->
          fs.writeFile.callsArg 2
          sinon.stub sftp, 'runCommand'
          doAction()

        it 'calls runCommand with put command', ->
          expect(sftp.runCommand).to.have.been.calledWith "put '/tmp/action/tempfile' '/path/to/remote-file'"

        context 'when runCommand succeeds', ->
          beforeEach ->
            output = '''
              put /tmp/action/tempfile /path/to/remote-file
              Uploading tempfile to /path/to/remote-file
            ''' + '\nsftp> '
            sftp.runCommand.callsArgWith 1, output
            doAction()

          it 'returns no errors', ->
            expect(cbSpy).to.have.been.called
            expect(cbSpy.args[0][0]).not.to.exist

        context 'when runCommand fails with bad path', ->
          beforeEach ->
            output = '''
              put /tmp/action/tempfile /path/to/remote-file
              stat tempfile: No such file or directory
            ''' + '\nsftp> '
            sftp.runCommand.callsArgWith 1, output
            doAction()

          it 'returns an error', ->
            expect(cbSpy).to.have.been.calledWith 'stat tempfile: No such file or directory'

      context 'when writing the given buffer into the temp file fails', ->
        err = null

        beforeEach ->
          err = new Error 'some error'
          fs.writeFile.callsArgWith 2, err
          doAction()

        it 'makes a callback with error', ->
          expect(cbSpy).to.have.been.calledWith err

  describe '#rm', ->
    cbSpy = null

    beforeEach ->
      cbSpy = sinon.spy()
      sinon.stub sftp, 'runCommand'

    it 'calls runCommand with rm command', ->
      sftp.rm 'remote-file', cbSpy
      expect(sftp.runCommand).to.have.been.calledWith "rm 'remote-file'"

    context 'when runCommand succeeds', ->
      beforeEach ->
        output = '''
          rm remote-file
          Removing remote-file
        ''' + '\nsftp> '
        sftp.runCommand.callsArgWith 1, output

      it 'returns no errors', (done) ->
        sftp.rm 'remote-file', (err) ->
          expect(err).not.to.exist
          done()

    context 'when runCommand fails with bad path', ->
      beforeEach ->
        output = '''
          rm unknown-file
          Couldn't stat remote file: No such file or directory
          Removing /home/foo/unknown-file
          Couldn't delete file: No such file or directory
        ''' + '\nsftp> '
        sftp.runCommand.callsArgWith 1, output

      it 'returns an error', (done) ->
        sftp.rm 'unknow-file', (err) ->
          expect(err).to.equal '''
            Couldn't stat remote file: No such file or directory
            Removing /home/foo/unknown-file
            Couldn't delete file: No such file or directory
          '''
          done()

    context 'when runCommand fails with bad path', ->
      beforeEach ->
        output = '''
          rm unknown-file
          Failed to remove /home/foo/unknown-file
        ''' + '\nsftp> '
        sftp.runCommand.callsArgWith 1, output

      it 'returns an error', (done) ->
        sftp.rm 'unknow-file', (err) ->
          expect(err).to.equal '''
            Failed to remove /home/foo/unknown-file
          '''
          done()

    context 'when there are some other types of error', ->
      beforeEach ->
        output = '''
          rm remote-file
          some random
          error message
        ''' + '\nsftp> '
        sftp.runCommand.callsArgWith 1, output

      it 'returns an error', (done) ->
        sftp.rm 'remote-file', (err) ->
          expect(err).to.equal '''
            some random
            error message
          '''
          done()
