gatherer  = require './gatherer'


tutor = module.exports
window.tutor = tutor unless typeof window is 'undefined'

tutor[name] = gatherer[name] for name in [
  'formats'
  'set'
  'sets'
  'types'
]

tutor.card = (details, callback) ->
  switch typeof details
    when 'number' then details = id: details
    when 'string' then details = name: details

  card = languages = legality = null
  get = (fn) -> (err, data) ->
    fn data
    if err
      callback err
      callback = ->
    else if card? and languages? and legality?
      card.languages = languages
      card.legality = legality
      callback null, card

  gatherer.card details, get (data) -> card = data
  gatherer.languages details, get (data) -> languages = data
  gatherer.printings details, get (data) -> {legality} = data
