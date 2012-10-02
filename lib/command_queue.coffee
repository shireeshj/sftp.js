module.exports = class CommandQueue
  constructor: ->
    @items = []

  enqueue: (command) ->
    @items.push command
    command() if @items.length == 1

  dequeue: ->
    @items.shift()
    @items[0]() if @items.length > 0

