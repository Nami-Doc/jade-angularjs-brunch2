jade = require 'jade'
sysPath = require 'path'
mkdirp  = require 'mkdirp'
fs = require 'fs'

fileWriter = (newFilePath) -> (err, content) ->
  throw err if err?
  return if not content?
  dirname = sysPath.dirname newFilePath
  mkdirp dirname, '0775', (err) ->
    throw err if err?
    fs.writeFile newFilePath, content, (err) -> throw err if err?

module.exports = class JadeAngularJsCompiler
  brunchPlugin: yes
  type: 'template'
  extension: 'jade'

  constructor: (config) ->
    @public = config.paths.public
    @pretty = !!config.plugins?.jade?.pretty
    @locals = config.plugins?.jade_angular?.locals
    @modulesFolder = config.plugins?.jade_angular?.modules_folder

  preparePair: (pair) ->
    pair.path.push(pair.path.pop()[...-@extension.length] + 'html')
    pair.path.splice 0, 1, @public

  writeStatic: (pair) ->
    @preparePair pair
    writer = fileWriter sysPath.join.apply(this, pair.path)
    writer null, pair.result

  setupModule: (pair) ->
    @preparePair pair
    pair.path.splice 1, 1, 'js'

    moduleFolderIndex = pair.path.lastIndexOf(@modulesFolder)+1
    modulePath = pair.path.slice 2, moduleFolderIndex

    if modulePath.length is 0
      modulePath.push @modulesFolder

    moduleName = modulePath.join '.'
    jsFileName = moduleName + '.js'
    copyfolder = pair.path.slice 0, 2
    copyfolder.push jsFileName

    virtualPathGen = =>
      virtualPath = modulePath.concat pair.path.slice moduleFolderIndex
      virtualPath = "/#{virtualPath.join '/'}"
      virtualPath = virtualPath.replace "/#{@modulesFolder}", ''
      virtualPath

    result =
      moduleName: moduleName
      modulePath: sysPath.join.apply this, copyfolder
      virtualPath: virtualPathGen()
      content: pair.result

  parseStringToJSArray: (str) ->
    stringArray = '['
    str.split('\n').map (e, i) ->
      stringArray += "\n'" + e.replace(/'/g, "\\'") + "',"
    stringArray += "''" + '].join("\\n")'

  writeModules: (modules) ->
    content = ""
    for own moduleName, templates of modules
      content += """
                angular.module('#{moduleName}', [])
                    .run(['$templateCache', function($templateCache) {\n
                """
      templates.map (e, i) =>
        inlineContent = @parseStringToJSArray(e.content)
        content +=  """
                      $templateCache.put('#{e.virtualPath}', #{inlineContent});\n
                    """

      content += "}]);\n\n"

    if content
      writer = fileWriter sysPath.join @public, 'js', 'templates.js'
      writer null, content

  #TODO: сделать async
  prepareResult: (compiled) ->
    pathes = (result.sourceFiles for result in compiled when result.path is sysPath.normalize('_public/js/dontUseMe'))[0]

    return [] if pathes is undefined

    pathes.map (e, i) => 
        data = fs.readFileSync e.path, 'utf8'
        content = jade.compile data,
          compileDebug: no,
          client: no,
          filename: e.path,
          pretty: @pretty

        result =
          path: e.path.split sysPath.sep
          result: content @locals

  onCompile: (compiled) ->
    preResult = @prepareResult compiled

    @writeStatic pair for pair in preResult \
      when pair.path.indexOf(@modulesFolder) is -1 and \
        pair.path.indexOf('assets') is -1

    modulesRows = (@setupModule pair for pair in preResult \
      when pair.path.indexOf(@modulesFolder) > -1 and \
        pair.path.indexOf('assets') is -1)

    modules = {}
    modulesRows.map (element, index) ->
      if Object.keys(modules).indexOf(element.moduleName) is -1
        modules[element.moduleName] = []
      modules[element.moduleName].push(element)

    @writeModules modules