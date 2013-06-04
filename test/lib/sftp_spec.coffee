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

  describe '#destroy', ->
    it 'ends the ssh connection', ->

  #describe '#get', ->
  #  cbSpy = null

  #  beforeEach ->
  #    cbSpy = sinon.spy()
  #    sinon.stub tmp, 'file'

  #  afterEach ->
  #    tmp.file.restore()

  #  doAction = ->
  #    sftp.get 'path/to/remote-file', cbSpy

  #  context 'when temp file creation fails', ->
  #    err = null

  #    beforeEach ->
  #      err = new Error 'some error'
  #      tmp.file.yields err
  #      doAction()

  #    it 'makes a callback with error', ->
  #      expect(cbSpy).to.have.been.calledWith err

  #  context 'when temp file creation succeeds', ->
  #    fdSpy = null

  #    beforeEach ->
  #      fdSpy = sinon.spy()
  #      tmp.file.yields null, '/tmp/action/tempfile', fdSpy
  #      sinon.stub sftp, '_runCommand'
  #      sinon.stub fs, 'close'

  #    afterEach ->
  #      fs.close.restore()

  #    it 'closes the file descriptor', ->
  #      doAction()
  #      expect(fs.close).to.have.been.calledWith fdSpy

  #    it 'calls _runCommand with get command', ->
  #      doAction()
  #      expect(sftp._runCommand).to.have.been.calledWith "get 'path/to/remote-file' '/tmp/action/tempfile'"

  #    context 'when _runCommand succeeds', ->
  #      beforeEach ->
  #        output = '''
  #          get 'path/to/remote-file' '/tmp/action/tempfile'
  #          Fetching /home/foo/path/to/remote-file to remote-file
  #        ''' + '\nsftp> '
  #        sinon.stub fs, 'readFile'
  #        sinon.stub fs, 'unlink'
  #        sinon.stub childProcess, 'exec'
  #        sftp._runCommand.callsArgWith 1, output

  #      afterEach ->
  #        fs.readFile.restore()
  #        fs.unlink.restore()
  #        childProcess.exec.restore()

  #      it 'runs file command to determine file type', ->
  #        doAction()
  #        expect(childProcess.exec).to.have.been.calledWith "file -b '/tmp/action/tempfile'"

  #      context 'when file command succeeds', ->
  #        beforeEach ->
  #          childProcess.exec.callsArgWith 1, null, 'some file type'

  #        it 'reads the temp file', ->
  #          doAction()
  #          expect(fs.readFile).to.have.been.calledWith '/tmp/action/tempfile'
  #          expect(fs.unlink).not.to.have.been.called

  #        context 'when readFile succeeds', ->
  #          beforeEach ->
  #            fs.readFile.callsArgWith 1, null, new Buffer 'some file content'

  #          it 'returns no errors', (done) ->
  #            sftp.get 'path/to/remote-file', (err, data, fileType) ->
  #              expect(err).not.to.exist
  #              expect(data).to.be.an.instanceOf Buffer
  #              expect(fileType).to.equal 'some file type'
  #              expect(data.toString 'utf8').to.equal 'some file content'
  #              expect(fs.unlink).to.have.been.calledWith '/tmp/action/tempfile'
  #              done()

  #        context 'when readFile fails with error', ->
  #          error = null

  #          beforeEach ->
  #            error = new Error 'some error'
  #            childProcess.exec.callsArgWith 1, null, 'some file type'
  #            fs.readFile.callsArgWith 1, error

  #          it 'returns error', (done) ->
  #            sftp.get 'path/to/remote-file', (err, data, fileType) ->
  #              expect(err).to.equal error
  #              expect(data).not.to.exist
  #              expect(fileType).not.to.exist
  #              expect(fs.unlink).to.have.been.calledWith '/tmp/action/tempfile'
  #              done()

  #      context 'when exec fails with error', ->
  #        error = null

  #        beforeEach ->
  #          error = new Error 'some error'
  #          childProcess.exec.callsArgWith 1, error

  #        it 'returns error', (done) ->
  #          sftp.get 'path/to/remote-file', (err, data, fileType) ->
  #            expect(err).to.equal error
  #            expect(data).not.to.exist
  #            expect(fileType).not.to.exist
  #            expect(fs.unlink).to.have.been.calledWith '/tmp/action/tempfile'
  #            done()

  #    context 'when _runCommand fails with bad path', ->
  #      beforeEach ->
  #        output = '''
  #          get 'path/to/remote-file' '/tmp/action/tempfile'
  #          Couldn't stat remote file: No such file or directory
  #          File "/home/ubuntu/remote-file" not found
  #        ''' + '\nsftp> '
  #        sftp._runCommand.callsArgWith 1, output

  #      it 'returns an error', (done) ->
  #        sftp.get 'path/to/remote-file', (err) ->
  #          expect(err).to.be.an.instanceOf Error
  #          expect(err.message).to.equal '''
  #            Couldn\'t stat remote file: No such file or directory
  #            File "/home/ubuntu/remote-file" not found
  #          '''
  #          done()

  #    context 'when there are some other types of error', ->
  #      beforeEach ->
  #        output = '''
  #          get 'path/to/remote-file' '/tmp/action/tempfile'
  #          some random
  #          error message
  #          which spans more than 2 lines
  #        ''' + '\nsftp> '
  #        sftp._runCommand.callsArgWith 1, output

  #      it 'returns an error', (done) ->
  #        sftp.get 'path/to/remote-file', (err) ->
  #          expect(err).to.be.an.instanceOf Error
  #          expect(err.message).to.equal '''
  #            some random
  #            error message
  #            which spans more than 2 lines
  #          '''
  #          done()

  #describe '#_runPutCommand', ->
  #  cbSpy = null

  #  beforeEach ->
  #    cbSpy = sinon.spy()
  #    sinon.stub sftp, '_runCommand'

  #  doAction = (deleteAfterPut=false) ->
  #    sftp._runPutCommand '/local/path', '/remote/path', deleteAfterPut, cbSpy

  #  it 'calls _runCommand with put command', ->
  #    doAction()
  #    expect(sftp._runCommand).to.have.been.calledWith "put '/local/path' '/remote/path'"

  #    context 'when _runCommand callback is invoked', ->
  #      beforeEach ->
  #        sftp._runCommand.callsArgWith 1, ''
  #        sinon.stub fs, 'unlink'

  #      afterEach ->
  #        fs.unlink.restore()

  #      context 'when deleteAfterPut arg is true', ->
  #        beforeEach ->
  #          doAction true

  #        it 'deletes the local file', ->
  #          expect(fs.unlink).to.have.been.calledWith '/local/path'

  #      context 'when deleteAfterPut arg is false', ->
  #        beforeEach ->
  #          doAction false

  #        it 'does not the local file', ->
  #          expect(fs.unlink).not.to.have.been.calledWith '/local/path'

  #  context 'when _runCommand succeeds', ->
  #    beforeEach ->
  #      output = '''
  #        put /local/path /remote/path
  #        Uploading tempfile to /remote/path
  #      ''' + '\nsftp> '
  #      sftp._runCommand.callsArgWith 1, output
  #      doAction()

  #    it 'returns no errors', ->
  #      doAction()
  #      expect(cbSpy).to.have.been.called
  #      expect(cbSpy.args[0][0]).not.to.exist

  #  context 'when _runCommand fails with bad path', ->
  #    beforeEach ->
  #      output = '''
  #        put /local/path /remote/path
  #        stat tempfile: No such file or directory
  #      ''' + '\nsftp> '
  #      sftp._runCommand.callsArgWith 1, output
  #      doAction()

  #    it 'returns an error', ->
  #      expect(cbSpy).to.have.been.called
  #      expect(cbSpy.args[0][0]).to.be.an.instanceOf Error
  #      expect(cbSpy.args[0][0].message).to.equal 'stat tempfile: No such file or directory'

  #  context 'when _runCommand fails with some other error', ->
  #    beforeEach ->
  #      output = '''
  #        put /local/path /remote/path
  #        Uploading tempfile to /remote/path
  #        Connection Interrupted Due To Alien Invasion
  #      ''' + '\nsftp> '
  #      sftp._runCommand.callsArgWith 1, output
  #      doAction()

  #    it 'returns an error', ->
  #      expect(cbSpy).to.have.been.called
  #      expect(cbSpy.args[0][0]).to.be.an.instanceOf Error
  #      expect(cbSpy.args[0][0].message).to.equal '''
  #        Uploading tempfile to /remote/path
  #        Connection Interrupted Due To Alien Invasion
  #      '''

  #describe '#put', ->
  #  cbSpy = null

  #  beforeEach ->
  #    cbSpy = sinon.spy()
  #    sinon.stub fs, 'stat'

  #  afterEach ->
  #    fs.stat.restore()

  #  doAction = ->
  #    sftp.put '/local/path', '/remote/path', cbSpy

  #  it 'does fs.stat to check whether local file exists', ->
  #    doAction()
  #    expect(fs.stat).to.have.been.calledWith '/local/path'

  #  context 'when fs.stat returns error', ->
  #    err = null

  #    beforeEach ->
  #      err = new Error
  #      fs.stat.callsArgWith 1, err
  #      doAction()

  #    it 'makes a callback with error', ->
  #      expect(cbSpy).to.have.been.calledWith err

  #  context 'when fs.stat returns stat object', ->
  #    mockStats = null

  #    beforeEach ->
  #      mockStats = { isFile: sinon.stub() }
  #      fs.stat.callsArgWith 1, null, mockStats

  #    context 'when the path is not a file', ->
  #      beforeEach ->
  #        mockStats.isFile.returns false
  #        doAction()

  #      it 'makes a callback with error', ->
  #        expect(cbSpy).to.have.been.called
  #        expect(cbSpy.args[0][0]).to.be.an.instanceOf Error
  #        expect(cbSpy.args[0][0].message).to.equal 'local path does not point to a file'

  #    context 'when the path is a file', ->
  #      beforeEach ->
  #        sinon.stub sftp, '_runPutCommand'
  #        mockStats.isFile.returns true

  #      it 'calls _runPutCommand', ->
  #        doAction()
  #        expect(sftp._runPutCommand).to.have.been.calledWith '/local/path', '/remote/path', false, cbSpy

  #describe '#putData', ->
  #  cbSpy = null
  #  buf = new Buffer 'some text'

  #  beforeEach ->
  #    cbSpy = sinon.spy()
  #    sinon.stub tmp, 'file'

  #  afterEach ->
  #    tmp.file.restore()

  #  doAction = ->
  #    sftp.putData '/remote/path', buf, cbSpy

  #  context 'when temp file creation fails', ->
  #    err = null

  #    beforeEach ->
  #      err = new Error 'some error'
  #      tmp.file.yields err
  #      doAction()

  #    it 'makes a callback with error', ->
  #      expect(cbSpy).to.have.been.calledWith err

  #  context 'when temp file creation succeeds', ->
  #    fdSpy = null

  #    beforeEach ->
  #      fdSpy = sinon.spy()
  #      tmp.file.yields null, '/tmp/action/tempfile', fdSpy
  #      sinon.stub fs, 'writeFile'
  #      sinon.stub fs, 'close'

  #    afterEach ->
  #      fs.writeFile.restore()
  #      fs.close.restore()

  #    it 'closes the file descriptor', ->
  #      doAction()
  #      expect(fs.close).to.have.been.calledWith fdSpy

  #    it 'attempts to write a given buffer into the temp file', ->
  #      doAction()
  #      expect(fs.writeFile).to.have.been.calledWith '/tmp/action/tempfile', buf

  #    context 'when writing the given buffer into the temp file fails', ->
  #      err = null

  #      beforeEach ->
  #        err = new Error 'some error'
  #        fs.writeFile.callsArgWith 2, err
  #        doAction()

  #      it 'makes a callback with error', ->
  #        expect(cbSpy).to.have.been.calledWith err

  #    context 'when writing a given buffer into the temp file succeeds', ->
  #      beforeEach ->
  #        fs.writeFile.callsArg 2
  #        sinon.stub sftp, '_runPutCommand'

  #      it 'calls _runPutCommand', ->
  #        doAction()
  #        expect(sftp._runPutCommand).to.have.been.calledWith '/tmp/action/tempfile', '/remote/path', true, cbSpy

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
