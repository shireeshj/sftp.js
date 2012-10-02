CommandQueue = require '../../lib/command_queue'

describe 'CommandQueue', ->
  queue = null

  beforeEach ->
    queue = new CommandQueue

  it 'initializes an empty queue array', ->
    expect(queue.items).to.deep.equal []

  describe '#enqueue', ->
    command = null

    context 'when there exists no item in the queue', ->
      beforeEach ->
        queue.items = []
        command = sinon.spy()
        queue.enqueue command

      it 'adds the command', ->
        expect(queue.items).to.deep.equal [command]

      it 'runs the command', ->
        expect(command).to.have.been.called

    context 'when there exists an item in the queue', ->
      existingCommand = null

      beforeEach ->
        existingCommand = sinon.spy()
        queue.items = [existingCommand]
        command = sinon.spy()
        queue.enqueue command

      it 'adds the command', ->
        expect(queue.items).to.deep.equal [existingCommand, command]

      it 'runs neither the existing command in the queue nor the newly enqueued command', ->
        expect(existingCommand).not.to.have.been.called
        expect(command).not.to.have.been.called

  describe '#dequeue', ->
    command = null

    context 'when there is only one item in the queue', ->
      beforeEach ->
        command = sinon.spy()
        queue.items = [command]
        queue.dequeue()

      it 'removes the first item in the queue', ->
        expect(queue.items).to.deep.equal []

      it 'does not run any command', ->
        expect(command).not.to.have.been.called

    context 'when there is more than one item in the queue', ->
      command2 = null

      beforeEach ->
        command = sinon.spy()
        command2 = sinon.spy()
        queue.items = [command, command2]
        queue.dequeue()

      it 'removes the first item in the queue', ->
        expect(queue.items).to.deep.equal [command2]

      it 'runs the next item in the queue (the new first item)', ->
        expect(command).not.to.have.been.called
        expect(command2).to.have.been.called

