###
The nesh command, which parses options and then drops the user
into an interactive session.
###
_ = require 'underscore'
{exec} = require 'child_process'
fs = require 'fs'
nesh = require './nesh'
path = require 'path'

argparse = require('argparse')
#argparse = require('argcoffee')
parser = new argparse.ArgumentParser()
parser.addArgument(['-c', '--coffee'], {action:'storeTrue', help:'Load CoffeeScript; shortcut for -l coffee'})
parser.addArgument(['--disable'], {nargs:'+', help:'Disable plugin(s) for autoload', metavar:'MODULE'})
parser.addArgument(['-e', '--eval'], {help:'Filename or string to eval in the REPL context'})
parser.addArgument(['--enable'], {nargs:'+', help:'Enable plugin(s) for autoload', metavar:'MODULE'})
parser.addArgument(['-l', '--language'], {help:'Set interpreter language'})
parser.addArgument(['--list-languages'], {action:'storeTrue', help:'List available languages'})
parser.addArgument(['-p', '--prompt'], {help:'Set prompt string '})
parser.addArgument(['--plugins'], {action:'storeTrue', help:'List auto-loaded plugins'})
parser.addArgument(['--version'], {action:'storeTrue', help:'Show version and exit'})
parser.addArgument(['--verbose'], {action:'storeTrue', help:'Enable verbose debug output'})
parser.addArgument(['-w', '--welcome'], {help:'Set welcome message'})

# what should we do about extra strings?
# option 1 - raise error if there is anything extra
#    argv = parser.parseArgs()
# option 2 - put everything extra in an attribute
#    [argv,rest] = parser.parseKnownArgs()
#    argv._ = rest
# option 3 - define a positional '*' take extras
#    SUPPRESS keeps it out of the usage/help
#    unknown optionals (--) will still give error
#    parser.addArgument(['_'], {nargs:'*', help: argparse.Const.SUPPRESS})
# option 4 - use REMAINDER to define the positional
#    once it 'starts' it takes everything, including option like
#    parser.addArgument(['_'], {nargs:'...', help: argparse.Const.SUPPRESS})
# can we do anything meaningful with argv._?  Like passing it to the REPL?
# REPL can use process.argv

parser.addArgument(['_'], {nargs:'*', help: argparse.Const.SUPPRESS})
argv = parser.parseArgs()

# what to do with unrecognized args?
if argv.verbose
    console.log argv

if argv.help
    optimist.showHelp()
    return

if argv.version
    nesh.log.info "nesh version #{nesh.version}"
    return

if argv.list_languages
    nesh.log.info nesh.languages().join ', '
    return

if argv.verbose
    # Verbose output, so set the log level to debug
    nesh.log.level = nesh.log.DEBUG

nesh.config.load()

if argv.enable?
    # Enable a new plugin, installing it if needed. This updates the user's
    # Nesh configuration file.
    enabled = argv.enable

    install = enabled.filter (item) ->
        not fs.existsSync "./plugins/#{item}.js"

    prefix = path.join nesh.config.home, '.nesh_modules'
    if install.length
        # Install via NPM into a custom location
        exec "npm --prefix=#{prefix} --color=always install #{install.join ' '} 2>&1", (err, stdout) ->
            nesh.log.info stdout
            throw err if err

    config = nesh.config.get()
    config.plugins ?= []
    config.plugins = _(config.plugins.concat enabled).uniq()
    config.pluginsExclude ?= []
    config.pluginsExclude = _(config.pluginsExclude).reject (item) -> item in enabled

    nesh.config.save()
    # Exit after installation/removal of plugins
    return

if argv.disable?
    # Disable a plugin, removing it if needed. This updates the user's
    # Nesh configuration file.
    disabled = argv.disable

    prefix = path.join nesh.config.home, '.nesh_modules'
    uninstall = disabled.filter (item) ->
        fs.existsSync path.join(prefix, 'node_modules', item)

    if uninstall.length
        # Remove via NPM
        exec "npm --prefix=#{prefix} --color=always rm #{uninstall.join ' '} 2>&1", (err, stdout) ->
            nesh.log.info stdout
            throw err if err

    config = nesh.config.get()
    config.plugins ?= []
    config.plugins = _(config.plugins).reject (item) -> item in disabled
    config.pluginsExclude ?= []
    config.pluginsExclude = _(config.pluginsExclude.concat disabled).uniq()

    nesh.config.save()
    return

if argv.coffee
    # Shortcut for CoffeeScript
    argv.language = 'coffee'

if argv.language
    nesh.loadLanguage argv.language

opts = {}
opts.prompt = argv.prompt if argv.prompt?
opts.welcome = argv.welcome if argv.welcome?

if argv.eval
    isJs = false
    if fs.existsSync argv.eval
        isJs = argv.eval[-3..] is '.js'
        opts.evalData = fs.readFileSync argv.eval, 'utf-8'
    else
        opts.evalData = argv.eval

    # If we are evaluating code, and it's either from a string or
    # from a file not ending in `.js`, and a non-js language is
    # set, then we need to compile it to js first.
    if not isJs and nesh.compile
        nesh.log.debug 'Compiling eval data'
        opts.evalData = nesh.compile opts.evalData

# Initialize and autoload plugins
nesh.init true, (err) ->
    return nesh.log.error err if err

    # Print plugin info?
    if argv.plugins
        for plugin in nesh.plugins
            nesh.log.info "#{plugin.name}: " + "#{plugin.description}".grey
        return

    # Start the REPL!
    nesh.start opts, (err) ->
        nesh.log.error err if err
