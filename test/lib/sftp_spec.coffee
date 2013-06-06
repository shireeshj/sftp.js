SFTP = require '../../lib/sftp'
fs = require 'fs'
tmp = require 'tmp'
path = require 'path'

describe 'SFTP', ->
  @timeout 5000
  sftp = null
  privateKey = null
  testDir = null
  relativeTestDir = null
  home = null

  beforeEach ->
    home = process.env.HOME
    privateKey = fs.readFileSync process.env.HOME + '/.ssh/nopass_id_rsa', 'utf8'
    testDir = path.resolve(__dirname, "..")
    relativeTestDir = testDir.replace home, ""
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

    it 'considers remote prefix when generating outputs', (done) ->
      sftp.remotePrefix = home
      sftp.ls relativeTestDir, (err, data) ->
        expect(data).to.eql [
          ['fixtures', true, 4096],
          ['lib', true, 4096],
          ['mocha.opts', false, 92],
          ['spec_helper.coffee', false, 431],
        ]
        done()

    context 'when list a single file', ->
      it 'parses the output and generates an array of directories and files', (done) ->
        sftp.ls testDir + "/mocha.opts", (err, data) ->
          expect(data).to.eql [
            [path.join(testDir, 'mocha.opts'), false, 92],
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

    it 'considers remote prefix when creating directory', (done) ->
      sftp.remotePrefix = home
      newDir = relativeTestDir + "/tmp"
      sftp.mkdir newDir, (err, data) ->
        expect(fs.existsSync(path.join(home, newDir))).to.be.true
        fs.rmdirSync path.join(home, newDir)
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

    afterEach (done) ->
      fs.rmdir "/tmp/hello", -> done()

    it 'removes the directory', (done) ->
      sftp.rmdir '/tmp/hello', (err) ->
        expect(fs.existsSync('/tmp/hello')).to.be.false
        done()

    it 'considers remote prefix when removing the directory', (done) ->
      sftp.remotePrefix = home
      newDir = relativeTestDir + "/tmp"
      fs.mkdirSync path.join(home, newDir)
      sftp.rmdir newDir, (err, data) ->
        expect(fs.existsSync(path.join(home, newDir))).to.be.false
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

    it 'considers remote prefix when fetching the file', (done) ->
      sftp.remotePrefix = home
      testFile = relativeTestDir + "/fixtures/test.txt"
      sftp.get testFile, (err, data, fileType) ->
        expect(data.toString()).to.eql "This is a test file\n"
        expect(fileType).to.eql "ASCII text\n"
        done()

    it 'gets file with empty content', (done) ->
      newFile = testDir + "/fixtures/new.txt" 
      fs.openSync newFile, "w"
      sftp.get newFile, (err, data, fileType) ->
        fs.unlinkSync newFile
        expect(data.toString()).to.eql ""
        expect(fileType).to.eql "empty\n"
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

    it 'considers remote prefix when putting the file', (done) ->
      sftp.remotePrefix = home
      testFile = relativeTestDir + "/fixtures/tmp.txt"
      sftp.put localPath, testFile, (err) ->
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

    it 'considers remote prefix when saving the file', (done) ->
      sftp.remotePrefix = home
      testFile = relativeTestDir + "/fixtures/tmp.txt"
      sftp.putData testFile, "tmp content", (err) ->
        expect(err).to.be.nil
        expect(fs.readFileSync(remotePath).toString()).to.eql "tmp content"
        done()

    context "when the remote path does not exist and content is empty", ->
      it 'creates a empty file at remote path', (done) ->
        fs.unlink remotePath, ->
          sftp.putData remotePath, "", (err) ->
            expect(err).to.be.nil
            expect(fs.existsSync(remotePath)).to.be.true
            expect(fs.readFileSync(remotePath).toString()).to.be.empty
            done()

    context "when the remote path is not writable", ->
      beforeEach -> remotePath = testDir + "/fixtures"

      it 'returns an error', (done) ->
        sftp.putData remotePath, "tmp content", (err) ->
          expect(err).to.be.an.instanceOf Error
          done()

  describe '#rm', ->
    remotePath = null

    beforeEach (done) ->
      remotePath = testDir + "/fixtures/tmp.txt"
      fs.writeFileSync remotePath, "wow"
      sftp.connect -> done()

    afterEach (done) ->
      fs.unlink remotePath, -> done()

    it 'removes the remote path', (done) ->
      sftp.rm remotePath, (err) ->
        expect(err).to.be.nil
        expect(fs.existsSync(remotePath)).to.be.false
        done()

    it 'considers remote prefix when removing the file', (done) ->
      sftp.remotePrefix = home
      testFile = relativeTestDir + "/fixtures/tmp.txt"
      sftp.rm testFile, (err) ->
        expect(err).to.be.nil
        expect(fs.existsSync(remotePath)).to.be.false
        done()

    context 'when the path is invalid', ->
      invalidPath = null

      beforeEach (done) ->
        invalidPath = testDir + "/fixtures/invalid-file.txt"
        fs.unlink invalidPath, -> done()

      it 'returns an error', (done) ->
        sftp.rm invalidPath, (err) ->
          expect(err).to.be.an.instanceOf Error
          expect(err.message).to.eql "No such file"
          done()

  describe '#rename', ->
    remotePath = null
    newPath = null

    beforeEach (done) ->
      remotePath = testDir + "/fixtures/tmp.txt"
      newPath = testDir + "/fixtures/newtmp.txt"
      fs.writeFileSync remotePath, "wow"
      sftp.connect -> done()

    afterEach (done) ->
      fs.unlink remotePath, ->
        fs.unlink newPath, -> done()

    it 'renames the remote file', (done) ->
      sftp.rename remotePath, newPath, (err) ->
        expect(err).to.be.nil
        expect(fs.existsSync(remotePath)).to.be.false
        expect(fs.existsSync(newPath)).to.be.true
        expect(fs.readFileSync(newPath).toString()).to.eql "wow"
        done()

    it 'considers remote prefix when renaming the file', (done) ->
      sftp.remotePrefix = home
      testFile = relativeTestDir + "/fixtures/tmp.txt"
      newTestFile = relativeTestDir + "/fixtures/newtmp.txt"
      sftp.rename testFile, newTestFile, (err) ->
        expect(err).to.be.nil
        expect(fs.existsSync(remotePath)).to.be.false
        expect(fs.existsSync(newPath)).to.be.true
        expect(fs.readFileSync(newPath).toString()).to.eql "wow"
        done()

    context 'when the remotePath does not exist', ->
      beforeEach (done) ->
        fs.unlinkSync remotePath
        remotePath = testDir + "/fixtures/invalid-path.txt"
        fs.unlink remotePath, -> done()

      it 'returns an error', (done) ->
        sftp.rename remotePath, newPath, (err) ->
          expect(err).to.be.an.instanceOf Error
          expect(err.message).to.eql "No such file"
          expect(fs.existsSync(newPath)).to.be.false
          done()

  describe '#destroy', ->
    beforeEach (done) -> sftp.connect -> done()

    it 'ends the ssh connection', ->
      sftp.destroy()
      expect(sftp.ready).to.be.false
      expect(sftp.sftp).to.be.nil
