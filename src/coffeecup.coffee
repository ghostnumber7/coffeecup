# **CoffeeCup** lets you to write HTML templates in 100% pure
# [CoffeeScript](http://coffeescript.org).
#
# You can run it on [node.js](http://nodejs.org) or the browser, or compile your
# templates down to self-contained javascript functions, that will take in data
# and options and return generated HTML on any JS runtime.
#
# The concept is directly stolen from the amazing
# [Markaby](http://markaby.rubyforge.org/) by Tim Fletcher and why the lucky
# stiff.

if window?
  coffeecup = window.coffeecup = {}
  coffee = if CoffeeScript? then CoffeeScript else null
else
  coffeecup = exports
  coffee = require 'coffee-script'
  compiler = require __dirname + '/compiler'
  compiler.setup coffeecup
  fs = require 'fs'

coffeecup.version = '0.3.21'

# Values available to the `doctype` function inside a template.
# Ex.: `doctype 'strict'`
coffeecup.doctypes =
  'default': '<!DOCTYPE html>'
  '5': '<!DOCTYPE html>'
  'xml': '<?xml version="1.0" encoding="utf-8" ?>'
  'transitional': '<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">'
  'strict': '<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">'
  'frameset': '<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Frameset//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-frameset.dtd">'
  '1.1': '<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.1//EN" "http://www.w3.org/TR/xhtml11/DTD/xhtml11.dtd">',
  'basic': '<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML Basic 1.1//EN" "http://www.w3.org/TR/xhtml-basic/xhtml-basic11.dtd">'
  'mobile': '<!DOCTYPE html PUBLIC "-//WAPFORUM//DTD XHTML Mobile 1.2//EN" "http://www.openmobilealliance.org/tech/DTD/xhtml-mobile12.dtd">'
  'ce': '<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN" "ce-html-1.0-transitional.dtd">'

# CoffeeScript-generated JavaScript may contain anyone of these; but when we
# take a function to string form to manipulate it, and then recreate it through
# the `Function()` constructor, it loses access to its parent scope and
# consequently to any helpers it might need. So we need to reintroduce these
# inside any "rewritten" function.
coffeescript_helpers = """
  var __slice = Array.prototype.slice;
  var __hasProp = Object.prototype.hasOwnProperty;
  var __bind = function(fn, me){ return function(){ return fn.apply(me, arguments); }; };
  var __extends = function(child, parent) {
    for (var key in parent) { if (__hasProp.call(parent, key)) child[key] = parent[key]; }
    function ctor() { this.constructor = child; }
    ctor.prototype = parent.prototype; child.prototype = new ctor; child.__super__ = parent.prototype;
    return child; };
  var __indexOf = Array.prototype.indexOf || function(item) {
    for (var i = 0, l = this.length; i < l; i++) {
      if (this[i] === item) return i;
    } return -1; };
""".replace /\n/g, ''

# Private HTML element reference.
# Please mind the gap (1 space at the beginning of each subsequent line).
elements =
  # Valid HTML 5 elements requiring a closing tag.
  # Note: the `var` element is out for obvious reasons, please use `tag 'var'`.
  regular: 'a abbr address article aside audio b bdi bdo blockquote body button
 canvas caption cite code colgroup datalist dd del details dfn div dl dt em
 fieldset figcaption figure footer form h1 h2 h3 h4 h5 h6 head header hgroup
 html i iframe ins kbd label legend li main map mark menu meter nav noscript object
 ol optgroup option output p pre progress q rp rt ruby s samp script section
 select small span strong style sub summary sup table tbody td textarea tfoot
 th thead time title tr u ul video'

 # Support for SVG 1.1 tags
  svg: 'a altGlyph altGlyphDef altGlyphItem animate animateColor animateMotion
 animateTransform circle clipPath color-profile cursor defs desc ellipse
 feBlend feColorMatrix feComponentTransfer feComposite feConvolveMatrix
 feDiffuseLighting feDisplacementMap feDistantLight feFlood feFuncA feFuncB
 feFuncG feFuncR feGaussianBlur feImage feMerge feMergeNode feMorphology
 feOffset fePointLight feSpecularLighting feSpotLight feTile feTurbulence
 filter font font-face font-face-format font-face-name font-face-src
 font-face-uri foreignObject g glyph glyphRef hkern image line linearGradient
 marker mask metadata missing-glyph mpath path pattern polygon polyline
 radialGradient rect script set stop style svg symbol text textPath
 title tref tspan use view vkern'

  # Valid self-closing HTML 5 elements.
  void: 'area base br col command embed hr img input keygen link meta param
 source track wbr'

  # Support for xml sitemap elements
  xml: 'urlset url loc lastmod changefreq priority'

  obsolete: 'applet acronym bgsound dir frameset noframes isindex listing
 nextid noembed plaintext rb strike xmp big blink center font marquee multicol
 nobr spacer tt'

  obsolete_void: 'basefont frame'

# Create a unique list of element names merging the desired groups.
merge_elements = (args...) ->
  result = []
  for a in args
    for element in elements[a].split ' '
      result.push element unless element in result
  result

