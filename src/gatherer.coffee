entities  = require './entities'
load      = require './load'
request   = require './request'
symbols   = require './symbols'


gatherer = module.exports

gatherer.card       = require './gatherer/card'
gatherer.languages  = require './gatherer/languages'
gatherer.printings  = require './gatherer/printings'
gatherer.set        = require './gatherer/set'

collect_options = (label) -> (callback) ->
  request url: 'http://gatherer.wizards.com/Pages/Default.aspx', (err, res, body) ->
    return callback err if err?
    return callback new Error 'unexpected status code' unless res.statusCode is 200
    try formats = extract body, label catch err then return callback err
    callback null, formats
  return

extract = (html, label) ->
  $ = load html
  id = "#ctl00_ctl00_MainContent_Content_SearchControls_#{label}AddText"
  values = ($(o).attr('value') for o in $(id).children())
  values = (entities.decode v for v in values when v)

gatherer.formats  = collect_options 'format'
gatherer.sets     = collect_options 'set'
gatherer.types    = collect_options 'type'

to_symbol = (alt) ->
  m = /^(\S+) or (\S+)$/.exec alt
  m and "#{to_symbol m[1]}/#{to_symbol m[2]}" or symbols[alt] or alt

gatherer._get_text = (node) ->
  node.find('img').each ->
    # TODO: make this reusable
    $ = jQuery ? (x) -> x
    $(this).replaceWith "{#{to_symbol $(this).attr 'alt'}}"
  node.text().trim()

identity = (value) -> value
gatherer._get_rules_text = (node, get_text) ->
  node.children().toArray().map(get_text).filter(identity).join('\n\n')

gatherer._get_versions = (image_nodes) ->
  versions = {}
  image_nodes.each ->
    [expansion, rarity] = /^(.*\S)\s+[(](.+)[)]$/.exec(@attr('alt'))[1..]
    expansion = entities.decode expansion
    versions[/\d+$/.exec @parent().attr('href')] = {expansion, rarity}
  versions

gatherer._set = (obj, key, value) ->
  obj[key] = value unless value is undefined or value isnt value

gatherer._to_stat = (str) ->
  num = +str?.replace('{1/2}', '.5')
  if num is num then num else str
