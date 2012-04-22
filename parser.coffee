jsdom = require 'jsdom'
fs    = require 'fs'

gatherer_root = 'http://gatherer.wizards.com/Pages/'

symbols =
  White: 'W', 'Phyrexian White':  'W/P'
  Blue:  'U', 'Phyrexian Blue':   'U/P'
  Black: 'B', 'Phyrexian Black':  'B/P'
  Red:   'R', 'Phyrexian Red':    'R/P'
  Green: 'G', 'Phyrexian Green':  'G/P'
  Two:   '2', 'Variable Colorless': 'X'
  Snow:  'S'

to_symbol = (alt) ->
  match = /^(\S+) or (\S+)$/.exec alt
  if match and [match, a, b] = match then "#{to_symbol a}/#{to_symbol b}"
  else symbols[alt] or alt

{HTMLElement} = jsdom.dom.level3.html
Object.defineProperty HTMLElement.prototype, 'text', get: ->
  return '[' + to_symbol(@alt) + ']' if @nodeName is 'IMG'
  text = ''
  for node in @childNodes
    switch node.nodeType
      when 1 then text += node.text
      when 3 then text += node.nodeValue.trim()
  # Due to our aggressive trimming, mana symbols can end up touching
  # adjacent words: "[2/R]can be paid with any two mana or with[R]."
  text.replace(/[\w.](?=[[(])/g, '$& ').replace(/\](?=[(\w])/g, '] ')

get_name = (identifier) ->
  ($) ->
    name = $(identifier)[0]?.text
    # Extract, for example, "Altar's Reap" from "Altar’s Reap (Altar's Reap)".
    if (match = /^(.+)’(.+) [(](\1'\2)[)]$/.exec name) then match[3] else name

get_mana_cost = (identifier) ->
  ($) ->
    images = $(identifier).children().get()
    ('[' + to_symbol(alt) + ']' for {alt} in images).join('') if images.length

get_converted_mana_cost = (identifier) ->
  ($) -> +$(identifier)[0]?.text or 0

get_text = (identifier) ->
  ($) ->
    return unless (elements = $(identifier).children().get()).length
    # Ignore empty paragraphs.
    (el.text for el in elements).filter((paragraph) -> paragraph).join '\n\n'

get_versions = ($el) ->
  versions = {}
  $el.find('img').each ->
    [match, expansion, rarity] = /^(.*\S)\s+[(](.+)[)]$/.exec @alt
    versions[/\d+$/.exec @parentNode.href] = {expansion, rarity}
  versions

to_stat = (stat_as_string) ->
  stat_as_number = +stat_as_string
  # Use string representation if coercing to a number gives `NaN`.
  if stat_as_number is stat_as_number then stat_as_number else stat_as_string

common_attrs =

  name: get_name 'Card Name'

  mana_cost: get_mana_cost 'Mana Cost'

  converted_mana_cost: get_converted_mana_cost 'Converted Mana Cost'

  type: ($, data) ->
    return unless el = $('Types')[0]
    [match, type, subtype] = /^(.+?)(?:\s+\u2014\s+(.+))?$/.exec el.text
    data.type = type if type
    data.subtype = subtype if subtype
    return

  text: get_text 'Card Text'

  color_indicator: ($) ->
    $('Color Indicator')[0]?.text

  watermark: ($) ->
    $('Watermark')[0]?.text

  stats: ($, data) ->
    return unless el = $('P/T')[0]
    [match, power, toughness] = ///^([^/]+?)\s*/\s*([^/]+)$///.exec el.text
    data.power = to_stat power
    data.toughness = to_stat toughness
    return

  loyalty: ($) ->
    +$('Loyalty')[0]?.text

  versions: ($, {expansion, rarity}) ->
    versions = get_versions $('All Sets')
    return versions unless Object.keys(versions).length is 0

    if img = $('Expansion').find('img')[0]
      {expansion, rarity} = gid_specific_attrs
      if (expansion = expansion $) and (rarity = rarity $)
        versions[/\d+$/.exec img.parentNode.href] = {expansion, rarity}
    versions

  rulings: ($, data, jQuery) ->
    rulings = []
    jQuery('.cardDetails').find('tr.post').each ->
      return unless ($td = jQuery(this).children()).length is 2
      [match, month, date, year] = /(\d+)\/(\d+)\/(\d+)/.exec $td.get(0).text
      month = "0#{month}" if month.length is 1
      date = "0#{date}" if date.length is 1
      text = $td.get(1).textContent.trim().replace(/[{](.+?)[}]/g, '[$1]')
      rulings.push ["#{year}-#{month}-#{date}", text.replace(/[ ]{2,}/g, ' ')]
    rulings

gid_specific_attrs =

  flavor_text: ($, data) ->
    return unless ($flavor = $('Flavor Text')).length
    $children = $flavor.children()
    if match = /^\u2014(.+)$/.exec $children.get(-1).text
      data.flavor_text_attribution = match[1]
      $children.last().remove()
    (/^"(.+)"$/.exec(text = $flavor[0].text) or [])[1] or text

  expansion: ($) ->
    $('Expansion').find('a:last-child')[0]?.text

  rarity: ($) ->
    $('Rarity')[0]?.text

  number: ($) ->
    +$('Card #')[0]?.text

  artist: ($) ->
    $('Artist')[0]?.text

get_gatherer_id = ($) ->
  match = /multiverseid=(\d+)/.exec $('.cardTitle').find('a').attr('href')
  +match[1]

list_view_attrs =

  name: get_name '.cardTitle'

  mana_cost: get_mana_cost '.manaCost'

  converted_mana_cost: get_converted_mana_cost '.convertedManaCost'

  type: ($, data) ->
    return unless el = $('.typeLine')[0]
    regex = ///^
      ([^\u2014]+?)             # type
      (?:\s+\u2014\s+(.+?))?    # subtype
      (?:\s+[(](?:              # "("
        ([^/]+?)\s*/\s*([^/]+)  # power and toughness
        |                       # or...
        (\d+)                   # loyalty
      )[)])?                    # ")"
    $///
    [match, type, subtype, power, toughness, loyalty] = regex.exec el.text
    data.type = type
    data.subtype = subtype
    data.power = to_stat power
    data.toughness = to_stat toughness
    data.loyalty = +loyalty
    return

  text: get_text '.rulesText'

  expansion: ($) -> list_view_attrs.versions($)[get_gatherer_id($)].expansion

  rarity: ($) -> list_view_attrs.versions($)[get_gatherer_id($)].rarity

  gatherer_url: ($) ->
    id = get_gatherer_id($)
    gatherer_root + 'Card/Details.aspx?multiverseid=' + id

  versions: ($) -> get_versions $('.setVersions')

jquery_172 = fs.readFileSync("./jquery-1.7.2.min.js").toString()

exports.card = (body, callback) ->
  jsdom.env
    html: body
    src: [jquery_172]
    done: (errors, {jQuery}) ->
      $ = (label) -> jQuery('.label').filter(-> @text is label + ':').next()
      attach_attrs = (attrs, data) ->
        for own key, fn of attrs
          result = fn($, data, jQuery)
          data[key] = result unless result is undefined
        data
      data = attach_attrs common_attrs, {}
      data.gatherer_url = gatherer_root + 'Card/' + jQuery('#aspnetForm').attr('action')

      if /multiverseid/.test data.gatherer_url
        data = attach_attrs gid_specific_attrs, data

      for own key, value of data
        delete data[key] if value is undefined or value isnt value # NaN
      process.nextTick ->
        callback null, data

exports.set = (body, callback) ->
  jsdom.env
    html: body
    src: [jquery_172]
    done: (errors, {jQuery}) ->
      $ = (el) -> (selector) -> jQuery(el).find(selector)
      pages = do ->
        for {text} in jQuery('.paging').find('a').get().reverse()
          return number if (number = +text) > 0
        1

      # Gatherer returns the last page of results for a specified page
      # parameter beyond the upper bound. This is undesirable behaviour;
      # 404 is the appropriate response in such cases.
      #
      # Requests for nonexistent sets receive 404 responses, also.
      $el = jQuery('#ctl00_ctl00_ctl00_MainContent_SubContent_topPagingControlsContainer')
      page = +$el.children('a[style="text-decoration: underline;"]').text()
      requested_page = +jQuery('#aspnetForm').attr('action').match(/page=(\d+)/)?[1]+1
      if requested_page is page
        cards = []
        jQuery('.cardItem').each ->
          card = {}
          for own key, fn of list_view_attrs
            result = fn $(this), card
            card[key] = result unless result is undefined
          for own key, value of card
            delete card[key] if value is undefined or value isnt value # NaN
          cards.push card
        [error, data] = [null, {page, pages, cards}]
      else
        error = 'Not Found'
        data = {error, status: 404}
      process.nextTick ->
        callback error, data

collect_options = (label) ->
  (body, callback) ->
    jsdom.env html: body, src: [jquery_172], done: (errors, {jQuery}) ->
      id = "#ctl00_ctl00_MainContent_Content_SearchControls_#{label}AddText"
      $options = jQuery(id).children('option')
      process.nextTick ->
        callback null, (value for {value} in $options when value)

exports.sets    = collect_options 'set'
exports.formats = collect_options 'format'
exports.types   = collect_options 'type'