# Public/customizable list of possible elements.
# For each name in this list that is also present in the input template code,
# a function with the same name will be added to the compiled template.
coffeecup.tags = merge_elements 'regular', 'obsolete', 'void', 'obsolete_void',
  'svg', 'xml'

# Public/customizable list of elements that should be rendered self-closed.
coffeecup.self_closing = merge_elements 'void', 'obsolete_void'

# This is the basic material from which compiled templates will be formed.
# It will be manipulated in its string form at the `coffeecup.compile` function
# to generate the final template function.
skeleton = (data = {}) ->
  # Whether to generate formatted HTML with indentation and line breaks, or
  # just the natural "faux-minified" output.
  data.format ?= off

  # Whether to autoescape all content or let you handle it on a case by case
  # basis with the `h` function.
  data.autoescape ?= off

  # Internal coffeecup stuff.
  __cc =
    buffer: []

    esc: (txt) ->
      if data.autoescape then h(txt) else txt.toString()

    tabs: 0

    repeat: (string, count) -> Array(count + 1).join string

    indent: -> text @repeat('  ', @tabs) if data.format

    # Adapter to keep the builtin tag functions DRY.
    tag: (name, args) ->
      combo = [name]
      combo.push i for i in args
      tag.apply data, combo

    render_idclass: (str) ->
      classes = []

      for i, idx in str.split '.' when i isnt ''
        # look for an id in the first part
        if idx is 0 and i.indexOf('#') is 0
          id = i.slice(1)
        else
          classes.push i

      text " id=\"#{id}\"" if id

      if classes.length > 0
        text " class=\""
        for c in classes
          text ' ' unless c is classes[0]
          text c
        text '"'

    render_attrs: (obj, prefix = '') ->
      for k, v of obj
        # `true` is rendered as `selected="selected"`.
        v = k if typeof v is 'boolean' and v

        # Functions are rendered in an executable form.
        v = "(#{v}).call(this);" if typeof v is 'function'

        # Prefixed attribute.
        if typeof v is 'object' and v not instanceof Array
          # `data: {icon: 'foo'}` is rendered as `data-icon="foo"`.
          @render_attrs(v, prefix + k + '-')
        # `undefined`, `false` and `null` result in the attribute not being rendered.
        else if v or v==0 or v==''
          # strings, numbers, arrays and functions are rendered "as is".
          text " #{prefix + k}=\"#{@esc(v)}\""

    render_contents: (contents, safe) ->
      safe ?= false
      switch typeof contents
        when 'string', 'number', 'boolean'
          text if safe then contents else @esc(contents)
        when 'function'
          text '\n' if data.format
          @tabs++
          result = contents.call data
          if typeof result is 'string'
            @indent()
            text if safe then result else @esc(result)
            text '\n' if data.format
          @tabs--
          @indent()

    render_tag: (name, idclass, attrs, inline, contents) ->
      @indent()

      text "<#{name}"
      @render_idclass(idclass) if idclass
      @render_attrs(attrs) if attrs

      text " #{inline}" if inline

      if name in @self_closing
        text ' />'
        text '\n' if data.format
      else
        text '>'

        @render_contents(contents)

        text "</#{name}>"
        text '\n' if data.format

      null

  tag = (name, args...) ->
    for a in args
      switch typeof a
        when 'function'
          contents = a
        when 'object'
          attrs = a
        when 'number', 'boolean'
          contents = a
        when 'string'
          if args.length is 1
            contents = a
          else
            if a is args[0]
              first   = a.charAt(0)
              if first == '#' || first == '.'
                idclass = a.substr(0, a.indexOf(' '))
                inline = a.substr(a.indexOf(' ') + 1)
                if idclass == ''
                  idclass = inline
                  inline = undefined
              else
                inline  = a
                inline  = undefined if inline == ''
            else
              contents = a

    __cc.render_tag(name, idclass, attrs, inline, contents)

  cede = (f) ->
    temp_buffer = []
    old_buffer = __cc.buffer
    __cc.buffer = temp_buffer
    f()
    __cc.buffer = old_buffer
    temp_buffer.join ''

  h = (txt) ->
    txt.toString().replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')

  doctype = (type = 'default') ->
    text __cc.doctypes[type]
    text '\n' if data.format

  text = (txt) ->
    __cc.buffer.push txt.toString()
    null

  comment = (cmt) ->
    text "<!--#{cmt}-->"
    text '\n' if data.format

  coffeescript = (param) ->
    switch typeof param
      # `coffeescript -> alert 'hi'` becomes:
      # `<script>;(function () {return alert('hi');})();</script>`
      when 'function'
        script "#{__cc.coffeescript_helpers}(#{param}).call(this);"
      # `coffeescript "alert 'hi'"` becomes:
      # `<script type="text/coffeescript">alert 'hi'</script>`
      when 'string'
        script type: 'text/coffeescript', -> param
      # `coffeescript src: 'script.coffee'` becomes:
      # `<script type="text/coffeescript" src="script.coffee"></script>`
      when 'object'
        param.type = 'text/coffeescript'
        script param

  # Conditional IE comments.
  ie = (condition, contents) ->
    __cc.indent()

    text "<!--[if #{condition}]>"
    __cc.render_contents(contents)
    text "<![endif]-->"
    text '\n' if data.format

  null

# Stringify the skeleton and unwrap it from its enclosing `function(){}`, then
# add the CoffeeScript helpers.
skeleton = skeleton.toString()
  .replace(/function\s*\(.*\)\s*\{/, '')
  .replace(/return null;\s*\}$/, '')

skeleton = coffeescript_helpers + skeleton

# Compiles a template into a standalone JavaScript function.
coffeecup.compile = (template, options = {}) ->
  # The template can be provided as either a function or a CoffeeScript string
  # (in the latter case, the CoffeeScript compiler must be available).
  if typeof template is 'function' then template = template.toString()
  else if typeof template is 'string' and coffee?
    template = coffee.compile template, bare: yes
    template = "function(){#{template}}"

  # If an object `hardcode` is provided, insert the stringified value
  # of each variable directly in the function body. This is a less flexible but
  # faster alternative to the standard method of using `with` (see below).
  hardcoded_locals = ''

  if options.hardcode
    for k, v of options.hardcode
      if typeof v is 'function'
        # Make sure these functions have access to `data` as `@/this`.
        hardcoded_locals += "var #{k} = function(){return (#{v}).apply(data, arguments);};"
      else hardcoded_locals += "var #{k} = #{JSON.stringify v};"

  # If `optimize` is set on the options hash, use uglify-js to parse the
  # template function's code and optimize it using static analysis.
  if options.optimize and compiler?
    return compiler.compile template, hardcoded_locals, options

  # Add a function for each tag this template references. We don't want to have
  # all hundred-odd tags wasting space in the compiled function.
  tag_functions = ''
  tags_used = []

  for t in coffeecup.tags
    if template.indexOf(t) > -1 or hardcoded_locals.indexOf(t) > -1
      tags_used.push t

  tag_functions += "var #{tags_used.join ','};"
  for t in tags_used
    tag_functions += "#{t} = function(){return __cc.tag('#{t}', arguments);};"

  # Main function assembly.
  code = tag_functions + hardcoded_locals + skeleton

  code += "__cc.doctypes = #{JSON.stringify coffeecup.doctypes};"
  code += "__cc.coffeescript_helpers = #{JSON.stringify coffeescript_helpers};"
  code += "__cc.self_closing = #{JSON.stringify coffeecup.self_closing};"

  # If `locals` is set, wrap the template inside a `with` block. This is the
  # most flexible but slower approach to specifying local variables.
  code += 'with(data.locals){' if options.locals
  code += "(#{template}).call(data);"
  code += '}' if options.locals
  code += "return __cc.buffer.join('');"

  new Function('data', code)

cache = {}

# Template in, HTML out. Accepts functions or strings as does `coffeecup.compile`.
#
# Accepts an option `cache`, by default `false`. If set to `false` templates will
# be recompiled each time.
#
# `options` is just a convenience parameter to pass options separately from the
# data, but the two will be merged and passed down to the compiler (which uses
# `locals` and `hardcode`), and the template (which understands `locals`, `format`
# and `autoescape`).
coffeecup.render = (template, data = {}, options = {}) ->
  data[k] = v for k, v of options
  data.cache ?= off

  # Do not optimize templates if the cache is disabled, as it will slow
  # everything down considerably.
  if data.optimize and not data.cache then data.optimize = no

  if data.cache and cache[template]? then tpl = cache[template]
  else if data.cache then tpl = cache[template] = coffeecup.compile(template, data)
  else tpl = coffeecup.compile(template, data)
  tpl(data)

unless window?
  coffeecup.__express = (path, options = {}, fn) ->
    if options.optimize and not options.cache then options.optimize = no

    render = (tpl) ->
      try
        fn null, tpl(options)
      catch err
        fn err

    if options.cache and cache[path]?
      tpl = cache[path]
      render(tpl)
    else
      fs.readFile path, 'utf8', (err, str) ->
        if err then return fn err
        try
          tpl = coffeecup.compile(str,options)
        catch err
          return fn err

        if options.cache then cache[path] = tpl
        render(tpl)

  coffeecup.adapters =
    # Legacy adapters for when coffeecup expected data in the `context` attribute.
    simple: coffeecup.render
    meryl: coffeecup.render

    express:
      TemplateError: class extends Error
        constructor: (@message) ->
          Error.call this, @message
          Error.captureStackTrace this, arguments.callee
        name: 'TemplateError'

      compile: (template, data) ->
        # Allows `partial 'foo'` instead of `text @partial 'foo'`.
        data.hardcode ?= {}
        data.hardcode.partial = ->
          text @partial.apply @, arguments

        TemplateError = @TemplateError
        try tpl = coffeecup.compile(template, data)
        catch e then throw new TemplateError "Error compiling #{data.filename}: #{e.message}"

        return ->
          try tpl arguments...
          catch e then throw new TemplateError "Error rendering #{data.filename}: #{e.message}"
